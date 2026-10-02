"""Real Chromium/LiveView acceptance against a dedicated seeded Cloud fixture.

Install Playwright in a VM, then run with the README runtime variables and the
seeded CASEY/MORGAN passwords. Output contains counts, never WebSocket contents.
"""

import asyncio
import json
import os
from pathlib import Path
import signal
import subprocess
import time
import urllib.request
from playwright.async_api import async_playwright, expect

ORIGIN = os.environ.get("APP_ORIGIN", "http://127.0.0.1:4000")
OUTPUT = Path(os.environ.get("EVIDENCE_DIR", "/tmp/incident-browser-evidence"))
OUTPUT.mkdir(parents=True, exist_ok=True)


def start_server():
    # Do not give the HTTP process owner/admin/seed credentials.
    keys = [
        "PATH",
        "HOME",
        "LANG",
        "PGHOST",
        "PGPORT",
        "PGDATABASE",
        "PGSSLROOTCERT",
        "SECRET_KEY_BASE",
        "APP_ORIGIN",
    ]
    env = {key: os.environ[key] for key in keys if key in os.environ}
    env.update(
        PGUSER="incident_app", PGPASSWORD=os.environ["APP_PASSWORD"], PHX_SERVER="true"
    )
    log = open(OUTPUT / "server.log", "a")
    process = subprocess.Popen(
        ["mix", "phx.server"], env=env, stdout=log, stderr=log, start_new_session=True
    )
    for _ in range(150):
        try:
            with urllib.request.urlopen(ORIGIN + "/sign-in", timeout=2) as response:
                if response.status == 200:
                    return process, log
        except (OSError, TimeoutError):
            time.sleep(0.2)
        if process.poll() is not None:
            raise RuntimeError("Server exited; inspect the private server log")
    raise RuntimeError("Server did not start")


def stop_server(process, log):
    if process.poll() is not None:
        log.close()
        return
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=20)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
    log.close()


async def sign_in(page, email, password):
    await page.goto(ORIGIN + "/sign-in")
    await page.locator('input[name="session[email]"]').fill(email)
    await page.locator('input[name="session[password]"]').fill(password)
    await page.get_by_role("button", name="Sign in", exact=True).click()
    await page.wait_for_url(ORIGIN + "/")
    await page.wait_for_function("window.liveSocket && window.liveSocket.isConnected()")


async def push(page, event, payload):
    await page.evaluate(
        """([event, value]) => {
      window.liveSocket.execJS(document.querySelector('[data-phx-main]'),
        JSON.stringify([['push', {event, value}]]));
    }""",
        [event, payload],
    )


