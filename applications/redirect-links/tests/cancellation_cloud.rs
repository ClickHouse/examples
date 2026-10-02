//! Destructive control on a freshly seeded dedicated Cloud fixture, before HTTP cases.
use redirect_links::{
    db::{self, Database},
    input::NewLink,
};
use std::{
    io::{BufRead, BufReader, Write},
    process::{Command, Stdio},
    time::Duration,
};

fn admin() -> Command {
    let mut command = Command::new("psql");
    command
        .args(["-X", "-qAt", "-v", "ON_ERROR_STOP=1"])
        .env("PGUSER", std::env::var("ADMIN_USER").unwrap())
        .env("PGPASSWORD", std::env::var("ADMIN_PASSWORD").unwrap())
        .env("PGSSLMODE", "verify-full");
    command
}

fn sql(text: &str) -> String {
    let result = admin().args(["-c", text]).output().unwrap();
    assert!(
        result.status.success(),
        "{}",
        String::from_utf8_lossy(&result.stderr)
    );
    String::from_utf8(result.stdout).unwrap()
}

#[actix_web::test]
#[ignore = "requires freshly seeded dedicated Cloud fixture and private admin control"]
async fn cancelled_database_waiter_retains_capacity_and_can_commit() {
    let database = Database::connect(db::connection_info("redirects_app").unwrap()).unwrap();
    let mut holder = admin()
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut input = holder.stdin.take().unwrap();
    input
        .write_all(b"BEGIN; SELECT id FROM redirect_links.accounts WHERE id='north' FOR UPDATE;\n")
        .unwrap();
    input.flush().unwrap();
    let mut output = BufReader::new(holder.stdout.take().unwrap());
    let mut line = String::new();
    output.read_line(&mut line).unwrap();
    assert_eq!(line.trim(), "north");

    let mut tasks = Vec::new();
    for index in 0..4 {
        let database = database.clone();
        tasks.push(actix_web::rt::spawn(async move {
            database
                .run(move |conn| {
                    db::create(
                        conn,
                        "north".into(),
                        NewLink {
                            slug: format!("cancel-{index}"),
                            destination: "https://example.invalid/cancel".into(),
                            expires_at: None,
                        },
                    )
                })
                .await
        }));
    }
    let mut observed = false;
    for _ in 0..60 {
        let count = sql(
            "SELECT pg_stat_clear_snapshot(); SELECT count(*) FROM pg_stat_activity WHERE application_name='redirect-links' AND cardinality(pg_blocking_pids(pid))>0",
        );
        if count.lines().last() == Some("4") {
            observed = true;
            break;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    assert!(
        observed,
        "four actual Diesel connections must be observed waiting on control lock"
    );
    let cancelled = tasks.remove(0);
    cancelled.abort();
    assert!(matches!(cancelled.await, Err(error) if error.is_cancelled()));
    assert!(
        database.run(|_| Ok(())).await.is_err(),
        "cancelled waiter must not free admission before SQL finishes"
    );

    input.write_all(b"COMMIT;\n").unwrap();
    input.flush().unwrap();
    drop(input);
    assert!(holder.wait().unwrap().success());
    for task in tasks {
        task.await.unwrap().unwrap();
    }
    for _ in 0..60 {
        if sql("SELECT count(*) FROM redirect_links.links WHERE slug LIKE 'cancel-%'").trim() == "4"
        {
            break;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    assert_eq!(
        sql("SELECT count(*) FROM redirect_links.links WHERE slug LIKE 'cancel-%'").trim(),
        "4"
    );
    assert!(database.run(|_| Ok(())).await.is_ok());
    println!(
        "Four actual blocked Diesel sessions; aborted waiter retains capacity; all four writes commit; later admission succeeds"
    );
    sql(
        "BEGIN; DELETE FROM redirect_links.links WHERE slug LIKE 'cancel-%'; UPDATE redirect_links.accounts SET link_count=0 WHERE id='north'; COMMIT;",
    );
}
