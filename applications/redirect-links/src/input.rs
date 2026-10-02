use crate::error::ApiError;
use chrono::{DateTime, Datelike, Utc};
use serde::Deserialize;
use url::Url;

pub fn slug(value: &str) -> Result<String, ApiError> {
    if !(3..=40).contains(&value.len())
        || !value.is_ascii()
        || !value
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || c == b'-')
        || !value.as_bytes()[0].is_ascii_alphanumeric()
        || !value.as_bytes()[value.len() - 1].is_ascii_alphanumeric()
    {
        return Err(ApiError::invalid("invalid_slug"));
    }
    let canonical = value.to_ascii_lowercase();
    if ["health", "links", "admin", "api", "static"].contains(&canonical.as_str()) {
        return Err(ApiError::invalid("reserved_slug"));
    }
    Ok(canonical)
}

pub fn destination(value: &str) -> Result<String, ApiError> {
    if value.len() > 2048 || value != value.trim() || value.chars().any(char::is_control) {
        return Err(ApiError::invalid("invalid_destination"));
    }
    let authority = value
        .split_once("://")
        .map(|(_, rest)| rest.split(['/', '?', '#']).next().unwrap_or(""));
    if authority.is_none_or(|value| value.is_empty() || value.contains('@')) {
        return Err(ApiError::invalid("invalid_destination"));
    }
    let parsed = Url::parse(value).map_err(|_| ApiError::invalid("invalid_destination"))?;
    if !["http", "https"].contains(&parsed.scheme())
        || parsed.host().is_none()
        || !parsed.username().is_empty()
        || parsed.password().is_some()
        || parsed.as_str().len() > 2048
    {
        return Err(ApiError::invalid("invalid_destination"));
    }
    Ok(parsed.to_string())
}

pub fn positive(value: &str) -> Result<i64, ApiError> {
    if value.is_empty()
        || value.len() > 19
        || value.starts_with('0')
        || !value.bytes().all(|c| c.is_ascii_digit())
    {
        return Err(ApiError::invalid("invalid_number"));
    }
    value
        .parse()
        .map_err(|_| ApiError::invalid("invalid_number"))
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CreateInput {
    pub slug: String,
    pub destination: String,
    pub expires_at: Option<String>,
}

pub struct NewLink {
    pub slug: String,
    pub destination: String,
    pub expires_at: Option<DateTime<Utc>>,
}

impl CreateInput {
    pub fn validate(self) -> Result<NewLink, ApiError> {
        let expiry = self
            .expires_at
            .map(|text| {
                if text.len() > 35 {
                    return Err(ApiError::invalid("invalid_expiry"));
                }
                let date = DateTime::parse_from_rfc3339(&text)
                    .map_err(|_| ApiError::invalid("invalid_expiry"))?
                    .with_timezone(&Utc);
                if !(1970..=2100).contains(&date.year())
                    || date.timestamp_subsec_nanos() >= 1_000_000_000
                    || date.timestamp_subsec_nanos() % 1000 != 0
                {
                    return Err(ApiError::invalid("invalid_expiry"));
                }
                Ok(date)
            })
            .transpose()?;
        Ok(NewLink {
            slug: slug(&self.slug)?,
            destination: destination(&self.destination)?,
            expires_at: expiry,
        })
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DisableInput {
    pub revision: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Page {
    pub limit: Option<String>,
    pub before: Option<String>,
}

impl Page {
    pub fn validate(self) -> Result<(i64, Option<i64>), ApiError> {
        let limit = self
            .limit
            .as_deref()
            .map(positive)
            .transpose()?
            .unwrap_or(10);
        if limit > 20 {
            return Err(ApiError::invalid("invalid_limit"));
        }
        let before = self.before.as_deref().map(positive).transpose()?;
        Ok((limit, before))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn canonical_slug_and_url() {
        assert_eq!(slug("My-Link").unwrap(), "my-link");
        for value in ["ab", "-abc", "abc-", "abc/def", "a\0b", "ＡＢＣ", "health"] {
            assert!(slug(value).is_err());
        }
        assert_eq!(
            destination("HTTPS://EXAMPLE.COM:443/a").unwrap(),
            "https://example.com/a"
        );
        for value in [
            "file:///tmp/a",
            "https://user@example.com/",
            "https://@example.com/",
            "https:example.com",
            "https://example.com/\n",
            "https://example.com/\u{0085}",
            " https://example.com",
        ] {
            assert!(destination(value).is_err());
        }
    }

    #[test]
    fn numeric_and_expiry_bounds() {
        assert_eq!(positive("9223372036854775807").unwrap(), i64::MAX);
        for value in ["0", "01", "-1", "9223372036854775808"] {
            assert!(positive(value).is_err());
        }
        assert!(positive(&"9".repeat(1000)).is_err());
        let good: CreateInput = serde_json::from_str(r#"{"slug":"abc","destination":"https://example.com","expires_at":"2026-10-02T12:00:00+02:00"}"#).unwrap();
        assert_eq!(
            good.validate().unwrap().expires_at.unwrap().to_rfc3339(),
            "2026-10-02T10:00:00+00:00"
        );
        assert!(
            serde_json::from_str::<CreateInput>(
                r#"{"slug":"abc","destination":"https://example.com","owner":"south"}"#
            )
            .is_err()
        );
        assert!(
            serde_json::from_str::<CreateInput>(
                r#"{"slug":"\ud800","destination":"https://example.com"}"#
            )
            .is_err()
        );
        for date in [
            "2025-02-29T00:00:00Z",
            "2026-10-02T00:00:00.0000001Z",
            "2016-12-31T23:59:60Z",
        ] {
            let value = CreateInput {
                slug: "abc".into(),
                destination: "https://example.com".into(),
                expires_at: Some(date.into()),
            };
            assert!(value.validate().is_err());
        }
    }
}
