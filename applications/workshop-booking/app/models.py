"""ORM mapping. The checked-in SQL migrations own schema creation."""

from datetime import datetime
from uuid import UUID

from sqlalchemy import DateTime, ForeignKey, Integer, MetaData, String, Text, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    metadata = MetaData(schema="workshop_booking")


class Workshop(Base):
    __tablename__ = "workshops"

    id: Mapped[UUID] = mapped_column(primary_key=True)
    title: Mapped[str] = mapped_column(String(160))
    description: Mapped[str] = mapped_column(Text)
    starts_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    duration_minutes: Mapped[int] = mapped_column(Integer)
    capacity: Mapped[int] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.clock_timestamp()
    )


class Attendee(Base):
    __tablename__ = "attendees"

    id: Mapped[UUID] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(120))
    email: Mapped[str] = mapped_column(String(254), unique=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.clock_timestamp()
    )


class Booking(Base):
    __tablename__ = "bookings"

    id: Mapped[UUID] = mapped_column(primary_key=True)
    workshop_id: Mapped[UUID] = mapped_column(ForeignKey("workshop_booking.workshops.id"))
    attendee_id: Mapped[UUID] = mapped_column(ForeignKey("workshop_booking.attendees.id"))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.clock_timestamp()
    )
    cancelled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    @property
    def status(self) -> str:
        return "cancelled" if self.cancelled_at is not None else "confirmed"
