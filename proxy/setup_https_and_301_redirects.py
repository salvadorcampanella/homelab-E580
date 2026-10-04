#!/usr/bin/env python3
import urllib.request
import json
import os
import time

def main():
    env = {}
    script_dir = os.path.dirname(os.path.abspath(__file__))
    env_file = os.path.join(script_dir, "../.env")
    if os.path.exists(env_file):
        with open(env_file) as f:
            for line in f:
                if "=" in line and not line.startswith("#"):
                    k, v = line.strip().split("=", 1)
                    env[k.strip()] = v.strip().strip("\"'").strip()

    npm_url = env.get("NPM_URL", "http://127.0.0.1:81")
    email = env.get("NPM_ADMIN_EMAIL", "admin@example.com")
    password = env.get("NPM_ADMIN_PASSWORD", "changeme")
    base_domain = env.get("BASE_DOMAIN", "salvador512.com")

    print(f"[INFO] Authenticating to NPM ({npm_url})...")
    req = urllib.request.Request(f"{npm_url}/api/tokens", 
        data=json.dumps({"identity": email, "secret": password}).encode(),
        headers={"Content-Type": "application/json"})
    
    resp = urllib.request.urlopen(req, timeout=5)
    token = json.loads(resp.read().decode())["token"]
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    print("[OK] NPM Token obtained!")

    # Find Wildcard Certificate ID for base_domain
    req_cert = urllib.request.Request(f"{npm_url}/api/nginx/certificates", headers=headers)
    certs = json.loads(urllib.request.urlopen(req_cert, timeout=5).read().decode())
    cert_id = 0
    for c in certs:
        if any(base_domain in d for d in c.get("domain_names", [])):
            cert_id = c["id"]
            break
    
    print(f"[INFO] Found SSL Certificate ID: {cert_id} for {base_domain}")

    # 1. Fetch and clean any old DuckDNS or .casita.local Proxy Hosts that do not match base_domain
    req_ph = urllib.request.Request(f"{npm_url}/api/nginx/proxy-hosts", headers=headers)
    proxy_hosts = json.loads(urllib.request.urlopen(req_ph, timeout=5).read().decode())

    print("\n--- STEP 1: Cleaning Old Proxy Hosts ---")
    for p in proxy_hosts:
        domains = p.get("domain_names", [])
        ph_id = p["id"]
        if any(d.endswith(".casita.local") or "duckdns.org" in d for d in domains):
            print(f"Deleting Old Proxy Host ID {ph_id}: {domains}")
            req_del = urllib.request.Request(f"{npm_url}/api/nginx/proxy-hosts/{ph_id}", method="DELETE", headers=headers)
            try:
                urllib.request.urlopen(req_del, timeout=5)
                print(f"  🟢 Deleted Proxy Host ID {ph_id}")
            except Exception as e:
                print(f"  🔴 Error deleting Proxy Host ID {ph_id}: {e}")

    services = [
      ("pihole", "pihole", 80, "http", "location = / {\n    return 302 /admin/;\n}"),
      ("portainer", "portainer", 9443, "https", ""),
      ("npm", "nginx-proxy-manager", 81, "http", ""),
      ("radarr", "radarr", 7878, "http", ""),
      ("sonarr", "sonarr", 8989, "http", ""),
      ("prowlarr", "prowlarr", 9696, "http", ""),
      ("bazarr", "bazarr", 6767, "http", ""),
      ("qbit", "qbittorrent", 8080, "http", ""),
      ("jellyfin", "jellyfin", 8096, "http", ""),
      ("tdarr", "tdarr", 8265, "http", ""),
      ("homepage", "homepage", 3000, "http", ""),
      ("glances", "glances", 61208, "http", ""),
      ("grafana", "grafana", 3000, "http", ""),
      ("fotos", "photoprism-personal", 2342, "http", ""),
      ("familia", "photoprism-compartido", 2342, "http", ""),
      ("n8n", "n8n", 5678, "http", "")
    ]

    # Refresh Proxy Hosts list
    req_ph = urllib.request.Request(f"{npm_url}/api/nginx/proxy-hosts", headers=headers)
    proxy_hosts = json.loads(urllib.request.urlopen(req_ph, timeout=5).read().decode())
    existing_proxy_domains = {p["domain_names"][0]: p["id"] for p in proxy_hosts if p.get("domain_names")}

    print("\n--- STEP 2: Creating/Updating Primary HTTPS Proxy Hosts ---")
    for prefix, fwd_host, fwd_port, scheme, adv_cfg in services:
        https_dom = f"{prefix}.{base_domain}"

        payload_https = {
            "domain_names": [https_dom],
            "forward_scheme": scheme,
            "forward_host": fwd_host,
            "forward_port": fwd_port,
            "block_exploits": True,
            "allow_websocket_upgrade": True,
            "access_list_id": 0,
            "certificate_id": cert_id,
            "ssl_forced": True if cert_id > 0 else False,
            "meta": {"letsencrypt_agree": False, "dns_challenge": False},
            "advanced_config": adv_cfg,
            "enabled": 1,
            "locations": [],
            "http2_support": True if cert_id > 0 else False
        }

        if https_dom in existing_proxy_domains:
            ph_id = existing_proxy_domains[https_dom]
            try:
                req_put = urllib.request.Request(f"{npm_url}/api/nginx/proxy-hosts/{ph_id}", 
                    data=json.dumps(payload_https).encode(), method="PUT", headers=headers)
                urllib.request.urlopen(req_put, timeout=5)
                print(f"  🟢 Updated HTTPS Host ID {ph_id}: https://{https_dom} -> {scheme}://{fwd_host}:{fwd_port}")
            except Exception as e:
                print(f"  🔴 Error updating HTTPS Host {https_dom}: {e}")
        else:
            try:
                req_post = urllib.request.Request(f"{npm_url}/api/nginx/proxy-hosts", 
                    data=json.dumps(payload_https).encode(), method="POST", headers=headers)
                urllib.request.urlopen(req_post, timeout=5)
                print(f"  🟢 Created HTTPS Host: https://{https_dom} -> {scheme}://{fwd_host}:{fwd_port}")
            except Exception as e:
                print(f"  🔴 Error creating HTTPS Host {https_dom}: {e}")

    # Refresh Redirection Hosts list
    req_rh = urllib.request.Request(f"{npm_url}/api/nginx/redirection-hosts", headers=headers)
    redirect_hosts = json.loads(urllib.request.urlopen(req_rh, timeout=5).read().decode())
    existing_redirs = {r["domain_names"][0]: r["id"] for r in redirect_hosts if r.get("domain_names")}

    print("\n--- STEP 3: Creating 301 Redirection Hosts (.casita.local -> HTTPS DuckDNS) ---")
    for prefix, _, _, _, _ in services:
        local_dom = f"{prefix}.casita.local"
        target_dom = f"{prefix}.{base_domain}"

        payload_redir = {
            "domain_names": [local_dom],
            "forward_http_code": 301,
            "forward_scheme": "https",
            "forward_domain_name": target_dom,
            "preserve_path": True,
            "block_exploits": True,
            "advanced_config": ""
        }
        if local_dom not in existing_redirs:
            try:
                req_c = urllib.request.Request(f"{npm_url}/api/nginx/redirection-hosts", 
                    data=json.dumps(payload_redir).encode(), method="POST", headers=headers)
                urllib.request.urlopen(req_c, timeout=5)
                print(f"  🟢 Created 301 Redirect: http://{local_dom} -> https://{target_dom}")
            except Exception as e:
                print(f"  🔴 Error creating redirect for {local_dom}: {e}")
        else:
            rh_id = existing_redirs[local_dom]
            try:
                req_u = urllib.request.Request(f"{npm_url}/api/nginx/redirection-hosts/{rh_id}", 
                    data=json.dumps(payload_redir).encode(), method="PUT", headers=headers)
                urllib.request.urlopen(req_u, timeout=5)
                print(f"  🟢 Updated 301 Redirect ID {rh_id}: http://{local_dom} -> https://{target_dom}")
            except Exception as e:
                print(f"  🔴 Error updating redirect for {local_dom}: {e}")

if __name__ == "__main__":
    main()
