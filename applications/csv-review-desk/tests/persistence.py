"""After an actual process restart, compare the browser's durable approved batch."""

import json
import os
from pathlib import Path

from playwright.sync_api import expect, sync_playwright

from reviewdesk.database import make_engine
from reviewdesk.service import get_batch


def run():
    evidence = Path(os.environ.get("EVIDENCE_DIR", "/tmp/csv-review-desk-evidence"))
    before = json.loads((evidence / "persistence.json").read_text())
    engine = make_engine()
    try:
        after = get_batch(engine, before["id"])
        assert before == after, (
            "Saved revision, identities, raw rows and original approval must survive"
        )
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch()
            page = browser.new_page(viewport={"width": 1440, "height": 1100})
            page.goto("http://127.0.0.1:8501/?batch=" + before["id"])
            expect(
                page.get_by_role("button", name="Confirm approval again", exact=True)
            ).to_be_visible(timeout=30000)
            expect(page.locator('[data-testid="data-grid-canvas"]').first).to_be_visible()
            expect(page.locator('[data-testid="glide-cell-1-0"]')).to_have_text(
                before["rows"][0]["name"]
            )
            browser.close()
        print(
            "PASS real restarted process reads identical approved batch and displays it at its durable URL"
        )
        print("Batch", before["id"], "revision", before["revision"], "rows", before["row_count"])
    finally:
        engine.dispose()


if __name__ == "__main__":
    run()
