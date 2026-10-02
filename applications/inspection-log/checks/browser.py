#!/usr/bin/env python3
"""Browser flow on the real loopback application; Playwright lives outside the app bundle."""
import csv, io, os
from pathlib import Path
from playwright.sync_api import sync_playwright

out=Path(os.environ['EVIDENCE_DIR']);out.mkdir(parents=True,exist_ok=True)
note='  =1+1,"quoted"\n<script>window.__inspectionInjected=true</script>'
with sync_playwright() as p:
 browser=p.chromium.launch(headless=True)
 context=browser.new_context(viewport={'width':1100,'height':900},timezone_id='Pacific/Honolulu',accept_downloads=True)
 page=context.new_page();page.goto('http://127.0.0.1:9292/')
 page.locator('select[name=asset_id]').select_option('1')
 page.locator('input[name=inspected_on]').fill('2026-01-01')
 page.locator('select[name=outcome]').select_option('watch')
 page.locator('select[name=cable]').select_option('issue')
 page.locator('textarea[name=note]').fill(note)
 request_id=page.locator('input[name=request_id]').input_value()
 with page.expect_navigation():page.get_by_role('button',name='Save inspection',exact=True).click()
 assert '/inspections/' in page.url
 assert page.locator('h1').inner_text()=='Synthetic bench <A>'
 assert '2026-01-01' in page.locator('.intro').inner_text()
 assert page.locator('p.note').inner_text()==note
 assert page.evaluate('window.__inspectionInjected') is None
 assert request_id in page.locator('main').inner_text()
 page.screenshot(path=str(out/'browser-record.png'),full_page=True)
 page.get_by_role('link',name='View asset history').click()
 assert page.locator('tbody tr').count()==1
 page.screenshot(path=str(out/'browser-history.png'),full_page=True)
 with page.expect_download() as waiting:page.get_by_role('button',name='Download CSV',exact=True).click()
 download=waiting.value;data=Path(download.path()).read_text()
 rows=list(csv.DictReader(io.StringIO(data)))
 assert len(rows)==1 and rows[0]['inspected_on']=='2026-01-01'
 assert rows[0]['note']=="'"+note and rows[0]['asset']=='Synthetic bench <A>'
 assert rows[0]['cable']=='issue'
 (out/'browser-export.csv').write_text(data)
 print('Real browser: protected form→saved inspection→history→parsed CSV passed')
 print('Server/browser Pacific/Honolulu calendar day2026-01-01 stayed exact; escaped asset/note did not execute; quote/newline/formula prefix checked')
 context.close();browser.close()
