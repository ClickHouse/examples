"""Explicit libpq connection settings and server-owned attendee credentials."""

import json
import os
import re
from dataclasses import dataclass, field
from pathlib import Path
from uuid import UUID

from dotenv import load_dotenv


class ConfigurationError(ValueError):
    """A safe-to-display configuration error that never includes secret values."""


@dataclass(frozen=True)
class Settings:
    host: str
    port: int
    database: str
    user: str
    password: str = field(repr=False)
    sslrootcert: Path
    bearer_tokens: dict[UUID, str] = field(repr=False)

    @classmethod
    def from_env(cls, require_tokens: bool = True) -> "Settings":
        # Only the example's .env is loaded; existing environment values win.
        load_dotenv(Path.cwd() / ".env", override=False)

        def required(name: str) -> str:
            value = os.environ.get(name, "")
            if not value or "\x00" in value:
                raise ConfigurationError(f"Set {name} to a nonempty value.")
            return value

        host = required("PGHOST")
        if not re.fullmatch(r"[A-Za-z0-9.-]+", host):
            raise ConfigurationError("PGHOST must be a single DNS hostname.")
        try:
            port = int(os.environ.get("PGPORT", "5432"))
            if not 1 <= port <= 65535:
                raise ValueError
        except ValueError:
            raise ConfigurationError("PGPORT must be between 1 and 65535.") from None

        cert = Path(required("PGSSLROOTCERT")).expanduser().resolve()
        if not cert.is_file():
            raise ConfigurationError("PGSSLROOTCERT must point to the downloaded CA file.")

        tokens = parse_tokens(required("API_BEARER_TOKENS")) if require_tokens else {}
        return cls(
            host=host,
            port=port,
            database=required("PGDATABASE"),
            user=required("PGUSER"),
            password=required("PGPASSWORD"),
            sslrootcert=cert,
            bearer_tokens=tokens,
        )


def parse_tokens(raw: str) -> dict[UUID, str]:
    """Map stable, seeded attendee UUIDs to independently generated bearer tokens."""
    message = (
        "API_BEARER_TOKENS must be a JSON object of unique attendee UUIDs to unique "
        "32–256 character tokens using letters, digits, underscores or hyphens."
    )

    def unique_pairs(pairs: list[tuple[str, object]]) -> dict[str, object]:
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError
            result[key] = value
        return result

    try:
        parsed = json.loads(raw, object_pairs_hook=unique_pairs)
        if not isinstance(parsed, dict) or not 1 <= len(parsed) <= 100:
            raise ValueError
        tokens = {}
        for attendee, token in parsed.items():
            attendee_id = UUID(attendee)
            if attendee_id in tokens or not isinstance(token, str):
                raise ValueError
            if not re.fullmatch(r"[A-Za-z0-9_-]{32,256}", token):
                raise ValueError
            tokens[attendee_id] = token
        if len(set(tokens.values())) != len(tokens):
            raise ValueError
        return tokens
    except (ValueError, TypeError, AttributeError):
        raise ConfigurationError(message) from None
