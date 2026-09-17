"""Exercise real HTTP request handling and committed concurrent transactions."""

from concurrent.futures import ThreadPoolExecutor
from threading import Barrier, Event
from uuid import uuid4

import pytest
from sqlalchemy import event, text
from sqlalchemy.exc import SQLAlchemyError

import app.main


def book(client, database, workshop_id, *, attendee=0, booking_id=None):
    return client.post(
        "/bookings",
        headers=database.headers(attendee),
        json={"id": str(booking_id or uuid4()), "workshop_id": str(workshop_id)},
    )


def test_booking_replay_cancellation_and_new_booking(client, live_db, workshop):
    workshop_id, booking_id = workshop(1), uuid4()
    first = book(client, live_db, workshop_id, booking_id=booking_id)
    assert first.status_code == 201
    assert first.json()["status"] == "confirmed"
    replay = book(client, live_db, workshop_id, booking_id=booking_id)
    assert replay.status_code == 200
    assert replay.json() == first.json()
    assert live_db.active_count(workshop_id) == 1
    assert book(client, live_db, workshop_id).status_code == 409

    receipt = client.get(f"/bookings/{booking_id}", headers=live_db.headers())
    assert receipt.status_code == 200
    assert receipt.json() == first.json()
    cancelled = client.delete(f"/bookings/{booking_id}", headers=live_db.headers())
    assert cancelled.status_code == 200
    assert cancelled.json()["status"] == "cancelled"
    assert (
        client.delete(f"/bookings/{booking_id}", headers=live_db.headers()).json()
        == cancelled.json()
    )
    assert live_db.active_count(workshop_id) == 0

    # Replaying a cancelled UUID must never resurrect the booking.
    old_replay = book(client, live_db, workshop_id, booking_id=booking_id)
    assert old_replay.status_code == 200
    assert old_replay.json() == cancelled.json()
    assert live_db.active_count(workshop_id) == 0
    assert book(client, live_db, workshop_id).status_code == 201
    assert book(client, live_db, workshop_id, booking_id=booking_id).json()["status"] == "cancelled"
    assert live_db.active_count(workshop_id) == 1


def test_authentication_ownership_and_uuid_conflicts(client, live_db, workshop):
    workshop_id, other_workshop_id, booking_id = workshop(), workshop(), uuid4()
    assert book(client, live_db, workshop_id, booking_id=booking_id).status_code == 201
    for method in (client.get, client.delete):
        assert method(f"/bookings/{booking_id}").status_code == 401
        assert (
            method(f"/bookings/{booking_id}", headers={"Authorization": "Bearer wrong"}).status_code
            == 401
        )
        assert method(f"/bookings/{booking_id}", headers=live_db.headers(1)).status_code == 404
        assert method(f"/bookings/{uuid4()}", headers=live_db.headers()).status_code == 404
    assert book(client, live_db, workshop_id, attendee=1, booking_id=booking_id).status_code == 409
    assert book(client, live_db, other_workshop_id, booking_id=booking_id).status_code == 409
    assert live_db.active_count(workshop_id) == 1
    assert live_db.active_count(other_workshop_id) == 0


@pytest.mark.parametrize("attempt", range(3))
def test_two_attendees_compete_for_the_last_seat(client, live_db, workshop, attempt):
    workshop_id = workshop(1)
    start = Barrier(2)

    def compete(attendee):
        start.wait(timeout=10)
        return book(client, live_db, workshop_id, attendee=attendee)

    with ThreadPoolExecutor(max_workers=2) as pool:
        responses = list(pool.map(compete, (0, 1)))
    assert sorted(response.status_code for response in responses) == [201, 409]
    assert live_db.active_count(workshop_id) == 1


def test_concurrent_duplicate_uuid_returns_one_receipt(client, live_db, workshop):
    workshop_id, booking_id = workshop(1), uuid4()
    start = Barrier(2)

    def submit(_):
        start.wait(timeout=10)
        return book(client, live_db, workshop_id, booking_id=booking_id)

    with ThreadPoolExecutor(max_workers=2) as pool:
        responses = list(pool.map(submit, (0, 1)))
    assert sorted(response.status_code for response in responses) == [200, 201]
    assert responses[0].json() == responses[1].json()
    assert live_db.active_count(workshop_id) == 1


def test_concurrent_same_uuid_for_different_workshops_conflicts(client, live_db, workshop):
    workshops, booking_id = (workshop(), workshop()), uuid4()
    start = Barrier(2)

    def submit(workshop_id):
        start.wait(timeout=10)
        return book(client, live_db, workshop_id, booking_id=booking_id)

    with ThreadPoolExecutor(max_workers=2) as pool:
        responses = list(pool.map(submit, workshops))
    assert sorted(response.status_code for response in responses) == [201, 409]
    assert sum(live_db.active_count(workshop_id) for workshop_id in workshops) == 1
    receipt = client.get(f"/bookings/{booking_id}", headers=live_db.headers())
    winner = next(response for response in responses if response.status_code == 201)
    assert receipt.json() == winner.json()


