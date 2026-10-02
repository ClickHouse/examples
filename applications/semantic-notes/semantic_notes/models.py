from datetime import datetime, timezone
from uuid import UUID, uuid4

from pgvector.sqlalchemy import VECTOR
from sqlalchemy import Column, DateTime
from sqlalchemy.dialects.postgresql import JSONB
from sqlmodel import Field, SQLModel


class Collection(SQLModel, table=True):
    __tablename__ = "collection"
    __table_args__ = {"schema": "semantic_notes"}
    id: int = Field(primary_key=True)
    spec: dict = Field(sa_column=Column(JSONB, nullable=False))


class Note(SQLModel, table=True):
    __tablename__ = "notes"
    __table_args__ = {"schema": "semantic_notes"}
    id: UUID = Field(default_factory=uuid4, primary_key=True)
    collection_id: int = Field(default=1, foreign_key="semantic_notes.collection.id")
    title: str
    body: str
    embedding: list[float] = Field(sa_type=VECTOR(384))
    revision: int = Field(default=1)
    created_at: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc),
        sa_column=Column(DateTime(timezone=True), nullable=False),
    )
    updated_at: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc),
        sa_column=Column(DateTime(timezone=True), nullable=False),
    )
