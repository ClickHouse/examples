"""Native live fixture controls. Load separate setup/test credentials, never runtime.

Uses only Python's standard library; SQL controls run through native psql.
"""
import concurrent.futures
import html.parser
import http.cookiejar
import json
import os
import pathlib
import ssl
import subprocess
import threading
import urllib.error
import urllib.parse
import urllib.request

BASE = "http://127.0.0.1:8080"
CUSTOMERS = [f"00000000-0000-0000-0000-{n:012d}" for n in (1, 2, 3)]


def sql(statement, role=None, expect=None):
    environment = dict(os.environ)
    if role:
        environment.update(PGUSER=role, PGPASSWORD=os.environ[
            {"notebook_app": "NOTEBOOK_APP_PASSWORD",
             "notebook_report": "NOTEBOOK_REPORT_PASSWORD"}[role]])
    result = subprocess.run(["psql", "-X", "-At", "-v", "ON_ERROR_STOP=1",
                             "--set", "VERBOSITY=verbose"],
                            input=statement, text=True, capture_output=True,
                            env=environment, timeout=20)
    if expect:
        assert result.returncode != 0 and expect in result.stderr, result.stderr
        print("SQL negative control", role, expect)
    else:
        assert result.returncode == 0, result.stderr
    return result.stdout.strip()


def direct(query, user="default", password=None):
    endpoint = f"https://{os.environ['CH_HOST']}:{os.environ['CH_PORT']}/"
    endpoint += "?max_execution_time=10&max_rows_to_read=20000&max_result_rows=1000"
    request = urllib.request.Request(endpoint, data=query.encode(), headers={
        "X-ClickHouse-User": user,
        "X-ClickHouse-Key": password or os.environ["CH_ADMIN_PASSWORD"]})
    with urllib.request.urlopen(request, context=ssl.create_default_context(), timeout=15) as response:
        return response.read().decode()


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


class Document(html.parser.HTMLParser):
    def __init__(self, source):
        super().__init__()
        self.inputs, self.cells = {}, []
        self.in_cell = False
        self.cell = ""
        self.feed(source)

    def handle_starttag(self, tag, attributes):
        attributes = dict(attributes)
        if tag == "input" and "name" in attributes:
            self.inputs[attributes["name"]] = attributes.get("value", "")
        if tag == "td":
            self.in_cell, self.cell = True, ""

    def handle_data(self, value):
        if self.in_cell:
            self.cell += value

    def handle_endtag(self, tag):
        if tag == "td":
            self.cells.append(self.cell)
            self.in_cell = False


