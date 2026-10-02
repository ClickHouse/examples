"""Browser smoke test against the seeded local HTTP app. Run inside Linux."""
import os
from pathlib import Path
from playwright.sync_api import sync_playwright, expect

with sync_playwright() as p:
    browser = p.chromium.launch()
    page = browser.new_page(viewport={"width": 1440, "height": 1100})
    errors = []
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.goto("http://127.0.0.1:8000/accounts/login/")
    page.get_by_label("Username").fill("alex")
    page.get_by_label("Password").fill(os.environ["DEMO_PASSWORD"])
    page.get_by_role("button", name="Sign in").click()
    expect(page.get_by_role("heading", name="Good tools, ready to go.")).to_be_visible()
    page.wait_for_function("typeof htmx !== 'undefined'")
    camera = page.locator("article").filter(has=page.get_by_role("heading", name="Mirrorless camera"))
    camera.get_by_role("button", name="Borrow item").click()
    expect(page.get_by_role("status")).to_contain_text("Borrowed Mirrorless camera")
    expect(page.locator(".loan").filter(has_text="Mirrorless camera")).to_be_visible()
    page.locator(".loan").filter(has_text="Mirrorless camera").get_by_role("button", name="Return item").click()
    expect(page.get_by_role("status")).to_contain_text("Returned Mirrorless camera")
    expect(camera.get_by_role("button", name="Borrow item")).to_be_visible()
    Path(".deployment").mkdir(exist_ok=True)
    page.screenshot(path=".deployment/board-desktop.png", full_page=True)
    page.set_viewport_size({"width": 390, "height": 844})
    page.screenshot(path=".deployment/board-mobile.png", full_page=True)
    assert page.evaluate("document.documentElement.scrollWidth <= window.innerWidth"), "mobile overflow"
    assert not errors, errors
    browser.close()
    print("Browser login, htmx borrow/return, desktop/mobile checks passed.")
