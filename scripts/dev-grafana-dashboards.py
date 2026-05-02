#!/usr/bin/env python3
"""
Hot-push Grafana dashboard JSON files to nonprod on save.
stdlib only — no pip packages required.

Usage:
  ./scripts/dev-grafana-dashboards.py

  Fetches a Grafana API token automatically via get-grafana-api-key.sh
  (requires kubectl access to the nonprod-gen2 cluster context).

  Defaults target nonprod. Override via env vars:
    GRAFANA_URL       (default: https://grafana.local.non-prod.abbottland.io)
    DASHBOARDS_DIR    (default: infra/non-prod-gen2/kube-prometheus-stack/dashboards)
    GRAFANA_FOLDER_UID  (optional: push into a specific folder)
    POLL_INTERVAL     (default: 1.0 seconds)
    DEV_UID_SUFFIX    (default: -dev, appended to uid to avoid provisioned-dashboard conflicts)
"""

import json
import os
import signal
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

SCRIPTS_DIR = Path(__file__).parent.resolve()
REPO_ROOT = SCRIPTS_DIR.parent

GRAFANA_URL = os.environ.get(
    "GRAFANA_URL", "https://grafana.local.non-prod.abbottland.io"
).rstrip("/")
DASHBOARDS_DIR = Path(
    os.environ.get(
        "DASHBOARDS_DIR",
        str(REPO_ROOT / "infra/non-prod-gen2/kube-prometheus-stack/dashboards"),
    )
)
GRAFANA_FOLDER_UID = os.environ.get("GRAFANA_FOLDER_UID", "")
POLL_INTERVAL = float(os.environ.get("POLL_INTERVAL", "1.0"))
# Avoids "Cannot save provisioned dashboard" — provisioned dashboards block API writes.
# Dev copy gets a distinct UID so Grafana treats it as a separate, editable dashboard.
DEV_UID_SUFFIX = os.environ.get("DEV_UID_SUFFIX", "-dev")

# Accept self-signed / cluster-internal certs
_SSL_CTX = ssl.create_default_context()
_SSL_CTX.check_hostname = False
_SSL_CTX.verify_mode = ssl.CERT_NONE


def die(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def ts() -> str:
    return datetime.now().strftime("%H:%M:%S")


# ── token ──────────────────────────────────────────────────────────────────────

def fetch_token() -> str:
    key_script = SCRIPTS_DIR / "get-grafana-api-key.sh"
    if not key_script.exists():
        die(f"{key_script} not found")
    if not os.access(key_script, os.X_OK):
        die(f"{key_script} not executable")

    print("Fetching Grafana API token from nonprod cluster...")
    env = {**os.environ, "KUBE_CONTEXT": "nonprod-gen2"}
    result = subprocess.run(
        ["bash", str(key_script)], capture_output=True, text=True, env=env
    )
    if result.returncode != 0:
        die(f"get-grafana-api-key.sh failed:\n{result.stderr.strip()}")
    token = result.stdout.strip()
    if not token:
        die("get-grafana-api-key.sh returned empty token")
    return token


# ── http ───────────────────────────────────────────────────────────────────────

def grafana_request(
    path: str, token: str, method: str = "GET", data: dict | None = None
) -> tuple[int, dict]:
    url = f"{GRAFANA_URL}{path}"
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(
        url,
        data=body,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=10, context=_SSL_CTX) as resp:
            return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read())
        except Exception:
            return e.code, {"message": str(e)}
    except urllib.error.URLError as e:
        die(f"cannot reach {url}: {e.reason}")


def check_connectivity(token: str) -> str:
    status, body = grafana_request("/api/health", token)
    if status != 200:
        die(f"Grafana health check failed (HTTP {status}): {body}")
    return body.get("version", "unknown")


# ── dashboards ─────────────────────────────────────────────────────────────────

def scan_dashboards() -> list[Path]:
    files = sorted(DASHBOARDS_DIR.glob("*.json"))
    if not files:
        die(f"no .json files found in {DASHBOARDS_DIR}")
    return files


def validate_uids(files: list[Path]) -> None:
    bad = []
    for f in files:
        try:
            data = json.loads(f.read_text())
            if not data.get("uid"):
                bad.append(f)
        except (json.JSONDecodeError, OSError):
            bad.append(f)
    if bad:
        print("ERROR: dashboards missing stable uid field:", file=sys.stderr)
        for f in bad:
            print(f"  {f}", file=sys.stderr)
        sys.exit(1)


def push_file(path: Path, token: str) -> None:
    t = ts()
    try:
        dashboard = json.loads(path.read_text())
    except (json.JSONDecodeError, OSError) as e:
        print(f"[{t}] SKIP  {path.name} — {e}")
        return

    uid = dashboard.get("uid", "")
    if not uid:
        print(f"[{t}] SKIP  {path.name} — no uid field")
        return

    dashboard["uid"] = uid + DEV_UID_SUFFIX
    dashboard["title"] = dashboard.get("title", path.stem) + " (dev)"
    # clear id so Grafana upserts by uid rather than rejecting a stale numeric id
    dashboard.pop("id", None)

    envelope: dict = {"dashboard": dashboard, "overwrite": True, "message": "dev-push"}
    if GRAFANA_FOLDER_UID:
        envelope["folderUID"] = GRAFANA_FOLDER_UID

    status, body = grafana_request("/api/dashboards/db", token, method="POST", data=envelope)

    if 200 <= status < 300:
        slug = body.get("url", "")
        print(f"[{t}] PUSH  {path.name} → {GRAFANA_URL}{slug}")
    else:
        print(f"[{t}] FAIL  {path.name} (HTTP {status})")
        print(json.dumps(body, indent=2))


# ── watcher ────────────────────────────────────────────────────────────────────

def snapshot() -> dict[Path, float]:
    result = {}
    for f in DASHBOARDS_DIR.glob("*.json"):
        try:
            result[f] = f.stat().st_mtime
        except OSError:
            pass
    return result


def watch(token: str) -> None:
    print(f"Watching {DASHBOARDS_DIR} for changes (Ctrl+C to stop)...")
    mtimes = snapshot()

    while True:
        time.sleep(POLL_INTERVAL)
        current = snapshot()
        for f, mtime in current.items():
            if f not in mtimes or mtimes[f] != mtime:
                push_file(f, token)
        mtimes = current


# ── main ───────────────────────────────────────────────────────────────────────

def main() -> None:
    if not DASHBOARDS_DIR.is_dir():
        die(f"DASHBOARDS_DIR does not exist: {DASHBOARDS_DIR}")

    if subprocess.run(["which", "kubectl"], capture_output=True).returncode != 0:
        die("kubectl not found in PATH")

    token = fetch_token()
    version = check_connectivity(token)
    files = scan_dashboards()
    validate_uids(files)

    bar = "━" * 54
    print(f"\n{bar}")
    print(f"  {'Grafana:':<12} {GRAFANA_URL}  (v{version})")
    print(f"  {'Dashboards:':<12} {len(files)} files in {DASHBOARDS_DIR}")
    print(f"  {'Watcher:':<12} poll every {POLL_INTERVAL}s")
    print(f"{bar}\n")

    print("Initial sync...")
    for f in files:
        push_file(f, token)
    print()

    signal.signal(signal.SIGINT, lambda *_: (print("\nStopping watcher."), sys.exit(0)))
    signal.signal(signal.SIGTERM, lambda *_: (print("\nStopping watcher."), sys.exit(0)))

    watch(token)


if __name__ == "__main__":
    main()
