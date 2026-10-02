"""Real Streamlit upload/editor workflow; run on the dedicated local workbench."""

import os
import time
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from playwright.sync_api import expect, sync_playwright
from sqlalchemy import text

from reviewdesk.database import make_engine
from reviewdesk.service import get_batch

expect.set_options(timeout=30000)
BASE_URL = "http://127.0.0.1:8501"
ARTIFACTS = Path(os.environ.get("EVIDENCE_DIR", "/tmp/csv-review-desk-evidence"))
ARTIFACTS.mkdir(parents=True, exist_ok=True)


def ready(page):
    expect(page.get_by_role("button", name="Save corrections", exact=True)).to_be_visible()
    expect(page.locator('[data-testid="data-grid-canvas"]').first).to_be_visible()


def edit_cell(page, column, value):
    canvas = page.locator('[data-testid="data-grid-canvas"]').first
    box = canvas.bounding_box()
    page.mouse.click(box["x"] + 25, box["y"] + 54)
    for _ in range(column):
        page.keyboard.press("ArrowRight")
    page.keyboard.press("Enter")
    editor = page.get_by_role("textbox").last
    expect(editor).to_be_visible()
    editor.fill(value)
    editor.press("Tab")
    # Streamlit debounces editor widget-state serialization. Let that bounded
    # frontend commit settle before submitting the enclosing form.
    page.wait_for_timeout(750)


def run():
    engine = make_engine()
    errors = []
    uploads = []
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        first_context = browser.new_context(viewport={"width": 1440, "height": 1100})
        second_context = browser.new_context(viewport={"width": 1440, "height": 1100})
        first, second = first_context.new_page(), second_context.new_page()
        first_context.tracing.start(screenshots=True, snapshots=True)
        for page in [first, second]:
            page.on("pageerror", lambda error: errors.append(str(error)))
        first.on(
            "request",
            lambda request: uploads.append(request.url) if "upload_file" in request.url else None,
        )
        try:
            first.goto(BASE_URL)
            expect(first.get_by_role("heading", name="CSV review desk", exact=True)).to_be_visible()
            first.locator('input[type="file"]').set_input_files(
                {
                    "name": "notebook-review.csv",
                    "mimeType": "text/csv",
                    "buffer": f"sku,name,price_cents\nBROWSER-{int(time.time())},Notebook,3.50\n".encode(),
                }
            )
            first.get_by_role("button", name="Upload for review", exact=True).click()
            expect(first.get_by_role("heading", name="Review batch", exact=True)).to_be_visible()
            ready(first)
            expect(first.get_by_role("button", name="Approve batch", exact=True)).to_be_disabled()
            batch_id = parse_qs(urlparse(first.url).query)["batch"][0]
            first.screenshot(path=str(ARTIFACTS / "csv-invalid.png"), full_page=True)
            edit_cell(first, 2, "350")
            first.get_by_role("button", name="Save corrections", exact=True).click()
            expect(
                first.get_by_text(
                    "Corrections saved. Review the committed validation below.", exact=True
                )
            ).to_be_visible()
            ready(first)
            self_check = get_batch(engine, batch_id)
            assert self_check["revision"] == 2
            assert self_check["rows"][0]["price_cents"] == "350"
            assert self_check["rows"][0]["errors"] == []
            expect(first.get_by_role("button", name="Approve batch", exact=True)).to_be_enabled()

            # Another actual browser session changes the rows after first has reviewed revision2.
            second.goto(first.url)
            ready(second)
            edit_cell(second, 1, "Notebook revised")
            second.get_by_role("button", name="Save corrections", exact=True).click()
            expect(
                second.get_by_text(
                    "Corrections saved. Review the committed validation below.", exact=True
                )
            ).to_be_visible()
            ready(second)
            assert get_batch(engine, batch_id)["revision"] == 3
            first.get_by_role("button", name="Approve batch", exact=True).click()
            expect(
                first.get_by_text(
                    "The saved revision changed. The editor now shows committed rows; unsaved local changes were discarded.",
                    exact=True,
                )
            ).to_be_visible()
            assert get_batch(engine, batch_id)["status"] == "pending"
            with engine.connect() as conn:
                assert (
                    conn.scalar(
                        text("SELECT count(*) FROM catalogue_items WHERE source_batch_id=:id"),
                        {"id": batch_id},
                    )
                    == 0
                )
            expect(first.locator('[data-testid="glide-cell-1-0"]')).to_have_text("Notebook revised")
            first.screenshot(path=str(ARTIFACTS / "csv-desktop.png"), full_page=True)

            # Fresh click after inspecting refreshed revision3 can publish it.
            first.get_by_role("button", name="Approve batch", exact=True).click()
            expect(first.get_by_text("Approved: 1 catalogue items.", exact=True)).to_be_visible()
            current = get_batch(engine, batch_id)
            assert current["status"] == "approved" and current["revision"] == 4
            assert current["rows"][0]["name"] == "Notebook revised"
            approved_at = current["approved_at"]
            first.get_by_role("button", name="Confirm approval again", exact=True).click()
            expect(
                first.get_by_text(
                    "Already approved: 1 items; original approval retained.", exact=True
                )
            ).to_be_visible()
            assert get_batch(engine, batch_id)["approved_at"] == approved_at
            first.screenshot(path=str(ARTIFACTS / "csv-approved.png"), full_page=True)

            # Native upload endpoint refuses a request without an XSRF header.
            assert uploads, "Actual upload endpoint was observed"
            response = first_context.request.put(
                uploads[0],
                multipart={
                    "file": {
                        "name": "no-token.csv",
                        "mimeType": "text/csv",
                        "buffer": b"sku,name,price_cents\nA,a,1\n",
                    }
                },
            )
            assert response.status == 403, f"Expected native XSRF403, got {response.status}"
            mobile = browser.new_page(viewport={"width": 390, "height": 844})
            mobile.goto(first.url)
            expect(
                mobile.get_by_role("button", name="Confirm approval again", exact=True)
            ).to_be_visible()
            assert mobile.evaluate("document.documentElement.scrollWidth <= window.innerWidth")
            mobile.screenshot(path=str(ARTIFACTS / "csv-mobile.png"), full_page=True)
            assert not errors, errors
            (ARTIFACTS / "persistence.json").write_text(__import__("json").dumps(current))
            print(
                "PASS actual upload, invalid feedback, editor correction, durable exact price, two-session stale-click rejection, fresh approval, repeat result, native XSRF403, desktop/mobile fit, no page errors"
            )
            print("Batch", batch_id)
        finally:
            first_context.tracing.stop(path=str(ARTIFACTS / "browser-trace.zip"))
            browser.close()
            engine.dispose()


if __name__ == "__main__":
    run()
