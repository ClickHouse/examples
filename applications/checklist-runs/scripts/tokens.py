#!/usr/bin/env python3
"""Offline fixture issuer. There is no HTTP signing endpoint or login provider."""

import argparse
import base64
import hashlib
import hmac
import json
import os
import time

ROLES = ("checklist_north", "checklist_south")
AUDIENCE = "checklist-runs"


def b64url(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).decode("ascii").rstrip("=")


def issue(secret: str, role: str, lifetime: int = 900, now: int | None = None) -> str:
    if len(secret.encode("utf-8")) < 64:
        raise ValueError("Use a generated secret of at least 64 bytes.")
    if role not in ROLES:
        raise ValueError("Unknown fixture operator role.")
    if type(lifetime) is not int or not 1 <= lifetime <= 900:
        raise ValueError("Token lifetime must be between 1 and 900 seconds.")
    issued = int(time.time()) if now is None else now
    header = {"alg": "HS256", "typ": "JWT"}
    payload = {"role": role, "aud": AUDIENCE, "iat": issued, "exp": issued + lifetime}
    segments = [
        b64url(json.dumps(v, separators=(",", ":")).encode()) for v in (header, payload)
    ]
    signed = ".".join(segments)
    signature = hmac.new(
        secret.encode(), signed.encode("ascii"), hashlib.sha256
    ).digest()
    return signed + "." + b64url(signature)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("role", choices=ROLES)
    parser.add_argument("--seconds", type=int, default=900)
    args = parser.parse_args()
    secret = os.environ.get("PGRST_JWT_SECRET", "")
    try:
        print(issue(secret, args.role, args.seconds))
    except ValueError as exc:
        parser.error(str(exc))


if __name__ == "__main__":
    main()
