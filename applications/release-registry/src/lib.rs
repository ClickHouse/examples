pub mod database;
use axum::{
    Extension, Json, Router,
    extract::{DefaultBodyLimit, Path, Query, Request, State},
    http::StatusCode,
    middleware::{self, Next},
    response::{IntoResponse, Response},
    routing::{get, post},
};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use sqlx::{FromRow, PgPool, types::Json as DbJson};
use std::{collections::BTreeMap, sync::Arc};
use subtle::ConstantTimeEq;
use uuid::Uuid;

#[derive(Clone)]
pub struct AppState {
    pub pool: PgPool,
    tokens: Arc<Vec<([u8; 32], Uuid)>>,
}
pub fn tokens(raw: &str) -> Result<Vec<([u8; 32], Uuid)>, database::BoxError> {
    let values: BTreeMap<Uuid, String> = serde_json::from_str(raw)?;
    if values.is_empty() || values.len() > 20 {
        return Err("Configure 1-20 projects".into());
    }
    let mut tokens = Vec::new();
    for (id, token) in values {
        if token.len() < 32 || token.len() > 256 || token.chars().any(char::is_whitespace) {
            return Err("Invalid project token".into());
        }
        let hash: [u8; 32] = Sha256::digest(token.as_bytes()).into();
        if tokens.iter().any(|(existing, _)| *existing == hash) {
            return Err("Duplicate project token".into());
        }
        tokens.push((hash, id));
    }
    Ok(tokens)
}
pub async fn app(pool: PgPool, raw_tokens: &str) -> Result<Router, database::BoxError> {
    let tokens = tokens(raw_tokens)?;
    for (_, id) in &tokens {
        let exists: bool =
            sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM registry.projects WHERE id=$1)")
                .bind(id)
                .fetch_one(&pool)
                .await?;
        if !exists {
            return Err("Configured project is not seeded".into());
        }
    }
    let state = AppState {
        pool,
        tokens: Arc::new(tokens),
    };
    Ok(Router::new()
        .route("/releases", post(register).get(list))
        .route("/releases/{version}", get(inspect))
        .route("/channels/{name}", get(channel).put(promote))
        .route_layer(middleware::from_fn_with_state(state.clone(), authenticate))
        .route("/health", get(health))
        .layer(DefaultBodyLimit::max(8192))
        .with_state(state))
}
async fn authenticate(State(state): State<AppState>, mut request: Request, next: Next) -> Response {
    let token = request
        .headers()
        .get("Authorization")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.strip_prefix("Bearer "));
    let Some(token) = token.filter(|v| v.len() <= 256) else {
        return ApiError(StatusCode::UNAUTHORIZED, "Invalid token").into_response();
    };
    let hash: [u8; 32] = Sha256::digest(token.as_bytes()).into();
    let mut project = None;
    for (expected, id) in state.tokens.iter() {
        if bool::from(hash.ct_eq(expected)) {
            project = Some(*id);
        }
    }
    let Some(project) = project else {
        return ApiError(StatusCode::UNAUTHORIZED, "Invalid token").into_response();
    };
    request.extensions_mut().insert(project);
    next.run(request).await
}
#[derive(Debug)]
pub struct ApiError(StatusCode, &'static str);
impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        (self.0, Json(json!({"error":self.1}))).into_response()
    }
}
impl From<sqlx::Error> for ApiError {
    fn from(_: sqlx::Error) -> Self {
        Self(StatusCode::SERVICE_UNAVAILABLE, "Registry unavailable")
    }
}
#[derive(Serialize, Deserialize, FromRow, Debug, Clone)]
pub struct Release {
    pub id: Uuid,
    pub project_id: Uuid,
    pub version: String,
    pub digest: String,
    pub metadata: DbJson<BTreeMap<String, String>>,
    pub created_at: DateTime<Utc>,
}
#[derive(Serialize, Deserialize, FromRow, Debug)]
pub struct Channel {
    pub project_id: Uuid,
    pub name: String,
    pub release_id: Option<Uuid>,
    pub revision: i64,
    pub updated_at: DateTime<Utc>,
}
#[derive(Deserialize, Debug)]
#[serde(deny_unknown_fields)]
pub struct Register {
    pub version: String,
    pub digest: String,
    #[serde(default)]
    pub metadata: BTreeMap<String, String>,
}
pub fn validate(input: &mut Register) -> Result<(), ApiError> {
    if input.version.is_empty()
        || input.version.len() > 64
        || !input
            .version
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"._-".contains(&b))
    {
        return Err(ApiError(StatusCode::BAD_REQUEST, "Invalid version"));
    }
    let hex = input
        .digest
        .strip_prefix("sha256:")
        .ok_or(ApiError(StatusCode::BAD_REQUEST, "Invalid SHA256 digest"))?;
    if hex.len() != 64 || !hex.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err(ApiError(StatusCode::BAD_REQUEST, "Invalid SHA256 digest"));
    }
    input.digest = input.digest.to_ascii_lowercase();
    if input.metadata.len() > 10
        || input.metadata.iter().any(|(k, v)| {
            k.is_empty() || k.len() > 40 || v.len() > 256 || k.contains('\0') || v.contains('\0')
        })
        || serde_json::to_vec(&input.metadata)
            .map_err(|_| ApiError(StatusCode::BAD_REQUEST, "Invalid metadata"))?
            .len()
            > 2048
    {
        return Err(ApiError(StatusCode::BAD_REQUEST, "Metadata exceeds limits"));
    }
    Ok(())
}
async fn register(
    State(state): State<AppState>,
    Extension(project): Extension<Uuid>,
    Json(mut input): Json<Register>,
) -> Result<Response, ApiError> {
    validate(&mut input)?;
    let inserted = sqlx::query_as::<_, Release>(
        r#"
        INSERT INTO registry.releases (project_id, version, digest, metadata)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (project_id, version) DO NOTHING
        RETURNING id, project_id, version, digest, metadata, created_at
        "#,
    )
    .bind(project)
    .bind(&input.version)
    .bind(&input.digest)
    .bind(DbJson(&input.metadata))
    .fetch_optional(&state.pool)
    .await?;
    if let Some(release) = inserted {
        return Ok((StatusCode::CREATED, Json(release)).into_response());
    }
    let release = sqlx::query_as::<_, Release>(
        r#"
        SELECT id, project_id, version, digest, metadata, created_at
        FROM registry.releases
        WHERE project_id = $1 AND version = $2
        "#,
    )
    .bind(project)
    .bind(&input.version)
    .fetch_one(&state.pool)
    .await?;
    if release.digest != input.digest || release.metadata.0 != input.metadata {
        return Err(ApiError(
            StatusCode::CONFLICT,
            "Version already has different data",
        ));
    }
    Ok((StatusCode::OK, Json(release)).into_response())
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ListQuery {
    limit: Option<i64>,
    offset: Option<i64>,
}
async fn list(
    State(state): State<AppState>,
    Extension(project): Extension<Uuid>,
    Query(query): Query<ListQuery>,
) -> Result<Json<Vec<Release>>, ApiError> {
    let limit = query.limit.unwrap_or(20);
    let offset = query.offset.unwrap_or(0);
    if !(1..=100).contains(&limit) || !(0..=10000).contains(&offset) {
        return Err(ApiError(StatusCode::BAD_REQUEST, "Invalid pagination"));
    }
    Ok(Json(
        sqlx::query_as::<_, Release>(
            r#"
        SELECT id, project_id, version, digest, metadata, created_at
        FROM registry.releases
        WHERE project_id = $1
        ORDER BY created_at DESC, id DESC
        LIMIT $2 OFFSET $3
        "#,
        )
        .bind(project)
        .bind(limit)
        .bind(offset)
        .fetch_all(&state.pool)
        .await?,
    ))
}
async fn inspect(
    State(state): State<AppState>,
    Extension(project): Extension<Uuid>,
    Path(version): Path<String>,
) -> Result<Json<Release>, ApiError> {
    let release = sqlx::query_as::<_, Release>(
        r#"
        SELECT id, project_id, version, digest, metadata, created_at
        FROM registry.releases
        WHERE project_id = $1 AND version = $2
        "#,
    )
    .bind(project)
    .bind(version)
    .fetch_optional(&state.pool)
    .await?
    .ok_or(ApiError(StatusCode::NOT_FOUND, "Release not found"))?;
    Ok(Json(release))
}
fn channel_name(name: &str) -> Result<(), ApiError> {
    if !["staging", "production"].contains(&name) {
        return Err(ApiError(StatusCode::BAD_REQUEST, "Unknown channel"));
    };
    Ok(())
}
async fn channel(
    State(state): State<AppState>,
    Extension(project): Extension<Uuid>,
    Path(name): Path<String>,
) -> Result<Json<Channel>, ApiError> {
    channel_name(&name)?;
    Ok(Json(
        sqlx::query_as::<_, Channel>(
            r#"
        SELECT project_id, name, release_id, revision, updated_at
        FROM registry.channels
        WHERE project_id = $1 AND name = $2
        "#,
        )
        .bind(project)
        .bind(name)
        .fetch_one(&state.pool)
        .await?,
    ))
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Promotion {
    release_id: Uuid,
    expected_revision: i64,
}
async fn promote(
    State(state): State<AppState>,
    Extension(project): Extension<Uuid>,
    Path(name): Path<String>,
    Json(input): Json<Promotion>,
) -> Result<Json<Channel>, ApiError> {
    channel_name(&name)?;
    if input.expected_revision < 0 {
        return Err(ApiError(StatusCode::BAD_REQUEST, "Invalid revision"));
    }
    let owned: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM registry.releases WHERE project_id=$1 AND id=$2)",
    )
    .bind(project)
    .bind(input.release_id)
    .fetch_one(&state.pool)
    .await?;
    if !owned {
        return Err(ApiError(StatusCode::NOT_FOUND, "Release not found"));
    }
    let changed = sqlx::query_as::<_, Channel>(
        r#"
        UPDATE registry.channels
        SET release_id = $3, revision = revision + 1, updated_at = clock_timestamp()
        WHERE project_id = $1 AND name = $2 AND revision = $4
        RETURNING project_id, name, release_id, revision, updated_at
        "#,
    )
    .bind(project)
    .bind(name)
    .bind(input.release_id)
    .bind(input.expected_revision)
    .fetch_optional(&state.pool)
    .await?;
    Ok(Json(changed.ok_or(ApiError(
        StatusCode::CONFLICT,
        "Channel revision changed; read it again",
    ))?))
}
async fn health(State(state): State<AppState>) -> Result<Json<Value>, ApiError> {
    sqlx::query("SELECT 1").execute(&state.pool).await?;
    Ok(Json(json!({"status":"ok"})))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn canonical_and_bounded_registration() {
        let mut input = Register {
            version: "1.0.0".into(),
            digest: format!("sha256:{}", "A".repeat(64)),
            metadata: BTreeMap::new(),
        };
        validate(&mut input).unwrap();
        assert!(input.digest.ends_with(&"a".repeat(64)));
        input.version = "invalid version".into();
        assert!(validate(&mut input).is_err());
        input.version = "1.0.0".into();
        input.metadata.insert("notes".into(), "x".repeat(257));
        assert!(validate(&mut input).is_err());
        assert!(
            serde_json::from_str::<Register>(
                r#"{"version":"1","digest":"x","project_id":"attacker"}"#
            )
            .is_err()
        );
    }
    #[test]
    fn token_scope_config() {
        let token = "a".repeat(32);
        let config = json!({"00000000-0000-4000-8000-000000000001":token,"00000000-0000-4000-8000-000000000002":token});
        assert!(tokens(&config.to_string()).is_err());
        assert!(tokens("{}").is_err());
    }
}
