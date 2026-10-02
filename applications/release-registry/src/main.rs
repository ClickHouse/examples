use release_registry::{
    app,
    database::{BoxError, pool, required},
};
static MIGRATOR: sqlx::migrate::Migrator = sqlx::migrate!("./migrations");
#[tokio::main]
async fn main() {
    if run().await.is_err() {
        eprintln!("Registry command failed; check configuration, role, CA and database readiness");
        std::process::exit(1);
    }
}
async fn run() -> Result<(), BoxError> {
    let mode = std::env::args().nth(1).unwrap_or_else(|| "serve".into());
    let user = required("PGUSER")?;
    if !["serve", "migrate", "revert", "seed"].contains(&mode.as_str())
        || user
            != if mode == "serve" {
                "registry_app"
            } else {
                "registry_migrator"
            }
    {
        return Err("Use the command's restricted role".into());
    }
    let pool = pool(&user, &required("PGPASSWORD")?).await?;
    match mode.as_str() {
        "migrate" => MIGRATOR.run(&pool).await?,
        "revert" => MIGRATOR.undo(&pool, 0).await?,
        "seed" => {
            let mut tx = pool.begin().await?;
            sqlx::raw_sql(include_str!("../sql/seed.sql"))
                .execute(&mut *tx)
                .await?;
            tx.commit().await?;
        }
        _ => {
            let router = app(pool.clone(), &required("PROJECT_TOKENS")?).await?;
            let port: u16 = std::env::var("PORT")
                .unwrap_or_else(|_| "3000".into())
                .parse()?;
            if port == 0 {
                return Err("Invalid PORT".into());
            }
            let listener =
                tokio::net::TcpListener::bind((std::net::Ipv4Addr::LOCALHOST, port)).await?;
            println!("Release registry listening on http://127.0.0.1:{port}");
            axum::serve(listener, router)
                .with_graceful_shutdown(shutdown())
                .await?;
        }
    }
    pool.close().await;
    Ok(())
}
async fn shutdown() {
    let interrupt = async {
        let _ = tokio::signal::ctrl_c().await;
    };
    let terminate = async {
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
            .unwrap()
            .recv()
            .await;
    };
    tokio::select! {_=interrupt=>{},_=terminate=>{}}
}