def test_concurrent_cancellations_restore_exactly_one_seat(client, live_db, workshop):
    workshop_id, booking_id = workshop(1), uuid4()
    assert book(client, live_db, workshop_id, booking_id=booking_id).status_code == 201
    start = Barrier(3)

    def compete(operation):
        start.wait(timeout=10)
        if operation == "book":
            return book(client, live_db, workshop_id, attendee=1)
        return client.delete(f"/bookings/{booking_id}", headers=live_db.headers())

    with ThreadPoolExecutor(max_workers=3) as pool:
        responses = list(pool.map(compete, ("cancel", "cancel", "book")))
    assert [response.status_code for response in responses[:2]] == [200, 200]
    assert responses[0].json() == responses[1].json()
    assert responses[2].status_code in (201, 409)
    if responses[2].status_code == 409:
        assert book(client, live_db, workshop_id, attendee=1).status_code == 201
    assert live_db.active_count(workshop_id) == 1
    assert book(client, live_db, workshop_id, attendee=2).status_code == 409


def test_started_workshops_reject_new_bookings_and_active_cancellations(client, live_db, workshop):
    expired = workshop(started=True)
    assert book(client, live_db, expired).status_code == 409
    workshop_id, booking_id = workshop(), uuid4()
    assert book(client, live_db, workshop_id, booking_id=booking_id).status_code == 201
    with live_db.owner_engine.begin() as connection:
        connection.execute(text("SET LOCAL ROLE workshop_booking_owner"))
        connection.execute(
            text(
                "UPDATE workshop_booking.workshops "
                "SET starts_at = clock_timestamp() - interval '1 hour' "
                "WHERE id = :id"
            ),
            {"id": workshop_id},
        )
    assert client.delete(f"/bookings/{booking_id}", headers=live_db.headers()).status_code == 409
    # A network retry is still allowed after the start time.
    replay = book(client, live_db, workshop_id, booking_id=booking_id)
    assert replay.status_code == 200
    assert replay.json()["status"] == "confirmed"
    assert live_db.active_count(workshop_id) == 1


@pytest.mark.parametrize("operation", ("book", "cancel"))
def test_start_time_is_checked_after_waiting_for_the_lock(client, live_db, workshop, operation):
    workshop_id, booking_id = workshop(2), uuid4()
    if operation == "cancel":
        assert book(client, live_db, workshop_id, booking_id=booking_id).status_code == 201
    attempting_lock = Event()

    def observe_lock(_connection, _cursor, statement, _parameters, _context, _many):
        if "workshop_booking.workshops" in statement and "FOR UPDATE" in statement:
            attempting_lock.set()

    def request():
        if operation == "book":
            return book(client, live_db, workshop_id, booking_id=booking_id)
        return client.delete(f"/bookings/{booking_id}", headers=live_db.headers())

    event.listen(live_db.engine, "before_cursor_execute", observe_lock)
    try:
        with ThreadPoolExecutor(max_workers=1) as pool:
            with live_db.owner_engine.begin() as connection:
                connection.execute(text("SET LOCAL ROLE workshop_booking_owner"))
                connection.execute(
                    text(
                        "UPDATE workshop_booking.workshops "
                        "SET starts_at = clock_timestamp() + interval '1 second' WHERE id = :id"
                    ),
                    {"id": workshop_id},
                )
                pending = pool.submit(request)
                assert attempting_lock.wait(timeout=5)
                # Keep the parent lock until after its new start time. The API
                # must check actual database time after acquiring this lock.
                connection.execute(text("SELECT pg_sleep(1.1)"))
                assert not pending.done()
            response = pending.result(timeout=10)
        assert response.status_code == 409
        assert live_db.active_count(workshop_id) == (1 if operation == "cancel" else 0)
    finally:
        event.remove(live_db.engine, "before_cursor_execute", observe_lock)


def test_public_catalog_and_input_validation(client, live_db, workshop):
    workshop_id = workshop()
    expired_id = workshop(started=True)
    response = client.get("/workshops?limit=100")
    assert response.status_code == 200
    assert str(workshop_id) in response.text
    assert str(expired_id) not in response.text
    for query in ("limit=0", "limit=101", "offset=-1", "offset=10001"):
        assert client.get(f"/workshops?{query}").status_code == 422
    assert (
        client.post("/bookings", headers=live_db.headers(), json={"id": "bad"}).status_code == 422
    )
    assert book(client, live_db, uuid4()).status_code == 404


def test_application_rolls_back_a_flushed_booking_on_database_error(
    client, live_db, workshop, monkeypatch
):
    workshop_id = workshop(1)
    original = app.main.create_booking

    def fail_after_insert(*args, **kwargs):
        original(*args, **kwargs)  # Includes the real INSERT and session.flush().
        raise SQLAlchemyError("Injected error after insert")

    monkeypatch.setattr(app.main, "create_booking", fail_after_insert)
    response = book(client, live_db, workshop_id)
    assert response.status_code == 503
    assert response.headers["Retry-After"] == "1"
    assert "Injected" not in response.text
    assert live_db.active_count(workshop_id) == 0
    monkeypatch.setattr(app.main, "create_booking", original)
    assert book(client, live_db, workshop_id).status_code == 201
