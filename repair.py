#!/usr/bin/env python3
"""Puts back what the published Buzz template lost on 2026-10-19.

The live config had drifted from railway.template.json: the Pairing sidecar was
renamed to its image ref and lost its domain, so ${{Pairing.RAILWAY_PUBLIC_DOMAIN}}
resolved empty and every fresh relay crash-looped on BUZZ_PAIRING_RELAY_URL; MinIO
lost its volume, so uploads vanished on redeploy; the relay lost its healthcheck.

Usage: repair.py <published-config.json> [--dry-run]
"""

import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path("~/.claude/skills/create-template-for-railway/scripts").expanduser()))
import rw  # noqa: E402

TEMPLATE_ID = "f1dbede4-cb17-46db-af86-1447ed53b626"
CODE = "buzz"
WORKSPACE = "fc4796db-2c6c-4354-a564-d4a1d900af53"  # Auromations
NAME = "Buzz - Block"
ICON = "https://hmseeb.github.io/buzz-railway/buzz-icon.png"
MINIO_ICON = "https://hmseeb.github.io/buzz-railway/minio-icon.png"
RESTART = {"restartPolicyType": "ON_FAILURE", "restartPolicyMaxRetries": 10}


def by_role(config):
    roles = {}
    for sid, svc in config["services"].items():
        start = (svc.get("deploy") or {}).get("startCommand") or ""
        image = (svc.get("source") or {}).get("image", "")
        if start.startswith("buzz-pair-relay"):
            roles["pairing"] = sid
        elif image.startswith("ghcr.io/hmseeb/buzz-railway:"):
            roles["buzz"] = sid
        elif image.startswith("ghcr.io/hmseeb/buzz-railway-minio"):
            roles["minio"] = sid
    assert set(roles) == {"pairing", "buzz", "minio"}, roles
    return roles


def repair(config):
    r = by_role(config)
    s = config["services"]

    p = s[r["pairing"]]
    p["name"] = "Pairing"  # the relay references ${{Pairing.RAILWAY_PUBLIC_DOMAIN}} by this name
    p["icon"] = ICON
    p["deploy"] = {**(p.get("deploy") or {}), **RESTART, "startCommand": "buzz-pair-relay"}
    p["networking"] = {"serviceDomains": {"<hasDomain>": {}}}

    b = s[r["buzz"]]
    b["icon"] = ICON
    b["deploy"] = {**(b.get("deploy") or {}), **RESTART, "healthcheckPath": "/_readiness"}

    m = s[r["minio"]]
    m["icon"] = MINIO_ICON
    m["volumeMounts"] = {r["minio"]: {"mountPath": "/data"}}
    return config


def check(config):
    r = by_role(config)
    s = config["services"]
    problems = []
    if s[r["pairing"]]["name"] != "Pairing":
        problems.append("pairing name")
    if not (s[r["pairing"]].get("networking") or {}).get("serviceDomains"):
        problems.append("pairing domain")
    if (s[r["buzz"]].get("deploy") or {}).get("healthcheckPath") != "/_readiness":
        problems.append("relay healthcheck")
    mounts = [v.get("mountPath") for v in (s[r["minio"]].get("volumeMounts") or {}).values()]
    if mounts != ["/data"]:
        problems.append(f"minio volume {mounts}")
    ref = s[r["buzz"]]["variables"]["BUZZ_PAIRING_RELAY_URL"]["defaultValue"]
    if "Pairing.RAILWAY_PUBLIC_DOMAIN" not in ref:
        problems.append(f"pairing ref {ref}")
    return problems


def main():
    config = repair(json.loads(pathlib.Path(sys.argv[1]).read_text()))
    assert not check(config), check(config)
    if "--dry-run" in sys.argv:
        print(json.dumps(config, indent=1))
        return
    # An empty canvas wipes the template's saved layout, so pass the live one back.
    canvas = rw.gql("query($c: String!) { template(code: $c) { canvasConfig } }",
                    {"c": CODE})["template"]["canvasConfig"]
    saved = rw.gql(
        """mutation($id: String!, $input: TemplateUpsertConfigInput!) {
             templateUpsertConfig(id: $id, input: $input) { id code }
           }""",
        {"id": TEMPLATE_ID, "input": {"name": NAME, "workspaceId": WORKSPACE,
                                      "serializedConfig": config, "canvasConfig": canvas}},
        internal=True,
    )["templateUpsertConfig"]
    print(f"saved  id {saved['id']}  code {saved['code']}")
    # A write that returned success is not a write that landed.
    back = rw.gql("query($c: String!) { template(code: $c) { serializedConfig } }",
                  {"c": CODE})["template"]["serializedConfig"]
    problems = check(back)
    print("read-back ok" if not problems else f"read-back FAILED: {problems}")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
