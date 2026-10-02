"""Focused actual HTTP regression for JSON surrogate replacement."""

import json
import os
import unittest
import uuid
import httpx
from acceptance import CREATE, TRACKS, BASE, db


class UnicodeRegression(unittest.TestCase):
    def test_reject_surrogate_replacements_allow_valid_pair(self):
        marker = "Unicode regression " + uuid.uuid4().hex
        for suffix in ["\ud800", "\udc00", "\ufffd"]:
            body = {
                "query": CREATE,
                "variables": {
                    "input": {"name": marker + suffix, "trackIds": TRACKS[:1]}
                },
            }
            response = httpx.post(
                BASE + "/query",
                content=json.dumps(body, ensure_ascii=True).encode("ascii"),
                headers={
                    "Content-Type": "application/json",
                    "Authorization": "Bearer " + os.environ["ACCOUNT_A_TOKEN"],
                },
                timeout=35,
            )
            self.assertEqual(response.status_code, 200, response.text)
            result = response.json()
            self.assertFalse(result.get("data"))
            self.assertEqual(result["errors"][0]["extensions"]["code"], "INVALID")
            self.assertEqual(result["extensions"]["sqlStatements"], 0)
        with db(True) as owner:
            self.assertEqual(
                owner.execute(
                    "SELECT count(*) FROM playlist_api.playlists WHERE name=%s",
                    (marker + "\ufffd",),
                ).fetchone()[0],
                0,
            )
        paired = marker + "\ud83d\ude80"
        body = {
            "query": CREATE,
            "variables": {"input": {"name": paired, "trackIds": TRACKS[:1]}},
        }
        response = httpx.post(
            BASE + "/query",
            content=json.dumps(body, ensure_ascii=True).encode("ascii"),
            headers={
                "Content-Type": "application/json",
                "Authorization": "Bearer " + os.environ["ACCOUNT_A_TOKEN"],
            },
            timeout=35,
        )
        self.assertEqual(response.status_code, 200, response.text)
        result = response.json()
        self.assertNotIn("errors", result)
        self.assertEqual(
            result["data"]["createPlaylist"]["name"], marker + "\U0001f680"
        )
        print(
            "Escaped lone high/low surrogates and literal U+FFFD rejected with HTTP200 INVALID and zero Ent statements; valid paired non-BMP name persists unchanged"
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
