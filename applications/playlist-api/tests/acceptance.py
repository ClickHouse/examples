"""Opt-in actual GraphQL/Cloud controls, not part of basic CI."""

import os, uuid, time, json, unittest
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import httpx, psycopg

BASE = os.getenv("BASE_URL", "http://127.0.0.1:8080")
A = "00000000-0000-4000-8000-000000000001"
B = "00000000-0000-4000-8000-000000000002"
TRACKS = [f"10000000-0000-4000-8000-{n:012d}" for n in range(1, 61)]
FIELDS = "id name revision items {position track {id title artist durationSeconds}}"
CREATE = (
    "mutation($input:CreatePlaylistInput!){createPlaylist(input:$input){"
    + FIELDS
    + "}}"
)
REORDER = (
    "mutation($input:ReorderInput!){reorderPlaylist(input:$input){" + FIELDS + "}}"
)
READ = "query($id:ID!){playlist(id:$id){" + FIELDS + "}}"
LIST = (
    "query($limit:Int!,$cursor:String){playlists(limit:$limit,cursor:$cursor){playlists{"
    + FIELDS
    + "} nextCursor}}"
)


def db(owner=False):
    return psycopg.connect(
        host=os.environ["PGHOST"],
        port=os.getenv("PGPORT", "5432"),
        dbname=os.getenv("PGDATABASE", "postgres"),
        user=os.environ["TEST_OWNER_USER"] if owner else os.environ["PGUSER"],
        password=os.environ["TEST_OWNER_PASSWORD"]
        if owner
        else os.environ["PGPASSWORD"],
        sslmode="verify-full",
        sslrootcert=os.environ["PGSSLROOTCERT"],
        connect_timeout=10,
        options="-c statement_timeout=10000 -c lock_timeout=8000",
    )


def gql(query, variables=None, account="A"):
    with httpx.Client(timeout=35) as client:
        return client.post(
            BASE + "/query",
            json={"query": query, "variables": variables or {}},
            headers={
                "Authorization": "Bearer " + os.environ[f"ACCOUNT_{account}_TOKEN"]
            },
        )


def order(row):
    return [x["track"]["id"] for x in row["items"]]


