#!/usr/bin/env python3
"""Minimal Nostr helpers for test/e2e.sh: make a key, print its pubkey, and
redeem an invite as that key (POST /api/invites/claim, NIP-98 signed).

buzz-cli has no invite-claim command; the desktop app does this on the
invite landing page, so the e2e does it here.

Usage (run with `uv run --with coincurve --with requests`):
  nip98.py genkey                   -> hex secret on stdout
  nip98.py pubkey  (key in $KEY)    -> hex pubkey
  nip98.py claim <origin> <code>    (key in $KEY) -> claim response JSON
"""
import base64
import hashlib
import json
import os
import sys
import time

import coincurve
import requests


def pub(sk: bytes) -> str:
    return coincurve.PrivateKey(sk).public_key_xonly.format().hex()


def sign(sk: bytes, kind: int, tags: list, content: str = "") -> dict:
    ev = {"pubkey": pub(sk), "created_at": int(time.time()), "kind": kind, "tags": tags, "content": content}
    ser = json.dumps([0, ev["pubkey"], ev["created_at"], kind, tags, content], separators=(",", ":"), ensure_ascii=False)
    ev["id"] = hashlib.sha256(ser.encode()).hexdigest()
    ev["sig"] = coincurve.PrivateKey(sk).sign_schnorr(bytes.fromhex(ev["id"])).hex()
    return ev


def post(sk: bytes, origin: str, path: str, body: dict) -> requests.Response:
    raw = json.dumps(body).encode()
    url = origin.rstrip("/") + path
    auth = sign(sk, 27235, [["u", url], ["method", "POST"], ["payload", hashlib.sha256(raw).hexdigest()]])
    hdr = {"Authorization": "Nostr " + base64.b64encode(json.dumps(auth).encode()).decode(),
           "Content-Type": "application/json"}
    return requests.post(url, data=raw, headers=hdr, timeout=20)


def main() -> int:
    cmd = sys.argv[1]
    if cmd == "genkey":
        print(os.urandom(32).hex())
        return 0
    sk = bytes.fromhex(os.environ["KEY"])
    if cmd == "pubkey":
        print(pub(sk))
        return 0
    if cmd == "claim":
        origin, code = sys.argv[2], sys.argv[3]
        body = {"code": code}
        policy = requests.get(origin.rstrip("/") + "/api/join-policy", timeout=20)
        if policy.ok and (policy.json() or {}).get("version"):
            p = policy.json()
            r = post(sk, origin, "/api/invites/accept-policy", {"code": code, "policy_version": p["version"]})
            if r.ok:
                body["policy_receipt"] = r.json()["receipt"]
        r = post(sk, origin, "/api/invites/claim", body)
        print(r.status_code, r.text[:300])
        return 0 if r.ok else 1
    return 2


if __name__ == "__main__":
    sys.exit(main())
