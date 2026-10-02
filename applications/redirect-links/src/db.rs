use crate::{
    error::ApiError,
    gate::BlockingGate,
    input::NewLink,
    schema::{accounts::dsl as a, links::dsl as l},
};
use chrono::{DateTime, SecondsFormat, Utc};
use diesel::{
    prelude::*,
    r2d2::{ConnectionManager, Pool},
    sql_types::{Bool, Nullable, Timestamptz},
};
use serde::Serialize;
use std::time::Duration;

pub type PgPool = Pool<ConnectionManager<PgConnection>>;

#[derive(Clone)]
pub struct Database {
    pool: PgPool,
    gate: BlockingGate,
}

pub fn connection_info(role: &str) -> Result<String, ApiError> {
    let required =
        |name: &str| std::env::var(name).map_err(|_| ApiError::invalid("missing_configuration"));
    if required("PGUSER")? != role {
        return Err(ApiError::invalid("wrong_database_role"));
    }
    let quote = |text: String| format!("'{}'", text.replace('\\', "\\\\").replace('\'', "\\'"));
    let mut result = String::new();
    for (key, env) in [
        ("host", "PGHOST"),
        ("port", "PGPORT"),
        ("dbname", "PGDATABASE"),
        ("user", "PGUSER"),
        ("password", "PGPASSWORD"),
        ("sslrootcert", "PGSSLROOTCERT"),
    ] {
        let value = required(env)?;
        if value.is_empty() {
            return Err(ApiError::invalid("missing_configuration"));
        }
        result += &format!("{key}={} ", quote(value));
    }
    result += "sslmode=verify-full connect_timeout=5 application_name=redirect-links options='-c statement_timeout=4000 -c lock_timeout=2000 -c idle_in_transaction_session_timeout=6000'";
    Ok(result)
}

impl Database {
    pub fn connect(info: String) -> Result<Self, ApiError> {
        let pool = Pool::builder()
            .max_size(4)
            .min_idle(Some(0))
            .connection_timeout(Duration::from_secs(2))
            .idle_timeout(Some(Duration::from_secs(60)))
            .max_lifetime(Some(Duration::from_secs(300)))
            .build(ConnectionManager::<PgConnection>::new(info))
            .map_err(|_| ApiError::unavailable())?;
        pool.get_timeout(Duration::from_secs(2))
            .map_err(|_| ApiError::unavailable())?;
        Ok(Self {
            pool,
            gate: BlockingGate::new(4),
        })
    }

    pub async fn run<F, T>(&self, operation: F) -> Result<T, ApiError>
    where
        F: FnOnce(&mut PgConnection) -> Result<T, ApiError> + Send + 'static,
        T: Send + 'static,
    {
        let pool = self.pool.clone();
        self.gate
            .run(move || {
                let mut connection = pool
                    .get_timeout(Duration::from_secs(2))
                    .map_err(|_| ApiError::unavailable())?;
                operation(&mut connection)
            })
            .await
    }
}

#[derive(Queryable, Selectable)]
#[diesel(table_name = crate::schema::links)]
#[diesel(check_for_backend(diesel::pg::Pg))]
pub struct Link {
    pub id: i64,
    pub account: String,
    pub slug: String,
    pub destination: String,
    pub expires_at: Option<DateTime<Utc>>,
    pub disabled_at: Option<DateTime<Utc>>,
    pub revision: i64,
    pub created_at: DateTime<Utc>,
}

#[derive(Serialize)]
pub struct LinkView {
    pub id: String,
    pub slug: String,
    pub destination: String,
    pub expires_at: Option<String>,
    pub disabled_at: Option<String>,
    pub revision: String,
    pub created_at: String,
}
impl From<Link> for LinkView {
    fn from(row: Link) -> Self {
        let date = |value: DateTime<Utc>| value.to_rfc3339_opts(SecondsFormat::Micros, true);
        Self {
            id: row.id.to_string(),
            slug: row.slug,
            destination: row.destination,
            expires_at: row.expires_at.map(date),
            disabled_at: row.disabled_at.map(date),
            revision: row.revision.to_string(),
            created_at: date(row.created_at),
        }
    }
}

pub fn create(
    conn: &mut PgConnection,
    owner: String,
    input: NewLink,
) -> Result<LinkView, ApiError> {
    conn.transaction(|conn| {
        let count = a::accounts
            .filter(a::id.eq(&owner))
            .select(a::link_count)
            .for_update()
            .first::<i32>(conn)?;
        if count >= 20 {
            return Err(ApiError::conflict("account_full"));
        }
        diesel::update(a::accounts.filter(a::id.eq(&owner)))
            .set(a::link_count.eq(count + 1))
            .execute(conn)?;
        let saved = diesel::insert_into(l::links)
            .values((
                l::account.eq(owner),
                l::slug.eq(input.slug),
                l::destination.eq(input.destination),
                l::expires_at.eq(input.expires_at),
            ))
            .returning(Link::as_returning())
            .get_result::<Link>(conn)?;
        Ok(saved.into())
    })
}

pub fn disable(
    conn: &mut PgConnection,
    owner: String,
    slug: String,
    expected: i64,
) -> Result<LinkView, ApiError> {
    conn.transaction(|conn| {
        let saved = l::links
            .filter(l::account.eq(&owner))
            .filter(l::slug.eq(&slug))
            .select(Link::as_select())
            .for_update()
            .first::<Link>(conn)?;
        if saved.disabled_at.is_some() {
            if expected == saved.revision || expected == saved.revision - 1 {
                return Ok(saved.into());
            }
            return Err(ApiError::conflict("revision_conflict"));
        }
        if saved.revision != expected {
            return Err(ApiError::conflict("revision_conflict"));
        }
        let changed = diesel::update(
            l::links
                .filter(l::account.eq(owner))
                .filter(l::slug.eq(slug)),
        )
        .set((
            l::disabled_at.eq(diesel::dsl::sql::<Nullable<Timestamptz>>(
                "clock_timestamp()",
            )),
            l::revision.eq(saved.revision + 1),
        ))
        .returning(Link::as_returning())
        .get_result::<Link>(conn)?;
        Ok(changed.into())
    })
}

pub fn list(
    conn: &mut PgConnection,
    owner: String,
    limit: i64,
    before: Option<i64>,
) -> Result<Vec<LinkView>, ApiError> {
    let mut query = l::links.filter(l::account.eq(owner)).into_boxed();
    if let Some(before) = before {
        query = query.filter(l::id.lt(before));
    }
    Ok(query
        .order(l::id.desc())
        .limit(limit)
        .select(Link::as_select())
        .load::<Link>(conn)?
        .into_iter()
        .map(Into::into)
        .collect())
}

pub fn resolve(conn: &mut PgConnection, slug: String) -> Result<Option<String>, ApiError> {
    Ok(l::links
        .filter(l::slug.eq(slug))
        .filter(l::disabled_at.is_null())
        .filter(diesel::dsl::sql::<Bool>(
            "(expires_at IS NULL OR expires_at > clock_timestamp())",
        ))
        .select(l::destination)
        .first::<String>(conn)
        .optional()?)
}
