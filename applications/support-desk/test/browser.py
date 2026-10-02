import os
from pathlib import Path
from playwright.sync_api import sync_playwright, expect

PASSWORD = os.environ["DEMO_PASSWORD"]
expect.set_options(timeout=20000)
with sync_playwright() as p:
    browser = p.chromium.launch()
    contexts = [browser.new_context(viewport={"width": 1440, "height": 1100}) for _ in range(2)]
    customer, staff = [context.new_page() for context in contexts]
    errors = []
    for page, email in [(customer, "alex@example.test"), (staff, "morgan@example.test")]:
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.goto("http://127.0.0.1:3000/session/new")
        page.get_by_label("Email").fill(email)
        page.get_by_label("Password").fill(PASSWORD)
        page.get_by_role("button", name="Sign in").click()
        expect(page.get_by_role("heading", name="Your tickets" if page == customer else "All tickets")).to_be_visible()
        page.wait_for_function("typeof Turbo !== 'undefined'")
        expect(page.locator("body")).to_have_css("background-color", "rgb(246, 245, 242)")
    customer.get_by_role("link", name="New ticket").click()
    customer.get_by_label("Subject").fill("Browser: help with a connection")
    customer.get_by_label("Message", exact=True).fill("I need help setting up a connection.")
    customer.get_by_role("button", name="Create ticket").click()
    expect(customer.get_by_role("heading", name="Browser: help with a connection")).to_be_visible()
    ticket_url = customer.url
    staff.goto(ticket_url)
    staff.get_by_role("button", name="Claim ticket").click()
    expect(staff.get_by_text("You're the owner of this conversation.")).to_be_visible()
    staff.locator("form.reply-form").evaluate("form => form.noValidate = true")
    staff.get_by_label("Your reply").fill("   ")
    staff.get_by_role("button", name="Add reply").click()
    expect(staff.get_by_role("alert")).to_contain_text("Body can't be blank")
    staff.get_by_label("Your reply").fill("Please use the direct hostname and downloaded CA.")
    staff.get_by_role("button", name="Add reply").click()
    expect(staff.get_by_text("Please use the direct hostname and downloaded CA.")).to_be_visible()
    staff.get_by_role("button", name="Close ticket").click()
    expect(staff.get_by_text("This ticket is closed. Staff must reopen it before anyone can reply.")).to_be_visible()
    customer.reload()
    expect(customer.get_by_text("This ticket is closed. Staff must reopen it before anyone can reply.")).to_be_visible()
    staff.get_by_role("button", name="Reopen ticket").click()
    expect(staff.get_by_role("button", name="Close ticket")).to_be_visible()
    customer.reload()
    expect(customer.get_by_label("Your reply")).to_be_visible()
    customer.get_by_label("Your reply").fill("That worked, thank you.")
    customer.get_by_role("button", name="Add reply").click()
    expect(customer.get_by_text("That worked, thank you.")).to_be_visible()
    Path(".deployment").mkdir(exist_ok=True)
    staff.screenshot(path=".deployment/staff-desktop.png", full_page=True)
    customer.set_viewport_size({"width": 390, "height": 844})
    customer.screenshot(path=".deployment/customer-mobile.png", full_page=True)
    assert customer.evaluate("document.documentElement.scrollWidth <= window.innerWidth"), "mobile overflow"
    assert not errors, errors
    print("Browser customer/staff login, ticket create, Turbo claim/reply/status, 422 rendering and responsive layout passed.")
    browser.close()
