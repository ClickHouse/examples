pub mod db;
pub mod error;
pub mod gate;
pub mod input;
pub mod schema;

use actix_web::{
    HttpRequest, HttpResponse,
    http::{StatusCode, header},
    web,
};
use db::Database;
use error::ApiError;
use input::{CreateInput, DisableInput, Page};
use subtle::ConstantTimeEq;

pub struct State {
    pub database: Database,
    pub tokens: [(String, String); 2],
}

fn owner(request: &HttpRequest, state: &State) -> Result<String, ApiError> {
    let supplied = request
        .headers()
        .get(header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");
    for (account, token) in &state.tokens {
        let expected = format!("Bearer {token}");
        if bool::from(supplied.as_bytes().ct_eq(expected.as_bytes())) {
            return Ok(account.clone());
        }
    }
    Err(ApiError(StatusCode::UNAUTHORIZED, "unauthorized"))
}

async fn create(
    request: HttpRequest,
    state: web::Data<State>,
    body: web::Json<CreateInput>,
) -> Result<HttpResponse, ApiError> {
    if !request.query_string().is_empty() {
        return Err(ApiError::invalid("invalid_query"));
    }
    let owner = owner(&request, &state)?;
    let input = body.into_inner().validate()?;
    let saved = state
        .database
        .run(move |conn| db::create(conn, owner, input))
        .await?;
    Ok(HttpResponse::Created()
        .insert_header((header::CACHE_CONTROL, "no-store"))
        .json(saved))
}

async fn list(
    request: HttpRequest,
    state: web::Data<State>,
    page: web::Query<Page>,
) -> Result<HttpResponse, ApiError> {
    let owner = owner(&request, &state)?;
    let (limit, before) = page.into_inner().validate()?;
    let rows = state
        .database
        .run(move |conn| db::list(conn, owner, limit, before))
        .await?;
    let next = rows.last().map(|row| row.id.clone());
    Ok(HttpResponse::Ok()
        .insert_header((header::CACHE_CONTROL, "no-store"))
        .json(serde_json::json!({"rows":rows,"next_before":next})))
}

async fn disable(
    request: HttpRequest,
    state: web::Data<State>,
    path: web::Path<String>,
    body: web::Json<DisableInput>,
) -> Result<HttpResponse, ApiError> {
    if !request.query_string().is_empty() {
        return Err(ApiError::invalid("invalid_query"));
    }
    let owner = owner(&request, &state)?;
    let slug = input::slug(&path)?;
    let revision = input::positive(&body.revision)?;
    let saved = state
        .database
        .run(move |conn| db::disable(conn, owner, slug, revision))
        .await?;
    Ok(HttpResponse::Ok()
        .insert_header((header::CACHE_CONTROL, "no-store"))
        .json(saved))
}

async fn redirect(
    state: web::Data<State>,
    path: web::Path<String>,
) -> Result<HttpResponse, ApiError> {
    let slug = match input::slug(&path) {
        Ok(value) => value,
        Err(_) => {
            return Ok(HttpResponse::NotFound()
                .insert_header((header::CACHE_CONTROL, "no-store"))
                .finish());
        }
    };
    match state
        .database
        .run(move |conn| db::resolve(conn, slug))
        .await?
    {
        Some(location) => Ok(HttpResponse::TemporaryRedirect()
            .insert_header((header::LOCATION, location))
            .insert_header((header::CACHE_CONTROL, "no-store"))
            .finish()),
        None => Ok(HttpResponse::NotFound()
            .insert_header((header::CACHE_CONTROL, "no-store"))
            .finish()),
    }
}

pub fn routes(config: &mut web::ServiceConfig) {
    config
        .service(
            web::resource("/links")
                .route(web::get().to(list))
                .route(web::post().to(create)),
        )
        .service(web::resource("/links/{slug}/disable").route(web::post().to(disable)))
        .service(
            web::resource("/r/{slug}")
                .app_data(web::PathConfig::default().error_handler(|_, _| {
                    actix_web::error::InternalError::from_response(
                        "invalid_path",
                        HttpResponse::NotFound()
                            .insert_header((header::CACHE_CONTROL, "no-store"))
                            .finish(),
                    )
                    .into()
                }))
                .route(web::get().to(redirect))
                .route(web::head().to(redirect)),
        );
}

pub fn json_config() -> web::JsonConfig {
    web::JsonConfig::default()
        .limit(4096)
        .error_handler(|error, _| {
            let status = match error {
                actix_web::error::JsonPayloadError::OverflowKnownLength { .. }
                | actix_web::error::JsonPayloadError::Overflow { .. } => {
                    StatusCode::PAYLOAD_TOO_LARGE
                }
                _ => StatusCode::BAD_REQUEST,
            };
            ApiError(status, "invalid_json").into()
        })
}
