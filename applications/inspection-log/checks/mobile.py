#!/usr/bin/env python3
"""Responsive width check after the Cloud acceptance fixture reaches its cap."""
import os
from pathlib import Path
from playwright.sync_api import sync_playwright

out = Path(os.environ['EVIDENCE_DIR'])
with sync_playwright() as playwright:
    browser = playwright.chromium.launch(headless=True)
    page = browser.new_page(viewport={'width':375, 'height':812}, timezone_id='Pacific/Honolulu')
    page.goto('http://127.0.0.1:9292/inspections/1')
    assert page.locator('p.note').inner_text().startswith('  =1+1,')
    assert 'Retained request ID:' in page.locator('.hint').inner_text()
    assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth')
    page.screenshot(path=str(out/'browser-mobile-record.png'), full_page=True)
    page.goto('http://127.0.0.1:9292/')
    note = 'Long unbroken note ' + 'x'*580
    page.locator('textarea[name=note]').fill(note)
    request_id = page.locator('input[name=request_id]').input_value()
    with page.expect_response(lambda response: response.url.endswith('/inspections')) as waiting:
        page.get_by_role('button', name='Save inspection', exact=True).click()
    assert waiting.value.status == 409
    assert page.locator('textarea[name=note]').input_value() == note
    assert page.locator('input[name=request_id]').input_value() == request_id
    assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth')
    page.screenshot(path=str(out/'browser-mobile-preserved-form.png'), full_page=True)
    print('Real375px browser: saved long note/request UUID and599-character retained cap-error form fit viewport; no horizontal overflow')
    browser.close()
