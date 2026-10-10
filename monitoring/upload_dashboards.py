#!/usr/bin/env python3
"""
Uploads homelab Grafana dashboards directly to Grafana API (v2 Scenes format).
Reads all credentials and settings dynamically from .env.
"""
import base64
import json
import os
from pathlib import Path
import subprocess
import sys
import urllib.error
import urllib.request

REPO_ROOT = Path(__file__).resolve().parent.parent
ENV_PATH = REPO_ROOT / ".env"

def load_env_credentials():
    if not ENV_PATH.exists():
        print(f"❌ Error: .env file not found at {ENV_PATH}")
        sys.exit(1)

    user = "admin"
    password = None

    with open(ENV_PATH, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("GRAFANA_ADMIN_USER="):
                user = line.split("=", 1)[1].strip()
            elif line.startswith("GRAFANA_ADMIN_PASSWORD="):
                password = line.split("=", 1)[1].strip()

    if not password:
        print("❌ Error: GRAFANA_ADMIN_PASSWORD is not set in .env")
        sys.exit(1)

    return user, password

def get_grafana_ip():
    try:
        out = subprocess.check_output(
            ["docker", "inspect", "grafana", "--format", "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}"],
            stderr=subprocess.DEVNULL
        ).decode().strip()
        if out:
            return out
    except Exception:
        pass
    return "127.0.0.1"

def upload_dashboard(filepath, uid, title, auth, ip):
    if not filepath.exists():
        print(f"❌ File not found: {filepath}")
        return

    with open(filepath, "r", encoding="utf-8") as f:
        dash_spec = json.load(f)

    dash_spec["title"] = title
    dash_spec.pop("uid", None)
    dash_spec.pop("id", None)

    body = {
        "apiVersion": "dashboard.grafana.app/v2",
        "kind": "Dashboard",
        "metadata": {
            "name": uid
        },
        "spec": dash_spec
    }

    payload = json.dumps(body).encode("utf-8")
    url = f"http://{ip}:3000/apis/dashboard.grafana.app/v2/namespaces/default/dashboards"

    headers = {
        "Authorization": f"Basic {auth}",
        "Content-Type": "application/json",
        "Accept": "application/json"
    }

    req = urllib.request.Request(url, data=payload, headers=headers, method="POST")

    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode())
            print(f"✅ Dashboard created: '{title}' (UID: {data['metadata']['name']})")
    except urllib.error.HTTPError as e:
        if e.code in (400, 409):
            # If dashboard already exists, update with PUT
            put_req = urllib.request.Request(f"{url}/{uid}", data=payload, headers=headers, method="PUT")
            with urllib.request.urlopen(put_req, timeout=10) as put_resp:
                data = json.loads(put_resp.read().decode())
                print(f"✅ Dashboard updated: '{title}' (UID: {data['metadata']['name']})")
        else:
            print(f"❌ Error uploading '{title}': HTTP {e.code}\n{e.read().decode()}")
            sys.exit(1)

def main():
    user, password = load_env_credentials()
    auth = base64.b64encode(f"{user}:{password}".encode()).decode()
    ip = get_grafana_ip()

    dashboards = [
        (REPO_ROOT / "monitoring/dashboards/host_hardware_monitoring.json", "homelab-host", "🖥️ Host & Hardware Monitoring"),
        (REPO_ROOT / "monitoring/dashboards/docker_containers_monitoring.json", "homelab-docker", "🐳 Docker & Containers Monitoring"),
    ]

    for path, uid, title in dashboards:
        upload_dashboard(path, uid, title, auth, ip)

if __name__ == "__main__":
    main()
