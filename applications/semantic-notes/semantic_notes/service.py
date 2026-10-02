from datetime import datetime, timezone
from uuid import UUID

from sqlalchemy import func
from sqlmodel import Session, select

from .embeddings import checked_vector
from .models import Collection, Note
from .spec import SPEC


class DomainError(Exception):
    def __init__(self, message, status=422):
        super().__init__(message)
        self.status = status


def verify_collection(engine):
    with Session(engine) as session:
        collection = session.get(Collection, 1)
        if collection is None or collection.spec != SPEC:
            raise ValueError("Database collection and full model specification differ.")


def view(note):
    return {
        "id": str(note.id),
        "title": note.title,
        "body": note.body,
        "revision": note.revision,
        "created_at": note.created_at.isoformat(),
        "updated_at": note.updated_at.isoformat(),
    }


def create_note(engine, fields, vector):
    vector = checked_vector(vector)
    with Session(engine) as session, session.begin():
        collection = session.exec(
            select(Collection).where(Collection.id == 1).with_for_update()
        ).one()
        if collection.spec != SPEC:
            raise DomainError("Collection specification mismatch.", 503)
        count = session.exec(select(func.count()).select_from(Note)).one()
        if count >= 100:
            raise DomainError("This notebook holds at most 100 notes.", 409)
        note = Note(title=fields.title, body=fields.body, embedding=vector.tolist())
        session.add(note)
        session.flush()
        result = view(note)
    return result


def update_note(engine, note_id: UUID, fields, vector):
    vector = checked_vector(vector)
    with Session(engine) as session, session.begin():
        note = session.exec(
            select(Note).where(Note.id == note_id).with_for_update()
        ).first()
        if note is None:
            raise DomainError("Note not found.", 404)
        if note.revision != fields.revision:
            raise DomainError(
                "This note changed while you were editing. Reload before saving.", 409
            )
        note.title, note.body, note.embedding = (
            fields.title,
            fields.body,
            vector.tolist(),
        )
        note.revision += 1
        note.updated_at = datetime.now(timezone.utc)
        session.add(note)
        session.flush()
        result = view(note)
    return result


def read_note(engine, note_id):
    with Session(engine) as session:
        note = session.get(Note, note_id)
        if note is None:
            raise DomainError("Note not found.", 404)
        return view(note)


def list_notes(engine, page=1):
    if not isinstance(page, int) or not 1 <= page <= 10:
        raise DomainError("Page must be 1–10.")
    with Session(engine) as session, session.begin():
        session.connection().exec_driver_sql(
            "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY"
        )
        total = session.exec(select(func.count()).select_from(Note)).one()
        notes = session.exec(
            select(Note)
            .order_by(Note.updated_at.desc(), Note.id)
            .limit(12)
            .offset((page - 1) * 12)
        ).all()
        return {
            "notes": [view(n) for n in notes],
            "total": total,
            "page": page,
            "page_size": 12,
        }


def search_notes(engine, fields, vector):
    vector = checked_vector(vector)
    distance = Note.embedding.cosine_distance(vector)
    statement = select(Note, distance.label("distance"))
    if fields.title_filter:
        literal = (
            fields.title_filter.replace("\\", "\\\\")
            .replace("%", "\\%")
            .replace("_", "\\_")
        )
        statement = statement.where(Note.title.ilike(f"%{literal}%", escape="\\"))
    statement = statement.order_by(distance, Note.id).limit(fields.k)
    with Session(engine) as session:
        return [
            {**view(note), "distance": float(value), "excerpt": note.body[:240]}
            for note, value in session.exec(statement).all()
        ]
