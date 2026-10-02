"""Actual form workflow; evidence stays outside the source checkout."""

import asyncio
import json
import os
from pathlib import Path

from playwright.async_api import async_playwright, expect

ORIGIN = "http://127.0.0.1:8000"
ARTIFACTS = Path(os.getenv("EVIDENCE_DIR", "/tmp/semantic-notes-evidence"))
ARTIFACTS.mkdir(parents=True, exist_ok=True)


async def main():
    async with async_playwright() as playwright:
        browser = await playwright.chromium.launch()
        context = await browser.new_context(viewport={"width": 1440, "height": 1100})
        other = await browser.new_context(viewport={"width": 1280, "height": 900})
        page, stale = await context.new_page(), await other.new_page()
        errors = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        await page.goto(ORIGIN)
        await expect(
            page.get_by_role("heading", name="Find the thought.")
        ).to_be_visible(timeout=30000)
        await page.get_by_label("Title", exact=True).fill("Project memory")
        await page.get_by_label("Note", exact=True).fill(
            "Keep a brief record of decisions after each project meeting so the team can revisit the reasons."
        )
        await page.get_by_role("button", name="Save note", exact=True).click()
        await expect(page.get_by_role("status")).to_have_text(
            "Note saved.", timeout=30000
        )
        note_url = page.url.split("?")[0]
        await stale.goto(note_url)
        await expect(stale.get_by_label("Title", exact=True)).to_have_value(
            "Project memory", timeout=30000
        )
        await page.get_by_label("Note", exact=True).fill(
            "Write the decision and its reasoning immediately after each meeting. Review this record before making the next choice."
        )
        await page.get_by_role("button", name="Save changes").click()
        await expect(page.get_by_role("status")).to_have_text(
            "Note saved.", timeout=30000
        )
        await stale.get_by_label("Note", exact=True).fill(
            "An older draft must not replace the current decision record."
        )
        await stale.get_by_role("button", name="Save changes").click()
        await expect(stale.get_by_role("alert")).to_contain_text(
            "changed while you were editing", timeout=30000
        )
        await expect(stale.get_by_label("Note", exact=True)).to_have_value(
            "An older draft must not replace the current decision record."
        )
        await stale.get_by_role("link", name="Reload latest note").click()
        await expect(stale.get_by_label("Note", exact=True)).to_have_value(
            "Write the decision and its reasoning immediately after each meeting. Review this record before making the next choice.",
            timeout=30000,
        )
        await page.goto(ORIGIN)
        await page.get_by_label("What are you looking for?").fill(
            "Remember why we made a choice in a meeting"
        )
        await page.get_by_label("Title contains (optional)").fill("Project")
        await page.get_by_role("button", name="Search by meaning").click()
        await expect(
            page.get_by_role("heading", name="Project memory", exact=True)
        ).to_be_visible(timeout=30000)
        await expect(page.locator(".pill").filter(has_text="Distance")).to_be_visible()
        await page.screenshot(
            path=str(ARTIFACTS / "semantic-search.png"), full_page=True
        )
        foreign = await page.request.post(
            ORIGIN + "/api/notes",
            headers={"Origin": "https://foreign.invalid"},
            data={"title": "Foreign", "body": "Rejected"},
        )
        assert foreign.status == 403
        await page.goto(ORIGIN)
        await expect(
            page.get_by_role("heading", name="Project memory", exact=True)
        ).to_be_visible(timeout=30000)
        await page.screenshot(
            path=str(ARTIFACTS / "semantic-desktop.png"), full_page=True
        )
        mobile = await browser.new_context(
            viewport={"width": 390, "height": 844},
            is_mobile=True,
            device_scale_factor=1,
        )
        phone = await mobile.new_page()
        await phone.goto(ORIGIN)
        await expect(
            phone.get_by_role("heading", name="Find the thought.")
        ).to_be_visible(timeout=30000)
        assert await phone.evaluate(
            "document.documentElement.scrollWidth <= window.innerWidth"
        )
        await phone.screenshot(
            path=str(ARTIFACTS / "semantic-mobile.png"), full_page=True
        )
        assert not errors, errors
        report = {
            "browser_version": browser.version,
            "note_url_path": note_url.removeprefix(ORIGIN),
            "checks": [
                "actual add/save",
                "actual correction durable after reload",
                "two-browser stale form 409 retains input",
                "explicit reload latest",
                "actual model search with literal title filter",
                "foreign-origin 403",
                "desktop/mobile viewport",
                "no page errors",
            ],
        }
        (ARTIFACTS / "browser-result.json").write_text(json.dumps(report, indent=2))
        print(json.dumps(report, indent=2))
        await browser.close()


if __name__ == "__main__":
    asyncio.run(main())