class Session:
    def __init__(self):
        self.client = urllib.request.build_opener(
            NoRedirect(), urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

    def request(self, path, fields=None, raw=None):
        data = urllib.parse.urlencode(fields).encode() if fields is not None else raw
        request = urllib.request.Request(BASE + path, data=data)
        if data is not None:
            request.add_header("Content-Type", "application/x-www-form-urlencoded")
        try:
            response = self.client.open(request, timeout=20)
        except urllib.error.HTTPError as error:
            response = error
        return response.status, response.read().decode()

    def form(self, customer):
        status, source = self.request("/customers/" + customer)
        assert status == 200
        values = Document(source).inputs
        return {key: values[key] for key in ("revision", "__anti-forgery-token")}

    def save(self, customer, form, note, health="watch"):
        return self.request("/customers/" + customer,
                            {**form, "note": note, "health": health})


def snapshot(customer):
    return json.loads(sql(f"SELECT json_build_object('revision',revision,'note',note,"
                          f"'edits',(SELECT count(*) FROM notebook.customer_edits WHERE customer_id='{customer}')) "
                          f"FROM notebook.customers WHERE id='{customer}';"))


def main():
    customer = CUSTOMERS[0]
    first, second = Session(), Session()
    before = snapshot(customer)
    forms = [first.form(customer), second.form(customer)]
    assert forms[0]["revision"] == forms[1]["revision"] == str(before["revision"])
    barrier = threading.Barrier(2)
    notes = ["Editor A <script>retained</script>", "Editor B <script>retained</script>"]

    def save(index):
        barrier.wait()
        return [first, second][index].save(customer, forms[index], notes[index])

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        outcomes = list(executor.map(save, (0, 1)))
    assert sorted(status for status, _ in outcomes) == [303, 409], outcomes
    loser = next(i for i, outcome in enumerate(outcomes) if outcome[0] == 409)
    conflict = outcomes[loser][1]
    assert Document(conflict).inputs["revision"] == forms[loser]["revision"]
    assert notes[loser].replace("<", "&lt;").replace(">", "&gt;") in conflict
    assert "<script>" not in conflict
    after = snapshot(customer)
    assert after["revision"] == before["revision"] + 1
    assert after["edits"] == before["edits"] + 1
    print("Two independent HTTP editors:303/409; one revision and edit record; stale submitted note/revision escaped and retained.")

    form = first.form(customer)
    assert first.request("/customers/" + customer, {"note": "forged", "health": "risk", "revision": form["revision"]})[0] == 403
    for raw in [b"note=%ED%A0%80", b"note=%ED%B0%80", b"note=%FF"]:
        assert first.request("/customers/" + customer, raw=raw)[0] == 400
    assert first.request("/customers/" + customer, raw=b"note=" + b"a" * 4097)[0] == 413
    for fields in [{**form, "note": "\0 bad", "health": "healthy"},
                   {**form, "note": "valid", "health": "unknown"},
                   {**form, "note": "valid", "health": "healthy", "revision": "9" * 100},
                   {**form, "note": "valid", "health": "healthy", "actor": "forged"}]:
        assert first.request("/customers/" + customer, fields)[0] == 400
    print("Real HTTP CSRF403, malformed/lone-surrogate UTF-8/control/enum/decimal/unknown-field400, body413.")

    before = snapshot(customer)
    sql("SET ROLE notebook_owner; CREATE FUNCTION notebook.fail_append() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'forced append failure'; END $$; CREATE TRIGGER fail_append BEFORE INSERT ON notebook.customer_edits FOR EACH ROW EXECUTE FUNCTION notebook.fail_append();")
    try:
        assert first.save(customer, first.form(customer), "must roll back")[0] == 503
        assert snapshot(customer) == before
    finally:
        sql("SET ROLE notebook_owner; DROP TRIGGER fail_append ON notebook.customer_edits; DROP FUNCTION notebook.fail_append();")
    assert first.save(customer, first.form(customer), "Rollback control recovered")[0] == 303
    print("Forced append failure after profile UPDATE:503, unchanged revision/note/history; recovery303.")

    for customer in CUSTOMERS:
        status, source = first.request(f"/customers/{customer}/activity?from=2026-09-28&to=2026-09-30")
        assert status == 200, status
        cells = Document(source).cells
        actual = dict(zip(cells[::2], map(int, cells[1::2])))
        rows = [json.loads(line) for line in direct(
            f"SELECT toString(activity_day) AS day,count() AS events FROM notebook_analytics.activity "
            f"WHERE customer_id='{customer}' AND activity_day BETWEEN '2026-09-28' AND '2026-09-30' "
            "GROUP BY activity_day ORDER BY activity_day LIMIT31 FORMAT JSONEachRow".replace("LIMIT31", "LIMIT 31")).splitlines()]
        expected = {day: 0 for day in ("2026-09-28", "2026-09-29", "2026-09-30")}
        expected.update({row["day"]: int(row["events"]) for row in rows})
        assert actual == expected, (actual, expected)
        print("Exact app/direct equality including empty days:", customer, actual)
    for date in ["2000-01-01", "2100-12-31"]:
        assert first.request(f"/customers/{CUSTOMERS[0]}/activity?from={date}&to={date}")[0] == 200
    for dates in ["from=1999-12-31&to=2000-01-01", "from=2100-12-31&to=2101-01-01", "from=2026-09-01&to=2026-10-02"]:
        assert first.request(f"/customers/{CUSTOMERS[0]}/activity?{dates}")[0] == 400
    print("Supported date edges2000/2100 accepted; just-outside and32-day ranges400.")

    direct("REVOKE SELECT ON notebook_analytics.activity FROM notebook_report")
    try:
        for _ in range(2):
            status, source = first.request(f"/customers/{CUSTOMERS[0]}/activity?from=2026-09-28&to=2026-09-30")
            assert status == 503 and "Activity is temporarily unavailable" in source
        assert first.save(CUSTOMERS[0], first.form(CUSTOMERS[0]), "Operational edit during report permission loss")[0] == 303
    finally:
        direct("GRANT SELECT ON notebook_analytics.activity TO notebook_report")
    assert first.request(f"/customers/{CUSTOMERS[0]}/activity?from=2026-09-28&to=2026-09-30")[0] == 200
    print("Same running app:two report failures503, operational save303, restored report200.")

    for statement, role in [("CREATE TABLE notebook.forbidden(id int)", "notebook_app"),
                            ("DELETE FROM notebook.customer_edits", "notebook_app"),
                            ("UPDATE notebook.customers SET name='forged'", "notebook_app"),
                            ("SELECT notebook_fdw.clickhouse_raw_query('SELECT1','host=localhost')", "notebook_report")]:
        sql(statement, role, "42501")
    print("Mapping options visible to mapped reporting role:", sql(
        "SELECT umoptions IS NOT NULL FROM pg_user_mappings WHERE srvname='notebook_activity' AND usename=current_user;", "notebook_report"))
    try:
        direct("INSERT INTO notebook_analytics.activity VALUES ('00000000-0000-0000-0000-000000000001','2026-09-28',99)",
               "notebook_report", os.environ["CH_REPORT_PASSWORD"])
        raise AssertionError("Reporting user inserted")
    except urllib.error.HTTPError as error:
        assert error.code in (400, 403, 500) and b"ACCESS_DENIED" in error.read()
    print("Remote reporting INSERT denied; all live controls passed.")


if __name__ == "__main__":
    main()
