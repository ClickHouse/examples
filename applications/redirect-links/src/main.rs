use actix_web::{App, HttpResponse, HttpServer, web};
use diesel::{Connection, PgConnection, connection::SimpleConnection};
use redirect_links::{
    State,
    db::{Database, connection_info},
    error::ApiError,
    json_config, routes,
};

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    if let Err(error) = run().await {
        eprintln!("Startup failed; check private configuration ({})", error.1);
        std::process::exit(1);
    }
    Ok(())
}

async fn run() -> Result<(), ApiError> {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    if arguments == ["migrate"] {
        let info = connection_info("redirects_migration")?;
        web::block(move || {
            let mut conn = PgConnection::establish(&info).map_err(|_| ApiError::unavailable())?;
            conn.batch_execute(include_str!("../sql/migrate.sql"))?;
            Ok::<_, ApiError>(())
        })
        .await
        .map_err(|_| ApiError::unavailable())??;
        println!("Explicit migration complete");
        return Ok(());
    }
    if arguments == ["--check-db"] {
        let info = connection_info("redirects_app")?;
        // Explicit diagnostic CLI mode for private certificate-control evidence.
        let result = web::block(move || PgConnection::establish(&info))
            .await
            .map_err(|_| ApiError::unavailable())?;
        match result {
            Ok(_) => println!("Verified Diesel connection"),
            Err(error) => {
                eprintln!("{error}");
                return Err(ApiError::unavailable());
            }
        }
        return Ok(());
    }
    let preflight = arguments == ["--preflight"];
    if !arguments.is_empty() && !preflight {
        return Err(ApiError::invalid("invalid_arguments"));
    }
    let state = if preflight {
        None
    } else {
        let info = connection_info("redirects_app")?;
        let database = web::block(move || Database::connect(info))
            .await
            .map_err(|_| ApiError::unavailable())??;
        let token = |name: &str| {
            let value = std::env::var(name).map_err(|_| ApiError::invalid("missing_token"))?;
            if !(32..=128).contains(&value.len())
                || !value.bytes().all(|c| (b'!'..=b'~').contains(&c))
            {
                return Err(ApiError::invalid("invalid_token"));
            }
            Ok(value)
        };
        let north = token("NORTH_TOKEN")?;
        let south = token("SOUTH_TOKEN")?;
        if north == south {
            return Err(ApiError::invalid("tokens_must_differ"));
        }
        Some(web::Data::new(State {
            database,
            tokens: [("north".into(), north), ("south".into(), south)],
        }))
    };
    let port = std::env::var("PORT")
        .unwrap_or_else(|_| "4000".into())
        .parse::<u16>()
        .map_err(|_| ApiError::invalid("invalid_port"))?;
    if port < 1024 {
        return Err(ApiError::invalid("invalid_port"));
    }
    HttpServer::new(move || {
        let app = App::new()
            .app_data(json_config())
            .app_data(
                web::QueryConfig::default()
                    .error_handler(|_, _| ApiError::invalid("invalid_query").into()),
            )
            .default_service(web::route().to(|| async {
                HttpResponse::NotFound()
                    .insert_header(("Cache-Control", "no-store"))
                    .finish()
            }))
            .route(
                "/health",
                web::get()
                    .to(|| async { HttpResponse::Ok().json(serde_json::json!({"status":"up"})) }),
            );
        if let Some(state) = &state {
            app.app_data(state.clone()).configure(routes)
        } else {
            app
        }
    })
    .workers(2)
    .worker_max_blocking_threads(4)
    .max_connections(32)
    .client_request_timeout(std::time::Duration::from_secs(5))
    .keep_alive(std::time::Duration::from_secs(5))
    .shutdown_timeout(10)
    .bind(("127.0.0.1", port))
    .map_err(|_| ApiError::unavailable())?
    .run()
    .await
    .map_err(|_| ApiError::unavailable())
}
