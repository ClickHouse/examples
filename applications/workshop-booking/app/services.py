"""The seat invariant lives in these short, explicit database transactions."""

from uuid import UUID

from fastapi import HTTPException
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import Booking, Workshop
from app.schemas import BookingCreate, BookingResponse, WorkshopResponse


def list_workshops(session: Session, limit: int, offset: int) -> list[WorkshopResponse]:
    active_count = (
        select(func.count(Booking.id))
        .where(Booking.workshop_id == Workshop.id, Booking.cancelled_at.is_(None))
        .correlate(Workshop)
        .scalar_subquery()
    )
    rows = session.execute(
        select(Workshop, active_count.label("booked"))
        .where(Workshop.starts_at > func.statement_timestamp())
        .order_by(Workshop.starts_at, Workshop.id)
        .limit(limit)
        .offset(offset)
    )
    return [
        WorkshopResponse(
            id=workshop.id,
            title=workshop.title,
            description=workshop.description,
            starts_at=workshop.starts_at,
            duration_minutes=workshop.duration_minutes,
            capacity=workshop.capacity,
            available_seats=workshop.capacity - booked,
        )
        for workshop, booked in rows
    ]


def create_booking(
    session: Session, attendee_id: UUID, request: BookingCreate
) -> tuple[BookingResponse, bool]:
    # Every capacity-changing transaction locks the same parent row first.
    workshop = session.scalar(
        select(Workshop).where(Workshop.id == request.workshop_id).with_for_update()
    )
    if workshop is None:
        raise HTTPException(404, "Workshop not found.")

    existing = session.get(Booking, request.id)
    if existing is not None:
        if existing.attendee_id != attendee_id or existing.workshop_id != request.workshop_id:
            raise HTTPException(409, "Booking ID has already been used.")
        # Retrying a cancelled booking never creates a new reservation.
        return BookingResponse.model_validate(existing), False

    # CURRENT_TIMESTAMP is fixed at transaction start; use actual time after waiting.
    now = session.scalar(select(func.clock_timestamp()))
    if workshop.starts_at <= now:
        raise HTTPException(409, "This workshop has already started.")
    duplicate = session.scalar(
        select(Booking.id).where(
            Booking.workshop_id == workshop.id,
            Booking.attendee_id == attendee_id,
            Booking.cancelled_at.is_(None),
        )
    )
    if duplicate is not None:
        raise HTTPException(409, "You already have an active booking for this workshop.")
    booked = session.scalar(
        select(func.count(Booking.id)).where(
            Booking.workshop_id == workshop.id, Booking.cancelled_at.is_(None)
        )
    )
    if booked >= workshop.capacity:
        raise HTTPException(409, "This workshop is full.")

    booking = Booking(id=request.id, workshop_id=workshop.id, attendee_id=attendee_id)
    session.add(booking)
    session.flush()
    return BookingResponse.model_validate(booking), True


def get_booking(session: Session, attendee_id: UUID, booking_id: UUID) -> BookingResponse:
    booking = session.scalar(
        select(Booking).where(Booking.id == booking_id, Booking.attendee_id == attendee_id)
    )
    if booking is None:
        raise HTTPException(404, "Booking not found.")
    return BookingResponse.model_validate(booking)


def cancel_booking(session: Session, attendee_id: UUID, booking_id: UUID) -> BookingResponse:
    # Read only the parent ID here: acquiring a booking lock first could deadlock
    # with a create transaction. Workshop and owner IDs are never changed by the API.
    workshop_id = session.scalar(
        select(Booking.workshop_id).where(
            Booking.id == booking_id, Booking.attendee_id == attendee_id
        )
    )
    if workshop_id is None:
        raise HTTPException(404, "Booking not found.")
    workshop = session.scalar(select(Workshop).where(Workshop.id == workshop_id).with_for_update())
    booking = session.scalar(
        select(Booking)
        .where(Booking.id == booking_id, Booking.attendee_id == attendee_id)
        .with_for_update()
    )
    if booking.cancelled_at is not None:
        return BookingResponse.model_validate(booking)
    now = session.scalar(select(func.clock_timestamp()))
    if workshop.starts_at <= now:
        raise HTTPException(409, "This workshop has already started.")
    booking.cancelled_at = now
    session.flush()
    return BookingResponse.model_validate(booking)
