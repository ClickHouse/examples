use sqlx::{
    ConnectOptions, PgPool,
    postgres::{PgConnectOptions, PgPoolOptions, PgSslMode},
};
use std::{env, error::Error, path::PathBuf, time::Duration};
pub type BoxError = Box<dyn Error + Send + Sync>;
pub fn required(key: &str) -> Result<String, BoxError> {
    env::var(key).map_err(|_| format!("Missing {key}").into())
}
pub fn options(user: &str, password: &str) -> Result<PgConnectOptions, BoxError> {
    let port: u16 = env::var("PGPORT")
        .unwrap_or_else(|_| "5432".into())
        .parse()?;
    if port == 0 {
        return Err("Invalid PGPORT".into());
    }
    let mut options = PgConnectOptions::new_without_pgpass()
        .host(&required("PGHOST")?)
        .port(port)
        .database(&required("PGDATABASE")?)
        .username(user)
        .password(password)
        .ssl_mode(PgSslMode::VerifyFull)
        .ssl_root_cert(PathBuf::from(required("PGSSLROOTCERT")?))
        .application_name("release-registry")
        .options([("search_path", "registry"), ("statement_timeout", "5000")])
        .disable_statement_logging();
    if user == "registry_migrator" {
        options = options.options([("role", "registry_owner")]);
    }
    Ok(options)
}
pub async fn pool(user: &str, password: &str) -> Result<PgPool, BoxError> {
    Ok(PgPoolOptions::new()
        .max_connections(5)
        .acquire_timeout(Duration::from_secs(10))
        .connect_with(options(user, password)?)
        .await?)
}
