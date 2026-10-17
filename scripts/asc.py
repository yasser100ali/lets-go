#!/usr/bin/env python3
"""Small App Store Connect API client for Let's Go.

Reads the team API key from ~/.appstoreconnect/letsgo_asc_api_key.json (never the repo).

  scripts/asc.py app                       # the app record, if it exists yet
  scripts/asc.py setup-testers EMAIL...    # Internal group with every build, testers added
  scripts/asc.py wait-build BUILD          # wait for a build to finish processing
  scripts/asc.py next-build                # one more than the highest build Apple has
"""
import base64, json, os, sys, time

import jwt
import requests

KEY_FILE = os.path.expanduser("~/.appstoreconnect/letsgo_asc_api_key.json")
BUNDLE_ID = "com.yasser100ali.letsgo"
BASE = "https://api.appstoreconnect.apple.com"
GROUP = "Internal"


def _key():
    with open(KEY_FILE) as f:
        d = json.load(f)
    key = base64.b64decode(d["key"]).decode() if d.get("is_key_content_base64") else d["key"]
    return d, key


def _token():
    d, key = _key()
    now = int(time.time())
    return jwt.encode(
        {"iss": d["issuer_id"], "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": d["key_id"], "typ": "JWT"},
    )


def call(method, path, body=None, params=None, ok=(200, 201, 204)):
    r = requests.request(
        method, BASE + path, json=body, params=params, timeout=60,
        headers={"Authorization": "Bearer " + _token(), "Content-Type": "application/json"},
    )
    if r.status_code not in ok:
        raise SystemExit(f"{method} {path} -> {r.status_code}: {r.text[:800]}")
    return r.json() if r.text else {}


def app():
    data = call("GET", "/v1/apps", params={"filter[bundleId]": BUNDLE_ID})["data"]
    return data[0] if data else None


def setup_testers(emails):
    a = app()
    if not a:
        raise SystemExit(f"No App Store Connect app for {BUNDLE_ID} yet.")
    groups = call("GET", f"/v1/apps/{a['id']}/betaGroups")["data"]
    group = next((g for g in groups if g["attributes"]["isInternalGroup"]), None)
    if not group:
        group = call("POST", "/v1/betaGroups", {
            "data": {
                "type": "betaGroups",
                "attributes": {"name": GROUP, "isInternalGroup": True, "hasAccessToAllBuilds": True},
                "relationships": {"app": {"data": {"type": "apps", "id": a["id"]}}},
            }
        })["data"]
        print(f"Created internal group {group['id']}")
    for email in emails:
        existing = call("GET", "/v1/betaTesters", params={"filter[email]": email, "filter[apps]": a["id"]})["data"]
        if existing:
            call("POST", f"/v1/betaGroups/{group['id']}/relationships/betaTesters",
                 {"data": [{"type": "betaTesters", "id": existing[0]["id"]}]})
        else:
            call("POST", "/v1/betaTesters", {
                "data": {
                    "type": "betaTesters",
                    "attributes": {"email": email},
                    "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": group["id"]}]}},
                }
            })
        print(f"{email} is in {group['attributes']['name']}")


def next_build():
    """Highest build number App Store Connect has for the app, plus one."""
    a = app()
    if not a:
        raise SystemExit("No app record.")
    numbers = []
    url, params = f"/v1/builds", {"filter[app]": a["id"], "limit": 200, "fields[builds]": "version"}
    while url:
        page = call("GET", url, params=params)
        numbers += [int(b["attributes"]["version"]) for b in page["data"] if b["attributes"]["version"].isdigit()]
        nxt = page.get("links", {}).get("next")
        url, params = (nxt.replace(BASE, ""), None) if nxt else (None, None)
    return max(numbers, default=0) + 1


def wait_build(number, timeout=3600):
    a = app()
    if not a:
        raise SystemExit("No app record.")
    start = time.time()
    while time.time() - start < timeout:
        builds = call("GET", "/v1/builds", params={"filter[app]": a["id"], "filter[version]": str(number)})["data"]
        if builds:
            state = builds[0]["attributes"]["processingState"]
            print(f"build {number}: {state}", flush=True)
            if state == "VALID":
                return builds[0]
            if state in ("FAILED", "INVALID"):
                raise SystemExit(f"Build {number} is {state}")
        else:
            print(f"build {number}: not visible yet", flush=True)
        time.sleep(60)
    raise SystemExit("Timed out waiting for processing")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "app"
    if cmd == "app":
        a = app()
        print(json.dumps(a["attributes"], indent=1) if a else "none")
        sys.exit(0 if a else 1)
    elif cmd == "setup-testers":
        setup_testers(sys.argv[2:])
    elif cmd == "wait-build":
        wait_build(sys.argv[2])
    elif cmd == "next-build":
        print(next_build())
    else:
        raise SystemExit(__doc__)
