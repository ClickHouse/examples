//! A tour of the official `clickhouse` crate against ClickHouse Cloud.
//! See ../SPEC.md for the seven steps this program performs.

use std::error::Error;

use clickhouse::{Client, Row, sql::Identifier};
use serde::{Deserialize, Serialize};
use time::{Duration, OffsetDateTime, macros::datetime};
use uuid::Uuid;

const TABLE: &str = "readings_rust";
const MISSING_TABLE: &str = "no_such_table_rust";
const TOTAL_ROWS: i64 = 10_000;
const BATCHES: i64 = 10;
const BATCH_SIZE: i64 = TOTAL_ROWS / BATCHES;
const DEVICE: &str = "device-07";
const MIN_TEMP: f64 = 30.0;
const SITES: [&str; 5] = ["amsterdam", "berlin", "london", "madrid", "paris"];
const START: OffsetDateTime = datetime!(2026-01-01 0:00:00 UTC);

/// One row of `client_tour.readings_rust`. `Row` records the field names so the
/// client can validate them against the server's schema; the `serde(with = ...)`
/// helpers pick the RowBinary encoding for types serde has no native mapping for.
/// `Map(String, String)` is wire-compatible with `Array(Tuple(String, String))`,
/// so it deserializes into a `Vec` of pairs.
#[derive(Row, Serialize, Deserialize)]
struct Reading {
    #[serde(with = "clickhouse::serde::uuid")]
    reading_id: Uuid,
    #[serde(with = "clickhouse::serde::time::datetime64::millis")]
    recorded_at: OffsetDateTime,
    device_id: String,
    site: String,
    temp_c: f64,
    humidity_pct: Option<f64>,
    battery_pct: u8,
    tags: Vec<String>,
    attributes: Vec<(String, String)>,
}

#[derive(Row, Deserialize)]
struct SiteStats {
    site: String,
    readings: u64,
    avg_temp_c: f64,
    max_temp_c: f64,
}

/// Builds row `i` of the dataset. Integer arithmetic throughout, with a single
/// division per float, so every language in this directory emits identical bits.
fn reading(i: i64) -> Reading {
    Reading {
        // 00000000-0000-4000-8000-<i as 12 lowercase hex digits>
        reading_id: Uuid::from_u128((0x4000u128 << 64) | (0x8000u128 << 48) | i as u128),
        recorded_at: START + Duration::milliseconds(i * 1000 + (i * 37) % 1000),
        device_id: format!("device-{:02}", i % 50),
        site: SITES[(i % 50) as usize % 5].to_owned(),
        temp_c: 15.0 + ((i * 7919) % 1997) as f64 / 100.0,
        humidity_pct: match i % 10 {
            0 => None,
            _ => Some(30.0 + ((i * 104_729) % 6000) as f64 / 100.0),
        },
        battery_pct: (100 - (i % 101)) as u8,
        tags: match i % 3 {
            0 => vec!["calibrated".to_owned()],
            1 => vec!["calibrated".to_owned(), "outdoor".to_owned()],
            _ => vec![],
        },
        attributes: vec![
            ("firmware".to_owned(), format!("1.{}", i % 4)),
            (
                "model".to_owned(),
                if i % 2 == 0 { "tx-100" } else { "tx-200" }.to_owned(),
            ),
        ],
    }
}

fn env(name: &str) -> Result<String, String> {
    std::env::var(name).map_err(|_| format!("missing required environment variable {name}"))
}

