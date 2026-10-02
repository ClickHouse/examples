import os
from pathlib import Path
from playwright.sync_api import sync_playwright, expect

expect.set_options(timeout=20000)
BASE = "http://127.0.0.1:8000"
with sync_playwright() as p:
    browser = p.chromium.launch()
    contexts = [
        browser.new_context(viewport={"width": 1440, "height": 1100}) for _ in range(2)
    ]
    alex, sam = [context.new_page() for context in contexts]
    errors = []
    for page, email in [(alex, "alex@example.test"), (sam, "sam@example.test")]:
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.goto(BASE + "/login")
        page.get_by_label("Email").fill(email)
        page.get_by_label("Password").fill(os.environ["DEMO_PASSWORD"])
        page.get_by_role("button", name="Sign in").click()
        expect(page.get_by_role("heading", name="Your invoices")).to_be_visible()
        expect(page.locator("body")).to_have_css(
            "background-color", "rgb(245, 245, 241)"
        )
    alex.get_by_role("link", name="New invoice").click()
    alex.get_by_label("Recipient").fill("North Coast Studio")
    alex.get_by_label("Reference").fill("Browser: precise design work")
    alex.get_by_label("Description").fill("Design hours")
    alex.get_by_label("Quantity").fill("3")
    alex.get_by_label("Unit price (USD)").fill("0.001")
    alex.get_by_role("button", name="Save draft").click()
    expect(alex.get_by_role("alert")).to_contain_text("at most two decimal places")
    alex.get_by_label("Unit price (USD)").fill("0.10")
    alex.get_by_role("button", name="Add line").click()
    expect(alex.locator("[data-line]")).to_have_count(2)
    alex.get_by_label("Description").nth(1).fill("Hosting")
    alex.get_by_label("Quantity").nth(1).fill("2")
    alex.get_by_label("Unit price (USD)").nth(1).fill("12.30")
    alex.get_by_role("button", name="Save draft").click()
    expect(
        alex.get_by_role("heading", name="Browser: precise design work")
    ).to_be_visible()
    expect(alex.get_by_text("$24.90", exact=True)).to_be_visible()
    invoice_url = alex.url
    denied = sam.goto(invoice_url)
    assert denied.status == 404
    # Real session cookie + omitted form token exercises native419 protection.
    csrf = contexts[0].request.post(invoice_url + "/issue", data={})
    assert csrf.status == 419, csrf.status
    alex.get_by_role("link", name="Edit draft").click()
    alex.get_by_label("Unit price (USD)").nth(0).fill("0.11")
    alex.get_by_role("button", name="Save draft").click()
    expect(alex.get_by_text("$24.93", exact=True)).to_be_visible()
    alex.get_by_role("button", name="Issue invoice").click()
    expect(alex.get_by_role("heading", name="Issued snapshot")).to_be_visible()
    number = alex.locator(".eyebrow").inner_text()
    assert number.startswith("INV-")
    token = alex.locator('input[name="_token"]').first.get_attribute("value")
    retry = contexts[0].request.post(
        invoice_url + "/issue", form={"_token": token}, max_redirects=0
    )
    assert retry.status == 303, retry.status
    alex.reload()
    expect(alex.locator(".eyebrow")).to_have_text(number)
    alex.get_by_role("button", name="Mark settled").click()
    expect(alex.locator(".badge")).to_have_text("Settled")
    expect(alex.get_by_text("$24.93", exact=True)).to_be_visible()
    alex.screenshot(path=".deployment/invoice-desktop.png", full_page=True)
    alex.set_viewport_size({"width": 390, "height": 844})
    alex.screenshot(path=".deployment/invoice-mobile.png", full_page=True)
    assert alex.evaluate(
        "document.documentElement.scrollWidth <= innerWidth"
    ), "mobile overflow"
    assert not errors, errors
    print(
        "Browser login, invalid-decimal validation, dynamic lines, exact edit total, issue/retry, settlement, cross-user404, CSRF419, stylesheet and responsive layout passed."
    )
    browser.close()
