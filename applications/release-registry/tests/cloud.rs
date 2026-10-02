use release_registry::{
    Release, app,
    database::{options, pool, required},
};
use serde_json::{Value, json};
use sqlx::{PgPool, postgres::PgPoolOptions};
use std::collections::BTreeMap;
use uuid::Uuid;
const A: &str = "00000000-0000-4000-8000-000000000001";
const B: &str = "00000000-0000-4000-8000-000000000002";

struct Fixture {
    runtime: PgPool,
    owner: PgPool,
    url: String,
    client: reqwest::Client,
    token_a: String,
    token_b: String,
    server: tokio::task::JoinHandle<()>,
}
impl Fixture {
    async fn new() -> Self {
        let runtime = pool(
            &required("PGUSER").unwrap(),
            &required("PGPASSWORD").unwrap(),
        )
        .await
        .unwrap();
        let owner = pool(
            "registry_migrator",
            &required("TEST_MIGRATOR_PASSWORD").unwrap(),
        )
        .await
        .unwrap();
        sqlx::raw_sql("TRUNCATE registry.releases CASCADE;")
            .execute(&owner)
            .await
            .unwrap();
        sqlx::raw_sql(include_str!("../sql/seed.sql"))
            .execute(&owner)
            .await
            .unwrap();
        let raw = required("PROJECT_TOKENS").unwrap();
        let tokens: BTreeMap<String, String> = serde_json::from_str(&raw).unwrap();
        let router = app(runtime.clone(), &raw).await.unwrap();
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        let server = tokio::spawn(async move {
            axum::serve(listener, router).await.unwrap();
        });
        Self {
            runtime,
            owner,
            url,
            client: reqwest::Client::new(),
            token_a: tokens[A].clone(),
            token_b: tokens[B].clone(),
            server,
        }
    }
    async fn request(
        &self,
        method: &str,
        path: &str,
        token: &str,
        body: Option<Value>,
    ) -> (u16, Value) {
        let mut request = self
            .client
            .request(method.parse().unwrap(), format!("{}{}", self.url, path))
            .bearer_auth(token);
        if let Some(body) = body {
            request = request.json(&body);
        }
        let response = request.send().await.unwrap();
        let status = response.status().as_u16();
        let text = response.text().await.unwrap();
        (
            status,
            serde_json::from_str(&text).unwrap_or(Value::String(text)),
        )
    }
    async fn register(&self, token: &str, version: &str) -> Value {
        let (status, body) = self
            .request("POST", "/releases", token, Some(payload(version)))
            .await;
        assert_eq!(status, 201);
        body
    }
    async fn close(self) {
        self.server.abort();
        self.runtime.close().await;
        self.owner.close().await;
    }
}
fn payload(version: &str) -> Value {
    json!({"version":version,"digest":format!("sha256:{}","a".repeat(64)),"metadata":{"commit":"abc123","built_by":"ci"}})
}