/// The crate surfaces server exceptions as an opaque `BadResponse` string rather
/// than a structured code, so the `Code: NN` prefix has to be parsed out.
fn server_error_code(error: &clickhouse::error::Error) -> Option<u32> {
    let clickhouse::error::Error::BadResponse(message) = error else {
        return None;
    };
    let digits = message.strip_prefix("Code: ")?;
    digits
        .split(|c: char| !c.is_ascii_digit())
        .next()?
        .parse()
        .ok()
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    let client = Client::default()
        .with_url(format!(
            "https://{}:{}",
            env("CLICKHOUSE_HOST")?,
            env("CLICKHOUSE_HTTPS_PORT")?
        ))
        .with_user(env("CLICKHOUSE_USER")?)
        .with_password(env("CLICKHOUSE_PASSWORD")?)
        .with_database(env("CLICKHOUSE_DATABASE")?);

    // 1. Connect and ping.
    let version: String = client.query("SELECT version()").fetch_one().await?;
    println!("1 connect: ok, server version {version}");

    // 2. Create the table. `Identifier` interpolates a `?` as a quoted identifier
    // instead of a string literal.
    client
        .query("DROP TABLE IF EXISTS ?")
        .bind(Identifier(TABLE))
        .execute()
        .await?;
    client
        .query(
            "CREATE TABLE ?
             (
                 reading_id   UUID,
                 recorded_at  DateTime64(3, 'UTC'),
                 device_id    LowCardinality(String),
                 site         LowCardinality(String),
                 temp_c       Float64,
                 humidity_pct Nullable(Float64),
                 battery_pct  UInt8,
                 tags         Array(String),
                 attributes   Map(String, String)
             )
             ENGINE = MergeTree
             ORDER BY (site, device_id, recorded_at)",
        )
        .bind(Identifier(TABLE))
        .execute()
        .await?;
    println!("2 create table: ok");

    // 3. Insert 10,000 rows in 10 batches. Each `insert` is one streaming
    // INSERT request in RowBinaryWithNamesAndTypes; `end` flushes and awaits it.
    for batch in 0..BATCHES {
        let mut insert = client.insert::<Reading>(TABLE).await?;
        for i in batch * BATCH_SIZE..(batch + 1) * BATCH_SIZE {
            insert.write(&reading(i)).await?;
        }
        insert.end().await?;
    }
    println!("3 insert: {TOTAL_ROWS} rows in {BATCHES} batches");

    // 4. Parameterized query. `param` sends server-side query parameters
    // (`{name:Type}`); `bind` would substitute and escape client-side instead.
    let matches: u64 = client
        .query("SELECT count() FROM ? WHERE device_id = {device:String} AND temp_c > {min_temp:Float64}")
        .bind(Identifier(TABLE))
        .param("device", DEVICE)
        .param("min_temp", MIN_TEMP)
        .fetch_one()
        .await?;
    println!("4 parameterized query: {matches} readings for {DEVICE} above {MIN_TEMP:.1} C");

    // 5. Stream every row back through the cursor, decoding as rows arrive.
    let mut rows = 0u64;
    let mut battery_total = 0u64;
    let mut humidity_nulls = 0u64;
    let mut tag_total = 0u64;
    let mut cursor = client
        .query("SELECT * FROM ? ORDER BY recorded_at")
        .bind(Identifier(TABLE))
        .fetch::<Reading>()?;
    while let Some(row) = cursor.next().await? {
        rows += 1;
        battery_total += u64::from(row.battery_pct);
        humidity_nulls += u64::from(row.humidity_pct.is_none());
        tag_total += row.tags.len() as u64;
    }
    println!(
        "5 stream: {rows} rows, battery total {battery_total}, \
         humidity null in {humidity_nulls} rows, {tag_total} tags"
    );

    // 6. Aggregate into typed records.
    let stats = client
        .query(
            "SELECT site, count() AS readings,
                    round(avg(temp_c), 2) AS avg_temp_c,
                    round(max(temp_c), 2) AS max_temp_c
             FROM ?
             GROUP BY site ORDER BY site",
        )
        .bind(Identifier(TABLE))
        .fetch_all::<SiteStats>()
        .await?;
    println!("6 aggregate: site readings avg_temp_c max_temp_c");
    for s in stats {
        println!(
            "6 aggregate: {} {} {:.2} {:.2}",
            s.site, s.readings, s.avg_temp_c, s.max_temp_c
        );
    }

    // 7. Handle a server error.
    let error = client
        .query("SELECT count() FROM ?")
        .bind(Identifier(MISSING_TABLE))
        .fetch_one::<u64>()
        .await
        .expect_err("querying a missing table should fail");
    let code = server_error_code(&error).ok_or(error)?;
    println!("7 error: server error code {code}");

    Ok(())
}
