import json
from pathlib import Path
from uuid import UUID

import pytest

from app.config import ConfigurationError, Settings, parse_tokens
from app.database import build_engine

ALICE = "11111111-1111-4111-8111-111111111111"
BOB = "22222222-2222-4222-8222-222222222222"
TOKEN = "a" * 43


@pytest.fixture
def configured_env(monkeypatch, tmp_path):
    monkeypatch.chdir(tmp_path)
    cert = tmp_path / "ca.pem"
    cert.write_text("test certificate")
    values = {
        "PGHOST": "test.postgres.example.com",
        "PGPORT": "5432",
        "PGDATABASE": "workshop_booking",
        "PGUSER": "workshop_app",
        "PGPASSWORD": "a password containing @:/?&#%",
        "PGSSLROOTCERT": str(cert),
        "API_BEARER_TOKENS": json.dumps({ALICE: TOKEN}),
    }
    for name, value in values.items():
        monkeypatch.setenv(name, value)
    return values


def test_credentials_are_not_in_settings_repr(configured_env):
    settings = Settings.from_env()
    assert settings.bearer_tokens == {UUID(ALICE): TOKEN}
    assert configured_env["PGPASSWORD"] not in repr(settings)
    assert TOKEN not in repr(settings)


@pytest.mark.parametrize("port", ["0", "65536", "postgres", ""])
def test_port_is_bounded(configured_env, monkeypatch, port):
    monkeypatch.setenv("PGPORT", port)
    with pytest.raises(ConfigurationError, match="PGPORT"):
        Settings.from_env()


@pytest.mark.parametrize("host", ["/tmp", "one,two", "host user=admin", ""])
def test_host_is_a_single_dns_name(configured_env, monkeypatch, host):
    monkeypatch.setenv("PGHOST", host)
    with pytest.raises(ConfigurationError, match="PGHOST"):
        Settings.from_env()


def test_requires_a_ca_file(configured_env, monkeypatch):
    monkeypatch.setenv("PGSSLROOTCERT", "/does/not/exist.pem")
    with pytest.raises(ConfigurationError, match="PGSSLROOTCERT"):
        Settings.from_env()


def test_migrations_do_not_require_api_credentials(configured_env, monkeypatch):
    monkeypatch.delenv("API_BEARER_TOKENS")
    assert Settings.from_env(require_tokens=False).bearer_tokens == {}
    with pytest.raises(ConfigurationError, match="API_BEARER_TOKENS"):
        Settings.from_env()


@pytest.mark.parametrize(
    "raw",
    [
        "not-json",
        "[]",
        "{}",
        json.dumps({"invalid-uuid": TOKEN}),
        json.dumps({ALICE: "too-short"}),
        json.dumps({ALICE: TOKEN, BOB: TOKEN}),
        json.dumps({ALICE: " " * 43}),
        json.dumps({ALICE: "x" * 257}),
        json.dumps({ALICE: 1234}),
        '{"' + ALICE + '":"' + TOKEN + '","' + ALICE + '":"' + "b" * 43 + '"}',
        json.dumps({ALICE: TOKEN, ALICE.replace("-", ""): "b" * 43}),
    ],
)
def test_rejects_ambiguous_or_weak_token_configuration_without_echoing_it(raw):
    with pytest.raises(ConfigurationError) as error:
        parse_tokens(raw)
    assert raw not in str(error.value)
    assert TOKEN not in str(error.value)


def test_engine_forces_tls_and_read_committed(configured_env, monkeypatch):
    captured = {}

    def capture_engine(url, **options):
        captured.update(url=url, **options)
        return "engine"

    monkeypatch.setattr("app.database.create_engine", capture_engine)
    settings = Settings.from_env()
    assert build_engine(settings) == "engine"
    assert captured["url"].password == configured_env["PGPASSWORD"]
    assert captured["connect_args"]["sslmode"] == "verify-full"
    assert Path(captured["connect_args"]["sslrootcert"]).is_file()
    assert captured["isolation_level"] == "READ COMMITTED"
    assert captured["hide_parameters"] is True
    assert captured["pool_size"] + captured["max_overflow"] == 10
    assert "lock_timeout=3000" in captured["connect_args"]["options"]