#[tokio::test]
#[ignore = "dedicated Cloud service; destructive fixtures; run --ignored --test-threads=1"]
async fn duplicate_registration_race_and_canonical_conflicts() {
    let f = Fixture::new().await;
    let mut tasks = Vec::new();
    for _ in 0..12 {
        let client = f.client.clone();
        let url = f.url.clone();
        let token = f.token_a.clone();
        tasks.push(tokio::spawn(async move {
            client
                .post(format!("{url}/releases"))
                .bearer_auth(token)
                .json(&payload("1.0.0"))
                .send()
                .await
                .unwrap()
                .status()
                .as_u16()
        }));
    }
    let mut created = 0;
    for task in tasks {
        match task.await.unwrap() {
            201 => created += 1,
            200 => {}
            _ => panic!("duplicate not accepted"),
        }
    }
    assert_eq!(created, 1);
    let count: i64 = sqlx::query_scalar("SELECT count(*) FROM registry.releases")
        .fetch_one(&f.owner)
        .await
        .unwrap();
    assert_eq!(count, 1);
    let mut equivalent = payload("1.0.0");
    equivalent["digest"] = json!(format!("sha256:{}", "A".repeat(64)));
    assert_eq!(
        f.request("POST", "/releases", &f.token_a, Some(equivalent))
            .await
            .0,
        200
    );
    let mut mismatch = payload("1.0.0");
    mismatch["metadata"]["commit"] = json!("different");
    assert_eq!(
        f.request("POST", "/releases", &f.token_a, Some(mismatch))
            .await
            .0,
        409
    );
    let mut mismatch = payload("1.0.0");
    mismatch["digest"] = json!(format!("sha256:{}", "b".repeat(64)));
    assert_eq!(
        f.request("POST", "/releases", &f.token_a, Some(mismatch))
            .await
            .0,
        409
    );
    f.close().await;
}
#[tokio::test]
#[ignore = "dedicated Cloud service; destructive fixtures"]
async fn promotion_compare_and_swap_race_and_stale_replay() {
    let f = Fixture::new().await;
    let first = f.register(&f.token_a, "1.0.0").await;
    let second = f.register(&f.token_a, "2.0.0").await;
    let mut tasks = Vec::new();
    for id in [first["id"].clone(), second["id"].clone()] {
        let client = f.client.clone();
        let url = f.url.clone();
        let token = f.token_a.clone();
        tasks.push(tokio::spawn(async move {
            client
                .put(format!("{url}/channels/production"))
                .bearer_auth(token)
                .json(&json!({"release_id":id,"expected_revision":0}))
                .send()
                .await
                .unwrap()
                .status()
                .as_u16()
        }));
    }
    let mut statuses = Vec::new();
    for task in tasks {
        statuses.push(task.await.unwrap());
    }
    statuses.sort();
    assert_eq!(statuses, [200, 409]);
    let (_, channel) = f
        .request("GET", "/channels/production", &f.token_a, None)
        .await;
    assert_eq!(channel["revision"], 1);
    assert_eq!(
        f.request(
            "PUT",
            "/channels/production",
            &f.token_a,
            Some(json!({"release_id":first["id"],"expected_revision":0}))
        )
        .await
        .0,
        409
    );
    assert_eq!(
        f.request(
            "PUT",
            "/channels/production",
            &f.token_a,
            Some(json!({"release_id":first["id"],"expected_revision":1}))
        )
        .await
        .0,
        200
    );
    let (_, channel) = f
        .request("GET", "/channels/production", &f.token_a, None)
        .await;
    assert_eq!(channel["revision"], 2);
    assert_eq!(channel["release_id"], first["id"]);
    f.close().await;
}
#[tokio::test]
#[ignore = "dedicated Cloud service; destructive fixtures"]
async fn project_reads_and_composite_foreign_key() {
    let f = Fixture::new().await;
    let foreign = f.register(&f.token_b, "foreign-only").await;
    f.register(&f.token_a, "same-version").await;
    f.register(&f.token_b, "same-version").await;
    assert_eq!(
        f.request("GET", "/releases/foreign-only", &f.token_a, None)
            .await
            .0,
        404
    );
    let (_, list) = f.request("GET", "/releases", &f.token_a, None).await;
    assert_eq!(list.as_array().unwrap().len(), 1);
    assert_eq!(
        f.request(
            "PUT",
            "/channels/staging",
            &f.token_a,
            Some(json!({"release_id":foreign["id"],"expected_revision":0}))
        )
        .await
        .0,
        404
    );
    let foreign_id: Uuid = foreign["id"].as_str().unwrap().parse().unwrap();
    let project: Uuid = A.parse().unwrap();
    let error = sqlx::query(
        "UPDATE registry.channels SET release_id=$1 WHERE project_id=$2 AND name='staging'",
    )
    .bind(foreign_id)
    .bind(project)
    .execute(&f.runtime)
    .await
    .unwrap_err();
    assert_eq!(
        error.as_database_error().unwrap().code().as_deref(),
        Some("23503")
    );
    f.close().await;
}
#[tokio::test]
#[ignore = "dedicated Cloud service; destructive fixtures"]
async fn invalid_requests_and_immutable_runtime_privileges() {
    let f = Fixture::new().await;
    f.register(&f.token_a, "1.0.0").await;
    assert_eq!(f.request("GET", "/releases", "wrong", None).await.0, 401);
    for input in [
        json!({"version":"a","digest":"invalid"}),
        json!({"version":"spaces invalid","digest":format!("sha256:{}","a".repeat(64))}),
        json!({"version":"valid","digest":format!("sha256:{}","a".repeat(64)),"metadata":{"oversized":"x".repeat(257)}}),
        json!({"version":"nul-value","digest":format!("sha256:{}","a".repeat(64)),"metadata":{"bad":"\u{0000}"}}),
        json!({"version":"nul-key","digest":format!("sha256:{}","a".repeat(64)),"metadata":{"\u{0000}":"bad"}}),
    ] {
        assert_eq!(
            f.request("POST", "/releases", &f.token_a, Some(input))
                .await
                .0,
            400
        );
    }
    assert_eq!(
        f.request(
            "POST",
            "/releases",
            &f.token_a,
            Some(json!({"version":"v","digest":"x","project_id":B}))
        )
        .await
        .0,
        422
    );
    assert_eq!(
        f.request(
            "POST",
            "/releases",
            &f.token_a,
            Some(json!({"padding":"x".repeat(9000)}))
        )
        .await
        .0,
        413
    );
    assert_eq!(
        f.request("GET", "/releases?limit=101", &f.token_a, None)
            .await
            .0,
        400
    );
    for sql in [
        "UPDATE registry.releases SET digest='x'",
        "DELETE FROM registry.releases",
        "CREATE TABLE registry.denied (id INTEGER)",
        "SELECT * FROM registry._sqlx_migrations",
    ] {
        let error = sqlx::query(sql).execute(&f.runtime).await.unwrap_err();
        assert_eq!(
            error.as_database_error().unwrap().code().as_deref(),
            Some("42501")
        );
    }
    f.close().await;
}
#[tokio::test]
#[ignore = "dedicated Cloud service; destructive fixtures"]
async fn rollback_discards_registration_and_promotion() {
    let f = Fixture::new().await;
    let original = f.register(&f.token_a, "1.0.0").await;
    let project: Uuid = A.parse().unwrap();
    let mut tx = f.runtime.begin().await.unwrap();
    let inserted: Release = sqlx::query_as(
        r#"
        INSERT INTO registry.releases (project_id, version, digest, metadata)
        VALUES ($1, 'rollback', $2, '{}'::jsonb)
        RETURNING id, project_id, version, digest, metadata, created_at
        "#,
    )
    .bind(project)
    .bind(format!("sha256:{}", "b".repeat(64)))
    .fetch_one(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        r#"
        UPDATE registry.channels
        SET release_id = $1, revision = revision + 1
        WHERE project_id = $2 AND name = 'staging' AND revision = 0
        "#,
    )
    .bind(inserted.id)
    .bind(project)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.rollback().await.unwrap();
    assert_eq!(
        f.request("GET", "/releases/rollback", &f.token_a, None)
            .await
            .0,
        404
    );
    let (_, channel) = f
        .request("GET", "/channels/staging", &f.token_a, None)
        .await;
    assert_eq!(channel["revision"], 0);
    assert!(channel["release_id"].is_null());
    assert!(!original["id"].is_null());
    f.close().await;
}
#[tokio::test]
#[ignore = "real Cloud TLS and private certificate fixture"]
async fn tls_rejects_wrong_ca_and_hostname() {
    let user = required("PGUSER").unwrap();
    let password = required("PGPASSWORD").unwrap();
    let address = tokio::net::lookup_host((required("PGHOST").unwrap().as_str(), 5432))
        .await
        .unwrap()
        .next()
        .unwrap()
        .ip();
    for cfg in [
        options(&user, &password)
            .unwrap()
            .ssl_root_cert(std::path::PathBuf::from(required("TEST_WRONG_CA").unwrap())),
        options(&user, &password)
            .unwrap()
            .host(&address.to_string()),
    ] {
        let result = PgPoolOptions::new()
            .max_connections(1)
            .acquire_timeout(std::time::Duration::from_secs(10))
            .connect_with(cfg)
            .await;
        let error = result.unwrap_err();
        let message = error.to_string().to_lowercase();
        assert!(
            message.contains("certificate") || message.contains("cert"),
            "expected certificate rejection"
        );
    }
}
