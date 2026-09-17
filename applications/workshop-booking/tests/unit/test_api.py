from pathlib import Path
from typing import Annotated
from uuid import UUID

import pytest
from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient
from pydantic import ValidationError
from sqlalchemy.exc import OperationalError

from app.auth import get_attendee_id
from app.config import Settings
from app.database import get_session
from app.main import create_app
from app.schemas import BookingCreate

ALICE = UUID("11111111-1111-4111-8111-111111111111")
TOKEN = "a" * 43
WORKSHOP = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
BOOKING = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"


@pytest.fixture
def settings():
    return Settings("example.com", 5432, "db", "user", "secret", Path("ca.pem"), {ALICE: TOKEN})


@pytest.fixture
def auth_client(settings):
    app = FastAPI()
    app.state.settings = settings

    @app.get("/identity")
    def identity(attendee_id: Annotated[UUID, Depends(get_attendee_id)]):
        return {"id": str(attendee_id)}

    return TestClient(app)


@pytest.mark.parametrize(
    "headers",
    [{}, {"Authorization": "Basic abc"}, {"Authorization": "Bearer wrong"}],
)
def test_auth_rejects_missing_or_wrong_bearer(auth_client, headers):
    response = auth_client.get("/identity", headers=headers)
    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


def test_auth_resolves_the_server_owned_identity(auth_client):
    response = auth_client.get("/identity", headers={"Authorization": f"Bearer {TOKEN}"})
    assert response.status_code == 200
    assert response.json() == {"id": str(ALICE)}


@pytest.mark.parametrize(
    "body",
    [
        {"id": BOOKING, "workshop_id": WORKSHOP, "attendee_id": str(ALICE)},
        {"id": BOOKING, "workshop_id": WORKSHOP, "seats": 2},
        {"id": BOOKING, "workshop_id": WORKSHOP, "status": "confirmed"},
        {"id": "invalid", "workshop_id": WORKSHOP},
        {"id": BOOKING, "workshop_id": 123},
        {"workshop_id": WORKSHOP},
    ],
)
def test_booking_payload_rejects_untrusted_owner_or_invalid_values(body):
    with pytest.raises(ValidationError):
        BookingCreate.model_validate(body)


def test_booking_payload_accepts_client_uuid():
    body = BookingCreate.model_validate({"id": BOOKING, "workshop_id": WORKSHOP})
    assert body.id == UUID(BOOKING)


@pytest.fixture
def api_client(settings):
    app = create_app()
    app.state.settings = settings

    class UnavailableSession:
        def begin(self):
            raise OperationalError("SELECT private-data", {}, Exception("password-secret"))

    app.dependency_overrides[get_session] = lambda: UnavailableSession()
    return TestClient(app)


@pytest.mark.parametrize("query", ["limit=0", "limit=101", "offset=-1", "offset=10001"])
def test_list_pagination_is_bounded(api_client, query):
    assert api_client.get(f"/workshops?{query}").status_code == 422


def test_database_error_is_redacted_and_retryable(api_client, caplog):
    response = api_client.get("/workshops")
    assert response.status_code == 503
    assert response.headers["retry-after"] == "1"
    assert "private-data" not in response.text + caplog.text
    assert "password-secret" not in response.text + caplog.text


def test_validation_does_not_echo_submitted_values(api_client):
    response = api_client.post(
        "/bookings",
        headers={"Authorization": f"Bearer {TOKEN}"},
        json={"id": "secret-input", "workshop_id": WORKSHOP},
    )
    assert response.status_code == 422
    assert "secret-input" not in response.text


def test_openapi_exposes_bearer_auth_only_on_booking_routes(api_client):
    schema = api_client.get("/openapi.json").json()
    assert "security" not in schema["paths"]["/workshops"]["get"]
    assert schema["paths"]["/bookings"]["post"]["security"] == [{"HTTPBearer": []}]
    assert set(schema["paths"]) == {"/workshops", "/bookings", "/bookings/{booking_id}"}
