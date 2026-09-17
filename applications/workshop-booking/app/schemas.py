from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class BookingCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID = Field(
        description="A new client-generated UUID; reuse it when retrying this booking."
    )
    workshop_id: UUID


class BookingResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    workshop_id: UUID
    attendee_id: UUID
    status: Literal["confirmed", "cancelled"]
    created_at: datetime
    cancelled_at: datetime | None


class WorkshopResponse(BaseModel):
    id: UUID
    title: str
    description: str
    starts_at: datetime
    duration_minutes: int
    capacity: int
    available_seats: int