class Acceptance(unittest.TestCase):
    def success(self, response, key):
        self.assertEqual(response.status_code, 200, response.text)
        data = response.json()
        self.assertNotIn("errors", data, data)
        return data["data"][key]

    def error(self, response, code=None):
        self.assertEqual(response.status_code, 200, response.text)
        data = response.json()
        self.assertTrue(data.get("errors"), data)
        self.assertFalse(data.get("data"))
        if code:
            self.assertEqual(data["errors"][0].get("extensions", {}).get("code"), code)
        return data

    def create(self, tracks=None, account="A", name=None):
        return self.success(
            gql(
                CREATE,
                {
                    "input": {
                        "name": name or "Synthetic " + uuid.uuid4().hex,
                        "trackIds": tracks or TRACKS[:3],
                    }
                },
                account,
            ),
            "createPlaylist",
        )

    def reorder(self, row, tracks=None, revision=None, account="A"):
        return gql(
            REORDER,
            {
                "input": {
                    "id": row["id"],
                    "expectedRevision": row["revision"]
                    if revision is None
                    else revision,
                    "trackIds": tracks or list(reversed(order(row))),
                }
            },
            account,
        )

    def test_01_create_owner_and_nested_scope(self):
        row = self.create()
        self.assertEqual(row["revision"], 1)
        self.assertEqual(order(row), TRACKS[:3])
        self.assertEqual([x["position"] for x in row["items"]], [1, 2, 3])
        self.assertTrue(
            all(x["track"]["artist"] == "Example Ensemble" for x in row["items"])
        )
        self.assertEqual(self.success(gql(READ, {"id": row["id"]}), "playlist"), row)
        self.error(gql(READ, {"id": row["id"]}, "B"), "NOT_FOUND")
        self.error(self.reorder(row, account="B"), "NOT_FOUND")
        other = self.create(account="B")
        listed = self.success(gql(LIST, {"limit": 10}, "B"), "playlists")
        self.assertNotIn(row["id"], [x["id"] for x in listed["playlists"]])
        self.assertIn(other["id"], [x["id"] for x in listed["playlists"]])
        self.assertEqual(
            httpx.post(
                BASE + "/query", json={"query": "{tracks(limit:1){id}}"}
            ).status_code,
            401,
        )
        self.assertEqual(httpx.get(BASE + "/query").status_code, 405)

    def test_02_swap_revision_and_permutation(self):
        row = self.create(TRACKS[:2])
        changed = self.success(self.reorder(row), "reorderPlaylist")
        self.assertEqual(changed["revision"], 2)
        self.assertEqual(order(changed), TRACKS[1::-1])
        self.error(self.reorder(row), "STALE")
        for tracks in [[TRACKS[0], TRACKS[0]], [TRACKS[0]], [TRACKS[0], TRACKS[2]]]:
            self.error(self.reorder(changed, tracks), "INVALID")
        self.assertEqual(
            self.success(gql(READ, {"id": row["id"]}), "playlist"), changed
        )
        for body in [
            {"name": " ", "trackIds": TRACKS[:1]},
            {"name": "x", "trackIds": []},
            {"name": "x", "trackIds": TRACKS[:51]},
            {"name": "x", "trackIds": [str(uuid.uuid4())]},
        ]:
            self.error(gql(CREATE, {"input": body}), "INVALID")

    def test_03_independent_contending_reorders(self):
        row = self.create()
        sequences = [list(reversed(order(row))), order(row)[1:] + order(row)[:1]]
        with db(True) as owner:
            owner.execute(
                "SELECT id FROM playlist_api.playlists WHERE id=%s FOR UPDATE",
                (row["id"],),
            )
            with ThreadPoolExecutor(2) as pool:
                tasks = [pool.submit(self.reorder, row, tracks) for tracks in sequences]
                deadline = time.monotonic() + 5
                blocked = 0
                while time.monotonic() < deadline:
                    owner.execute("SELECT pg_stat_clear_snapshot()")
                    blocked = owner.execute(
                        "SELECT count(*) FROM pg_stat_activity WHERE usename='playlist_app' AND cardinality(pg_blocking_pids(pid))>0"
                    ).fetchone()[0]
                    if blocked >= 2:
                        break
                    time.sleep(0.05)
                self.assertGreaterEqual(blocked, 2)
                owner.commit()
                responses = [task.result() for task in tasks]
        winners = [r for r in responses if not r.json().get("errors")]
        self.assertEqual(len(winners), 1)
        loser = next(r for r in responses if r.json().get("errors"))
        self.error(loser, "STALE")
        winner = self.success(winners[0], "reorderPlaylist")
        self.assertEqual(winner["revision"], 2)
        self.assertIn(order(winner), sequences)

    def test_04_alias_fragment_cost_and_transport_policy(self):
        field = (
            'createPlaylist(input:{name:"forbidden",trackIds:["'
            + TRACKS[0]
            + '"]}){id}'
        )
        for query in [
            "mutation{a:" + field + " b:" + field + "}",
            "mutation{...F} fragment F on Mutation{a:"
            + field
            + " ...G} fragment G on Mutation{b:"
            + field
            + "}",
            "mutation{...F ...F} fragment F on Mutation{" + field + "}",
        ]:
            response = gql(query)
            self.assertEqual(response.status_code, 200, response.text)
            self.assertTrue(response.json().get("errors"))
            self.assertNotIn("cannot commit", response.text)
        expensive = (
            "{"
            + " ".join(
                "a" + str(n) + ":playlists(limit:10){playlists{" + FIELDS + "}}"
                for n in range(5)
            )
            + "}"
        )
        response = gql(expensive)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertTrue(response.json().get("errors"))
        log = Path(os.environ["SERVER_LOG"]).read_text().splitlines()
        self.assertIn("Observed Ent SQL statements=0", log[-1])
        for query in [
            "{playlists(limit:11){nextCursor}}",
            "{tracks(limit:51){id}}",
            "{__schema{types{name}}}",
        ]:
            response = gql(query)
            self.assertEqual(response.status_code, 200, response.text)
        response = gql("{tracks(limit:1){id}}")
        self.success(response, "tracks")
        response = httpx.post(
            BASE + "/query",
            headers={
                "Authorization": "Bearer " + os.environ["ACCOUNT_A_TOKEN"],
                "Content-Type": "application/json",
            },
            content=b" " * 16385,
        )
        self.assertEqual(response.status_code, 413)

    def controlled_failure(self, deferred):
        marker = "failure_" + uuid.uuid4().hex
        with db(True) as owner:
            if deferred:
                owner.execute(
                    """CREATE FUNCTION playlist_api.acceptance_fault() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.name LIKE 'failure_%%' THEN RAISE EXCEPTION 'Controlled deferred fault 23514' USING ERRCODE='23514';END IF;RETURN NEW;END $$"""
                )
                owner.execute(
                    "CREATE CONSTRAINT TRIGGER acceptance_fault AFTER INSERT ON playlist_api.playlists DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION playlist_api.acceptance_fault()"
                )
            else:
                owner.execute(
                    """CREATE FUNCTION playlist_api.acceptance_fault() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.position=2 AND EXISTS(SELECT 1 FROM playlist_api.items WHERE playlist_id=NEW.playlist_id AND position=1) THEN RAISE EXCEPTION 'Controlled child fault 23514' USING ERRCODE='23514';END IF;RETURN NEW;END $$"""
                )
                owner.execute(
                    "CREATE TRIGGER acceptance_fault AFTER INSERT ON playlist_api.items FOR EACH ROW EXECUTE FUNCTION playlist_api.acceptance_fault()"
                )
        try:
            response = gql(CREATE, {"input": {"name": marker, "trackIds": TRACKS[:3]}})
            self.error(response)
            self.assertNotIn("23514", response.text)
            self.assertNotIn("Controlled", response.text)
            self.assertNotIn("cannot commit", response.text)
            with db(True) as owner:
                self.assertEqual(
                    owner.execute(
                        "SELECT count(*) FROM playlist_api.playlists WHERE name=%s",
                        (marker,),
                    ).fetchone()[0],
                    0,
                )
                self.assertEqual(
                    owner.execute(
                        "SELECT count(*) FROM playlist_api.items i JOIN playlist_api.playlists p ON i.playlist_id=p.id WHERE p.name=%s",
                        (marker,),
                    ).fetchone()[0],
                    0,
                )
        finally:
            with db(True) as owner:
                owner.execute(
                    "DROP TRIGGER acceptance_fault ON playlist_api."
                    + ("playlists" if deferred else "items")
                )
                owner.execute("DROP FUNCTION playlist_api.acceptance_fault()")
        self.create(name=marker)

    def test_05_after_parent_and_child_rollback(self):
        self.controlled_failure(False)

    def test_06_deferred_commit_has_no_success_data(self):
        self.controlled_failure(True)

    def test_07_runtime_role_and_position_constraint(self):
        row = self.create()
        for sql in [
            "UPDATE playlist_api.tracks SET title='bad'",
            "DELETE FROM playlist_api.items",
            "CREATE TABLE playlist_api.forbidden(id int)",
            "CREATE TEMP TABLE forbidden(id int)",
        ]:
            with db() as runtime:
                with self.assertRaises(psycopg.errors.InsufficientPrivilege):
                    runtime.execute(sql)
        with db(True) as owner:
            with self.assertRaises(psycopg.errors.UniqueViolation):
                owner.execute(
                    "UPDATE playlist_api.items SET position=1 WHERE playlist_id=%s AND position=2",
                    (row["id"],),
                )
                owner.commit()
        self.assertEqual(self.success(gql(READ, {"id": row["id"]}), "playlist"), row)

    def test_08_scoped_cursor_and_live_keyset(self):
        page = self.success(gql(LIST, {"limit": 2}), "playlists")
        self.assertEqual(len(page["playlists"]), 2)
        self.assertTrue(page["nextCursor"])
        self.error(
            gql(LIST, {"limit": 2, "cursor": page["nextCursor"]}, "B"), "INVALID"
        )
        nextpage = self.success(
            gql(LIST, {"limit": 2, "cursor": page["nextCursor"]}), "playlists"
        )
        self.assertTrue(
            set(x["id"] for x in page["playlists"]).isdisjoint(
                x["id"] for x in nextpage["playlists"]
            )
        )

    def clear_b(self):
        with db(True) as owner:
            owner.execute(
                "DELETE FROM playlist_api.items WHERE playlist_id IN (SELECT id FROM playlist_api.playlists WHERE owner_id=%s)",
                (B,),
            )
            owner.execute("DELETE FROM playlist_api.playlists WHERE owner_id=%s", (B,))

    def test_09_observed_small_and_larger_nested_counts(self):
        self.clear_b()
        small = self.create(TRACKS[:2], "B")
        response = gql(READ, {"id": small["id"]}, "B")
        self.success(response, "playlist")
        self.assertEqual(response.json()["extensions"]["sqlStatements"], 3)
        self.clear_b()
        for _ in range(10):
            self.create(TRACKS[:50], "B")
        response = gql(LIST, {"limit": 10}, "B")
        page = self.success(response, "playlists")
        self.assertEqual(len(page["playlists"]), 10)
        self.assertEqual(sum(len(p["items"]) for p in page["playlists"]), 500)
        self.assertEqual(response.json()["extensions"]["sqlStatements"], 3)
        print(
            "Observed Ent statement counts: 1 playlist/2 items=3; 10 playlists/500 items=3 (excluding transaction control and trigger internals)"
        )

    def test_10_database_playlist_quota(self):
        marker = "quota_" + uuid.uuid4().hex
        with db(True) as owner:
            count = owner.execute(
                "SELECT count(*) FROM playlist_api.playlists WHERE owner_id=%s", (B,)
            ).fetchone()[0]
            remaining = 100 - count
            owner.execute(
                """WITH inserted AS (INSERT INTO playlist_api.playlists(id,owner_id,name) SELECT gen_random_uuid(),%s,%s FROM generate_series(1,%s) RETURNING id) INSERT INTO playlist_api.items(id,playlist_id,track_id,position) SELECT gen_random_uuid(),id,%s,1 FROM inserted""",
                (B, marker, remaining, TRACKS[0]),
            )
        try:
            self.error(
                gql(
                    CREATE,
                    {"input": {"name": "over quota", "trackIds": TRACKS[:1]}},
                    "B",
                )
            )
            with db(True) as owner:
                self.assertEqual(
                    owner.execute(
                        "SELECT count(*) FROM playlist_api.playlists WHERE owner_id=%s",
                        (B,),
                    ).fetchone()[0],
                    100,
                )
        finally:
            with db(True) as owner:
                owner.execute(
                    "DELETE FROM playlist_api.items WHERE playlist_id IN (SELECT id FROM playlist_api.playlists WHERE name=%s)",
                    (marker,),
                )
                owner.execute(
                    "DELETE FROM playlist_api.playlists WHERE name=%s", (marker,)
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)
