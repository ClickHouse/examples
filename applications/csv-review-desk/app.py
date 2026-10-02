import math

import pandas as pd
import streamlit as st
from sqlalchemy.exc import SQLAlchemyError

from reviewdesk.database import make_engine
from reviewdesk.service import approve_batch, create_batch, get_batch, list_batches, save_rows
from reviewdesk.validation import HEADERS, ReviewError

st.set_page_config(page_title="CSV review desk", page_icon="📋", layout="wide")


@st.cache_resource
def engine():
    # A thread-safe pool is shared. Every operation creates its own Session.
    return make_engine()


def show_flash():
    message = st.session_state.pop("flash", None)
    if message:
        st.success(message)


def reload_batch(message=None):
    if message:
        st.session_state.flash = message
    # Deliberately discard old editor widget state before reading committed data.
    for key in list(st.session_state):
        if key.startswith("editor_"):
            del st.session_state[key]
    st.rerun()


def board():
    st.title("CSV review desk")
    st.write("Stage catalogue rows, correct the details, then publish a complete batch.")
    show_flash()
    with st.container(border=True):
        st.subheader("Start a batch")
        st.caption("UTF-8 CSV · exact header sku,name,price_cents · up to 200 rows / 256 KiB")
        with st.form("upload"):
            upload = st.file_uploader("Catalogue CSV", type=["csv"])
            submitted = st.form_submit_button("Upload for review", type="primary")
        if submitted:
            if upload is None:
                st.warning("Choose a CSV first.")
            else:
                batch_id = create_batch(engine(), upload.name, upload.getvalue())
                st.query_params["batch"] = batch_id
                st.session_state.flash = "Batch saved. Corrections and validation stay in Postgres."
                st.rerun()
    st.subheader("Saved batches")
    page = st.number_input("Batch page", min_value=1, value=1, step=1)
    total, batches = list_batches(engine(), page)
    st.caption(
        f"{total} batches · page {page} of {max(1, math.ceil(total / 20))} · newest first · 20 per page"
    )
    if not batches:
        st.info("No batches on this page. Upload a sample CSV to begin.")
    for batch in batches:
        with st.container(border=True):
            left, right = st.columns([5, 1])
            left.text(batch["filename"])
            left.caption(
                f"{batch['status'].capitalize()} · {batch['row_count']} rows · revision {batch['revision']}"
            )
            if right.button("Review", key=f"open_{batch['id']}"):
                st.query_params["batch"] = batch["id"]
                st.rerun()


def review(batch_id):
    if st.button("← All batches"):
        st.query_params.clear()
        st.rerun()
    batch = get_batch(engine(), batch_id)
    seen_key = f"seen_{batch_id}"
    seen = st.session_state.get(seen_key)
    revision_changed = seen is not None and seen != batch["revision"]
    if revision_changed:
        for key in list(st.session_state):
            if key.startswith(f"editor_{batch_id}_"):
                del st.session_state[key]
        st.warning(
            "The saved revision changed. The editor now shows committed rows; unsaved local changes were discarded."
        )
    st.session_state[seen_key] = batch["revision"]
    st.title("Review batch")
    st.text(batch["filename"])
    show_flash()
    issues = sum(bool(row["errors"]) for row in batch["rows"])
    a, b, c = st.columns(3)
    a.metric("Rows", batch["row_count"])
    b.metric("Rows with issues", issues)
    c.metric("Saved revision", batch["revision"])
    if batch["status"] == "approved":
        st.success(
            f"Approved · {batch['row_count']} catalogue items published · {batch['approved_at']}"
        )
        st.dataframe(
            pd.DataFrame([{key: row[key] for key in HEADERS} for row in batch["rows"]]),
            hide_index=True,
            width="stretch",
        )
        st.caption(
            "These saved rows are immutable. A repeated approval returns the same publication."
        )
        if st.button("Confirm approval again"):
            result = approve_batch(engine(), batch_id, batch["revision"])
            reload_batch(
                f"Already approved: {result['published_rows']} items; original approval retained."
            )
        return
    st.subheader("Correct the rows")
    st.caption(
        "SKU and price stay as text while you review. Price is whole cents, not dollars. Save corrections before approving."
    )
    frame = pd.DataFrame(
        [
            {**{key: row[key] for key in ["id", *HEADERS]}, "issues": "; ".join(row["errors"])}
            for row in batch["rows"]
        ]
    )
    with st.form(f"edit_{batch_id}_{batch['revision']}"):
        edited = st.data_editor(
            frame,
            key=f"editor_{batch_id}_{batch['revision']}",
            num_rows="fixed",
            hide_index=True,
            disabled=["id", "issues"],
            column_config={
                "id": None,
                "sku": st.column_config.TextColumn("SKU"),
                "name": st.column_config.TextColumn("Name"),
                "price_cents": st.column_config.TextColumn("Price (cents)"),
                "issues": st.column_config.TextColumn("Saved issues"),
            },
            width="stretch",
        )
        save = st.form_submit_button("Save corrections", type="primary")
    if save and not revision_changed:
        submitted = [
            {key: row[key] for key in ["id", *HEADERS]} for row in edited.to_dict("records")
        ]
        save_rows(engine(), batch_id, batch["revision"], submitted)
        reload_batch("Corrections saved. Review the committed validation below.")
    if issues:
        st.warning("Approval is blocked until every saved row is valid.")
        for i, row in enumerate(batch["rows"], 1):
            if row["errors"]:
                st.text(f"Row {i}: " + " ".join(row["errors"]))
    else:
        st.info(
            "All saved rows are valid. Approval checks catalogue conflicts again and publishes the complete batch."
        )
    left, right = st.columns([1, 3])
    if left.button("Approve batch", disabled=bool(issues), type="primary") and not revision_changed:
        result = approve_batch(engine(), batch_id, batch["revision"])
        reload_batch(f"Approved: {result['published_rows']} catalogue items.")
    if right.button("Refresh saved rows"):
        reload_batch()


try:
    if "batch" in st.query_params:
        review(st.query_params["batch"])
    else:
        board()
except ReviewError as exc:
    st.error(str(exc))
    if st.button("Reload committed data"):
        reload_batch()
except (SQLAlchemyError, OSError, KeyError, ValueError):
    st.error(
        "The review desk could not reach its database or configuration. Please try again once the connection is available."
    )
    if st.button("Try again"):
        st.rerun()
