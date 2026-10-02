import os
import pathlib
from playwright.sync_api import sync_playwright, expect

URL = "http://127.0.0.1:8080/customers/00000000-0000-0000-0000-000000000001"

with sync_playwright() as playwright:
    browser = playwright.chromium.launch(headless=True)
    context = browser.new_context(viewport={"width": 1000, "height": 1000})
    first, second = context.new_page(), context.new_page()
    first.goto(URL)
    second.goto(URL)
    seen = second.locator('input[name="revision"]').input_value()
    assert first.locator('input[name="revision"]').input_value() == seen
    first.locator("#note").fill("Browser first editor saved")
    with first.expect_response(lambda response: response.request.method == "POST") as response:
        first.get_by_role("button", name="Save note", exact=True).click()
    assert response.value.status == 303
    first.wait_for_url(URL)
    expect(first.locator("#note")).to_have_value("Browser first editor saved")

    second.locator("#note").fill("Browser retained note <script>escaped</script>")
    second.locator("#health").select_option("risk")
    with second.expect_response(lambda response: response.request.method == "POST") as response:
        second.get_by_role("button", name="Save note", exact=True).click()
    assert response.value.status == 409
    expect(second.get_by_role("alert")).to_contain_text("This profile changed")
    expect(second.locator("#note")).to_have_value("Browser retained note <script>escaped</script>")
    assert second.locator('input[name="revision"]').input_value() == seen
    assert second.locator("script").count() == 0
    evidence = pathlib.Path(os.environ["EVIDENCE_DIR"])
    evidence.mkdir(parents=True, exist_ok=True)
    second.screenshot(path=str(evidence / "stale-form.png"), full_page=True)
    print("Actual Chromium two-editor workflow303/409; visible retained note/health/original revision; output escaped.")

    with first.expect_response(lambda response: response.request.method == "POST") as response:
        first.evaluate("""() => {
          document.querySelector('input[name="__anti-forgery-token"]').remove();
          document.querySelector('form[method="post"]').requestSubmit();
        }""")
    assert response.value.status == 403
    expect(first.get_by_text("Session check failed. Reload the form before saving.", exact=True)).to_be_visible()
    first.wait_for_load_state("load")
    print("Actual browser request without native Ring CSRF token rejected403.")

    first.goto(URL)
    assert first.locator('input[name="from"]').get_attribute("min") == "2000-01-01"
    assert first.locator('input[name="to"]').get_attribute("max") == "2100-12-31"
    first.get_by_role("button", name="View activity (up to 31 days)", exact=True).click()
    expect(first.get_by_role("heading", name="Synthetic daily activity")).to_be_visible()
    assert first.locator("tbody tr").count() == 3
    expect(first.locator("tbody tr").nth(1)).to_have_text("2026-09-290")
    first.screenshot(path=str(evidence / "activity.png"), full_page=True)
    print("Actual browser activity panel:three UTC dates, exact empty day0, date picker bounds2000..2100.")
    browser.close()
