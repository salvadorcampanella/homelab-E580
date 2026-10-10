#!/usr/bin/env python3
"""
Syncs homelab Grafana dashboards and alert rules directly via Grafana API.
Reads all credentials dynamically from .env and detects Docker container IP.
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
ALERT_CONFIG_PATH = REPO_ROOT / "monitoring/alerting/homelab_alerts.json"

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

def get_prometheus_datasource_uid(base_url, headers):
    req = urllib.request.Request(f"{base_url}/api/datasources", headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            datasources = json.loads(resp.read().decode())
            for ds in datasources:
                if ds.get("type") == "prometheus":
                    return ds.get("uid")
    except Exception as e:
        print(f"⚠️ Could not resolve Prometheus datasource UID dynamically: {e}")
    return "prometheus"

def upload_dashboard(filepath, uid, title, base_url, headers):
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
    url = f"{base_url}/apis/dashboard.grafana.app/v2/namespaces/default/dashboards"

    post_headers = dict(headers)
    post_headers["Content-Type"] = "application/json"

    req = urllib.request.Request(url, data=payload, headers=post_headers, method="POST")

    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode())
            print(f"✅ Dashboard created: '{title}' (UID: {data['metadata']['name']})")
    except urllib.error.HTTPError as e:
        if e.code in (400, 409):
            put_req = urllib.request.Request(f"{url}/{uid}", data=payload, headers=post_headers, method="PUT")
            with urllib.request.urlopen(put_req, timeout=10) as put_resp:
                data = json.loads(put_resp.read().decode())
                print(f"✅ Dashboard updated: '{title}' (UID: {data['metadata']['name']})")
        else:
            print(f"❌ Error uploading '{title}': HTTP {e.code}\n{e.read().decode()}")
            sys.exit(1)

def ensure_folder(folder_uid, title, base_url, headers):
    url = f"{base_url}/api/folders"
    post_headers = dict(headers)
    post_headers["Content-Type"] = "application/json"

    payload = json.dumps({"title": title, "uid": folder_uid}).encode("utf-8")
    req = urllib.request.Request(url, data=payload, headers=post_headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return folder_uid
    except urllib.error.HTTPError as e:
        if e.code in (400, 409, 412):
            return folder_uid
        print(f"⚠️ Warning ensuring folder '{title}': HTTP {e.code}")
        return folder_uid

def sync_alert_rules(config, prom_uid, base_url, headers):
    folder_uid = ensure_folder(config["folder"]["uid"], config["folder"]["title"], base_url, headers)

    alert_headers = dict(headers)
    alert_headers["Content-Type"] = "application/json"
    alert_headers["X-Disable-Provenance"] = "true"

    url = f"{base_url}/api/v1/provisioning/alert-rules"

    for rule in config["rules"]:
        rule_uid = rule["uid"]
        title = rule["title"]
        prom_expr = rule["expr"]
        threshold_val = rule["threshold"]
        severity = rule["severity"]
        for_duration = rule["for"]

        body = {
            "uid": rule_uid,
            "title": title,
            "condition": "C",
            "data": [
                {
                    "refId": "A",
                    "relativeTimeRange": {"from": 600, "to": 0},
                    "datasourceUid": prom_uid,
                    "model": {
                        "expr": prom_expr,
                        "instant": True,
                        "refId": "A"
                    }
                },
                {
                    "refId": "B",
                    "relativeTimeRange": {"from": 600, "to": 0},
                    "datasourceUid": "__expr__",
                    "model": {
                        "datasource": {"type": "__expr__", "uid": "__expr__"},
                        "expression": "A",
                        "reducer": "last",
                        "refId": "B",
                        "type": "reduce"
                    }
                },
                {
                    "refId": "C",
                    "relativeTimeRange": {"from": 600, "to": 0},
                    "datasourceUid": "__expr__",
                    "model": {
                        "datasource": {"type": "__expr__", "uid": "__expr__"},
                        "expression": "B",
                        "refId": "C",
                        "type": "threshold",
                        "conditions": [
                            {
                                "evaluator": {"params": [threshold_val], "type": "gt"},
                                "operator": {"type": "and"},
                                "query": {"params": ["C"]},
                                "reducer": {"params": [], "type": "last"},
                                "type": "query"
                            }
                        ]
                    }
                }
            ],
            "noDataState": "NoData",
            "execErrState": "Error",
            "for": for_duration,
            "annotations": {
                "summary": rule["summary"]
            },
            "labels": {
                "severity": severity
            },
            "folderUID": folder_uid,
            "ruleGroup": rule.get("ruleGroup", "Homelab")
        }

        payload = json.dumps(body).encode("utf-8")
        req = urllib.request.Request(url, data=payload, headers=alert_headers, method="POST")

        try:
            with urllib.request.urlopen(req, timeout=5) as resp:
                print(f"✅ Alert rule created: '{title}' (UID: {rule_uid})")
        except urllib.error.HTTPError as e:
            if e.code in (400, 409):
                put_req = urllib.request.Request(f"{url}/{rule_uid}", data=payload, headers=alert_headers, method="PUT")
                with urllib.request.urlopen(put_req, timeout=5) as put_resp:
                    print(f"✅ Alert rule updated: '{title}' (UID: {rule_uid})")
            else:
                print(f"❌ Error syncing alert '{title}': HTTP {e.code}\n{e.read().decode()}")

def sync_notification_policy(policy, base_url, headers):
    url = f"{base_url}/api/v1/provisioning/policies"
    policy_headers = dict(headers)
    policy_headers["Content-Type"] = "application/json"

    payload = json.dumps(policy).encode("utf-8")
    req = urllib.request.Request(url, data=payload, headers=policy_headers, method="PUT")

    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            print(f"✅ Notification policy set to receiver: '{policy.get('receiver')}'")
    except urllib.error.HTTPError as e:
        print(f"❌ Error setting notification policy: HTTP {e.code}\n{e.read().decode()}")

def main():
    user, password = load_env_credentials()
    auth = base64.b64encode(f"{user}:{password}".encode()).decode()
    ip = get_grafana_ip()
    base_url = f"http://{ip}:3000"

    headers = {
        "Authorization": f"Basic {auth}",
        "Accept": "application/json"
    }

    print(f"🚀 Connecting to Grafana at {base_url}...")
    prom_uid = get_prometheus_datasource_uid(base_url, headers)

    print("\n--- 1. Syncing Dashboards ---")
    dashboards = [
        (REPO_ROOT / "monitoring/dashboards/host_hardware_monitoring.json", "homelab-host", "🖥️ Host & Hardware Monitoring"),
        (REPO_ROOT / "monitoring/dashboards/docker_containers_monitoring.json", "homelab-docker", "🐳 Docker & Containers Monitoring"),
    ]
    for path, uid, title in dashboards:
        upload_dashboard(path, uid, title, base_url, headers)

    print("\n--- 2. Syncing Alert Rules & Policies ---")
    if ALERT_CONFIG_PATH.exists():
        with open(ALERT_CONFIG_PATH, "r", encoding="utf-8") as f:
            alert_config = json.load(f)
        sync_alert_rules(alert_config, prom_uid, base_url, headers)
        if "policy" in alert_config:
            sync_notification_policy(alert_config["policy"], base_url, headers)
    else:
        print(f"⚠️ Alert config file not found at {ALERT_CONFIG_PATH}")

    print("\n🎉 Grafana provisioning complete!")

if __name__ == "__main__":
    main()
