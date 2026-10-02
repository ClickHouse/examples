import json, os, re, sys
from pathlib import Path
import requests

base = "http://127.0.0.1:8000"
state_file = Path(".deployment/persistence.json")
session = requests.Session()


def token(page):
    return re.search(r'name="_token" value="([^"]+)"', page.text).group(1)


if sys.argv[1] == "before":
    page = session.get(base + "/login", timeout=20)
    response = session.post(
        base + "/login",
        data={
            "_token": token(page),
            "email": "alex@example.test",
            "password": os.environ["DEMO_PASSWORD"],
        },
        allow_redirects=False,
        timeout=20,
    )
    assert response.status_code == 303
    page = session.get(base + "/invoices/create", timeout=20)
    response = session.post(
        base + "/invoices",
        data={
            "_token": token(page),
            "recipient": "Persistent studio",
            "reference": "Persistence: fixed invoice",
            "lines[0][description]": "Exact ten cents",
            "lines[0][quantity]": "3",
            "lines[0][unit_price]": "0.10",
        },
        allow_redirects=False,
        timeout=20,
    )
    assert response.status_code == 303
    url = response.headers["Location"]
    page = session.get(url, timeout=20)
    issued = session.post(
        url + "/issue", data={"_token": token(page)}, allow_redirects=False, timeout=20
    )
    assert issued.status_code == 303
    page = session.get(url, timeout=20)
    number = re.search(r"INV-\d+", page.text).group(0)
    state_file.write_text(
        json.dumps(
            {"cookies": session.cookies.get_dict(), "url": url, "number": number}
        )
    )
    state_file.chmod(0o600)
    print(
        "Before restart: existing database session and issued invoice number/snapshot recorded privately."
    )
else:
    state = json.loads(state_file.read_text())
    for name, value in state["cookies"].items():
        session.cookies.set(name, value, domain="127.0.0.1", path="/")
    page = session.get(state["url"], allow_redirects=False, timeout=20)
    assert page.status_code == 200
    assert state["number"] in page.text and "Persistence: fixed invoice" in page.text
    assert page.text.count("Exact ten cents") == 1 and "$0.30" in page.text
    assert "Alex" in page.text
    state_file.unlink()
    print(
        "After actual worker restart: same database session authenticates; number and exact issued snapshot persist."
    )
