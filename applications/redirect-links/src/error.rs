use actix_web::{HttpResponse, ResponseError, http::StatusCode};
use diesel::result::{DatabaseErrorKind, Error};
use std::fmt;

#[derive(Debug)]
pub struct ApiError(pub StatusCode, pub &'static str);

impl ApiError {
    pub fn invalid(code: &'static str) -> Self {
        Self(StatusCode::BAD_REQUEST, code)
    }
    pub fn conflict(code: &'static str) -> Self {
        Self(StatusCode::CONFLICT, code)
    }
    pub fn unavailable() -> Self {
        Self(StatusCode::SERVICE_UNAVAILABLE, "unavailable")
    }
}

impl fmt::Display for ApiError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.1)
    }
}
impl std::error::Error for ApiError {}
impl ResponseError for ApiError {
    fn status_code(&self) -> StatusCode {
        self.0
    }
    fn error_response(&self) -> HttpResponse {
        HttpResponse::build(self.0)
            .insert_header(("Cache-Control", "no-store"))
            .json(serde_json::json!({"error": self.1}))
    }
}
impl From<Error> for ApiError {
    fn from(value: Error) -> Self {
        match value {
            Error::DatabaseError(DatabaseErrorKind::UniqueViolation, info)
                if info.constraint_name() == Some("links_slug_unique") =>
            {
                Self::conflict("slug_taken")
            }
            Error::NotFound => Self(StatusCode::NOT_FOUND, "not_found"),
            _ => Self::unavailable(),
        }
    }
}
