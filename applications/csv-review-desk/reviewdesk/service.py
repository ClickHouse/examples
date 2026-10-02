import uuid
from datetime import datetime, timezone

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from reviewdesk.models import Batch, CatalogueItem, StagedRow
from reviewdesk.validation import HEADERS, ReviewError, parse_csv, raw_record, validate_records


def _uuid(value):
    try:
        return uuid.UUID(str(value))
    except (ValueError, TypeError, AttributeError) as exc:
        raise ReviewError("Unknown batch or row.") from exc


def _locked(session, batch_id, read=False):
    batch = session.scalar(
        select(Batch).where(Batch.id == _uuid(batch_id)).with_for_update(read=read)
    )
    if batch is None:
        raise ReviewError("Batch not found.")
    return batch


def _revision(batch, expected):
    if type(expected) is not int or batch.revision != expected:
        raise ReviewError(
            "This batch changed in another session. Refresh and review the committed rows before saving."
        )
    if batch.status != "pending":
        raise ReviewError("Approved batches cannot be edited.")


def _rows(session, batch):
    return list(
        session.scalars(
            select(StagedRow).where(StagedRow.batch_id == batch.id).order_by(StagedRow.position)
        )
    )


def _feedback(session, rows):
    records = [{key: getattr(row, key) for key in HEADERS} for row in rows]
    existing = session.scalars(
        select(CatalogueItem.sku).where(CatalogueItem.sku.in_([r["sku"] for r in records]))
    )
    errors = validate_records(records, existing)
    for row, issues in zip(rows, errors):
        row.errors = issues
    return errors


def create_batch(engine, filename, data):
    records = parse_csv(data)
    filename = str(filename).replace("\x00", "")[:120] or "upload.csv"
    with Session(engine) as session, session.begin():
        batch = Batch(filename=filename, row_count=len(records))
        session.add(batch)
        session.flush()
        rows = [
            StagedRow(batch_id=batch.id, position=i, errors=[], **record)
            for i, record in enumerate(records)
        ]
        session.add_all(rows)
        _feedback(session, rows)
        session.flush()
        result = str(batch.id)
    return result


def save_rows(engine, batch_id, expected_revision, submitted):
    with Session(engine) as session, session.begin():
        batch = _locked(session, batch_id)
        _revision(batch, expected_revision)
        rows = _rows(session, batch)
        if not isinstance(submitted, list) or len(submitted) != len(rows):
            raise ReviewError(
                "Save the complete fixed set of rows; rows cannot be added or removed."
            )
        values = {}
        for record in submitted:
            if not isinstance(record, dict) or set(record) != {"id", *HEADERS}:
                raise ReviewError("Submit the fixed row identity and its three editable fields.")
            row_id = _uuid(record["id"])
            if row_id in values:
                raise ReviewError("Repeated row identity.")
            values[row_id] = raw_record({key: record[key] for key in HEADERS})
        if set(values) != {row.id for row in rows}:
            raise ReviewError("The submitted row identities do not belong to this batch.")
        for row in rows:
            for key, value in values[row.id].items():
                setattr(row, key, value)
        _feedback(session, rows)
        batch.revision += 1
    return get_batch(engine, batch_id)


def approve_batch(engine, batch_id, expected_revision):
    failure = None
    try:
        with Session(engine) as session, session.begin():
            batch = _locked(session, batch_id)
            if batch.status == "approved":
                return {
                    "batch_id": str(batch.id),
                    "published_rows": batch.row_count,
                    "approved_at": batch.approved_at.isoformat(),
                }
            _revision(batch, expected_revision)
            rows = _rows(session, batch)
            errors = _feedback(session, rows)
            if any(errors):
                batch.revision += 1
                failure = (
                    "Approval stopped: correct the saved row issues, then review and approve again."
                )
            else:
                for row in sorted(rows, key=lambda row: row.sku):
                    session.add(
                        CatalogueItem(
                            sku=row.sku,
                            name=row.name,
                            price_cents=int(row.price_cents),
                            source_batch_id=batch.id,
                            source_row_id=row.id,
                        )
                    )
                session.flush()
                batch.status = "approved"
                batch.approved_at = datetime.now(timezone.utc)
                batch.revision += 1
                result = {
                    "batch_id": str(batch.id),
                    "published_rows": batch.row_count,
                    "approved_at": batch.approved_at.isoformat(),
                }
    except IntegrityError as exc:
        # The transaction rolls back every inserted row if another batch wins a SKU.
        if (
            getattr(getattr(exc.orig, "diag", None), "constraint_name", None)
            == "catalogue_items_pkey"
        ):
            raise ReviewError(
                "Approval rolled back: a catalogue SKU conflict appeared. Refresh and save to update validation."
            ) from exc
        raise ReviewError(
            "Approval rolled back because a database constraint rejected the publication."
        ) from exc
    if failure:
        raise ReviewError(failure)
    return result


def get_batch(engine, batch_id):
    with Session(engine) as session, session.begin():
        # Keep the parent revision and its rows in one consistent shared-lock read.
        batch = _locked(session, batch_id, read=True)
        rows = _rows(session, batch)
        return {
            "id": str(batch.id),
            "filename": batch.filename,
            "status": batch.status,
            "revision": batch.revision,
            "row_count": batch.row_count,
            "approved_at": batch.approved_at.isoformat() if batch.approved_at else None,
            "rows": [
                {
                    "id": str(row.id),
                    **{key: getattr(row, key) for key in HEADERS},
                    "errors": list(row.errors),
                }
                for row in rows
            ],
        }


def list_batches(engine, page=1):
    if type(page) is not int or page < 1:
        raise ReviewError("Page must be a positive integer.")
    with Session(engine) as session:
        total = session.scalar(select(func.count()).select_from(Batch))
        batches = session.scalars(
            select(Batch)
            .order_by(Batch.created_at.desc(), Batch.id)
            .limit(20)
            .offset((page - 1) * 20)
        )
        return total, [
            {
                "id": str(b.id),
                "filename": b.filename,
                "status": b.status,
                "revision": b.revision,
                "row_count": b.row_count,
            }
            for b in batches
        ]