async def main():
    server, log = start_server()
    try:
        async with async_playwright() as playwright:
            browser = await playwright.chromium.launch()
            one = await browser.new_context(viewport={"width": 1360, "height": 1000})
            two = await browser.new_context(viewport={"width": 1360, "height": 1000})
            anonymous = await browser.new_context()
            casey, morgan, signed_out = (
                await one.new_page(),
                await two.new_page(),
                await anonymous.new_page(),
            )
            frames = {"casey": 0, "morgan": 0}
            for page, label in [(casey, "casey"), (morgan, "morgan")]:
                page.on(
                    "websocket",
                    lambda socket, label=label: socket.on(
                        "framereceived",
                        lambda _: frames.__setitem__(label, frames[label] + 1),
                    ),
                )
            await sign_in(
                casey, "casey@example.test", os.environ["SEED_CASEY_PASSWORD"]
            )
            await sign_in(
                morgan, "morgan@example.test", os.environ["SEED_MORGAN_PASSWORD"]
            )
            title = "API recovery " + str(time.time_ns())
            await casey.locator('input[name="incident[title]"]').fill(title)
            await casey.get_by_role("button", name="Open incident").click()
            await casey.wait_for_url("**/incidents/*")
            room = casey.url
            await morgan.goto(room)
            await expect(morgan.get_by_role("heading", name=title)).to_be_visible()
            await expect(morgan.locator(".live-badge")).to_have_text("● Live room")
            response = await anonymous.request.post(
                ORIGIN + "/sign-in",
                form={"email": "casey@example.test", "password": "no-token"},
            )
            assert response.status == 403
            print("PASS HTTP mutation without CSRF token returns native403")
            await signed_out.goto(room)
            await expect(signed_out).to_have_url(ORIGIN + "/sign-in")
            print("PASS signed-out HTTP room read redirects before mount")

            await morgan.locator("textarea").fill("Unsaved responder draft")
            await casey.locator("textarea").fill("Errors are falling after rollback")
            await casey.get_by_role("button", name="Add note").click()
            await expect(casey.locator("textarea")).to_have_value("")
            await expect(morgan.locator("#timeline")).to_contain_text(
                "Errors are falling after rollback"
            )
            await expect(morgan.locator("textarea")).to_have_value(
                "Unsaved responder draft"
            )
            print(
                "PASS committed note broadcasts to second browser; own form clears, foreign draft survives"
            )

            before = await casey.locator("#timeline li").count()
            await push(
                casey,
                "note",
                {
                    "note": {
                        "body": "Forged author",
                        "author_id": "00000000-0000-0000-0000-000000000002",
                    }
                },
            )
            await expect(casey.get_by_role("alert")).to_contain_text("not saved")
            assert await casey.locator("#timeline li").count() == before
            await push(casey, "note", {"note": []})
            await expect(casey.get_by_role("alert")).to_contain_text("not saved")
            await push(casey, "transition", {"status": "resolved", "version": "0"})
            await expect(casey.get_by_role("alert")).to_contain_text("not saved")
            await expect(casey.locator("#incident-status")).to_have_text(
                "Investigating"
            )
            print(
                "PASS forged author, malformed payload and invalid transition leave timeline unchanged"
            )

            await asyncio.gather(
                push(casey, "transition", {"status": "monitoring", "version": "0"}),
                push(morgan, "transition", {"status": "monitoring", "version": "0"}),
            )
            await expect(casey.locator("#incident-status")).to_have_text("Monitoring")
            await expect(morgan.locator("#incident-status")).to_have_text("Monitoring")
            await expect(casey.locator("#timeline")).to_contain_text(
                "Status changed from investigating to monitoring"
            )
            assert await casey.locator("#timeline li").count() == before + 1
            print(
                "PASS two browser expected-version race commits exactly one transition entry"
            )

            await morgan.evaluate("window.liveSocket.disconnect()")
            await casey.locator("textarea").fill("Missed broadcast while offline")
            await casey.get_by_role("button", name="Add note").click()
            await expect(casey.locator("#timeline")).to_contain_text(
                "Missed broadcast while offline"
            )
            assert (
                "Missed broadcast while offline"
                not in await morgan.locator("#timeline").inner_text()
            )
            await morgan.evaluate("window.liveSocket.connect()")
            await expect(morgan.locator("#timeline")).to_contain_text(
                "Missed broadcast while offline"
            )
            print(
                "PASS reconnect rehydrates committed data after deliberately missed broadcast"
            )
            await morgan.screenshot(
                path=str(OUTPUT / "incident-room.png"), full_page=True
            )

            old_pid = server.pid
            stop_server(server, log)
            server, log = start_server()
            assert old_pid != server.pid
            await casey.reload()
            await expect(casey.locator(".live-badge")).to_have_text("● Live room")
            await expect(casey.locator("#timeline")).to_contain_text(
                "Missed broadcast while offline"
            )
            await expect(casey.locator("#incident-status")).to_have_text("Monitoring")
            await casey.locator("textarea").fill(
                "Session still authorized after restart"
            )
            await casey.get_by_role("button", name="Add note").click()
            await expect(casey.locator("#timeline")).to_contain_text(
                "Session still authorized after restart"
            )
            print(
                "PASS real server process restart retains DB timeline, state and authenticated session"
            )

            duplicate_tab = await one.new_page()
            await duplicate_tab.goto(room)
            await expect(duplicate_tab.locator(".live-badge")).to_have_text(
                "● Live room"
            )
            preserved_cookie = await one.cookies()
            await casey.get_by_role("button", name="Sign out", exact=True).click()
            await expect(casey).to_have_url(ORIGIN + "/sign-in")
            await duplicate_tab.evaluate("window.liveSocket.connect()")
            await duplicate_tab.reload()
            await expect(duplicate_tab).to_have_url(ORIGIN + "/sign-in")
            replay = await browser.new_context()
            await replay.add_cookies(preserved_cookie)
            replay_page = await replay.new_page()
            await replay_page.goto(room)
            await expect(replay_page).to_have_url(ORIGIN + "/sign-in")
            print(
                "PASS independent replay of pre-logout cookie is rejected after DB revocation"
            )
            assert frames["casey"] > 0 and frames["morgan"] > 0
            print("WebSocket received frame counts: " + json.dumps(frames))
            await browser.close()
    finally:
        stop_server(server, log)


if __name__ == "__main__":
    asyncio.run(main())
