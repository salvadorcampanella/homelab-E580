#!/usr/bin/env python3
"""
sync_lyrics.py — Synchronized (.lrc) Lyrics Downloader for Jellyfin Music Library
================================================================================
Fetches all audio tracks from Jellyfin, checks if a local .lrc file already exists,
and queries the LRCLIB API with appropriate rate-limiting (1.2s delay) to avoid
Cloudflare 503 errors.

Configured via .env:
    BASE_DOMAIN       (default: salvador512.com)
    DOCKER_DATA_PATH  (default: /home/casita/docker-data)
    JELLYFIN_API_KEY  (required: API token from Jellyfin)

Usage:
    python3 arr/sync_lyrics.py
"""

import json
import os
import sys
import time
import urllib.parse
import urllib.request
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
ENV_FILE = os.path.join(REPO_ROOT, ".env")

# 1. Load configuration from .env
env_vars = {}
if os.path.exists(ENV_FILE):
    with open(ENV_FILE, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                env_vars[k.strip()] = v.strip().strip("\"' ")

BASE_DOMAIN = env_vars.get("BASE_DOMAIN", os.environ.get("BASE_DOMAIN", "salvador512.com"))
DOCKER_DATA_PATH = env_vars.get("DOCKER_DATA_PATH", os.environ.get("DOCKER_DATA_PATH", "/home/casita/docker-data"))
TOKEN = env_vars.get("JELLYFIN_API_KEY", os.environ.get("JELLYFIN_API_KEY", ""))

# Fallback: extract from homepage services.yaml if present
if not TOKEN:
    services_yaml = os.path.join(DOCKER_DATA_PATH, "homepage/config/services.yaml")
    if os.path.exists(services_yaml):
        try:
            with open(services_yaml, "r", encoding="utf-8") as f:
                lines = f.readlines()
                for i, line in enumerate(lines):
                    if "type: jellyfin" in line:
                        for sub in lines[i:i+8]:
                            if "key:" in sub:
                                candidate = sub.strip().split("key:", 1)[1].split("#")[0].strip()
                                if candidate and not candidate.startswith("<"):
                                    TOKEN = candidate
                                    break
        except Exception:
            pass

if not TOKEN:
    print("\033[0;31m[ERROR]\033[0m JELLYFIN_API_KEY not found in .env or homepage services.yaml.")
    print("Please set JELLYFIN_API_KEY in your .env file.")
    sys.exit(1)

JF_URL = f"https://jellyfin.{BASE_DOMAIN}"

def get_music_library_id():
    url = f"{JF_URL}/Library/MediaFolders"
    req = urllib.request.Request(url, headers={"Authorization": f'MediaBrowser Token="{TOKEN}"'})
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=15) as resp:
            data = json.loads(resp.read().decode())
            items = data.get("Items", [])
            for item in items:
                if item.get("CollectionType") == "music":
                    return item.get("Id")
                if item.get("Name", "").lower() in ("música", "musica", "music"):
                    return item.get("Id")
            if items:
                return items[0].get("Id")
    except Exception as e:
        print(f"\033[0;31m[ERROR]\033[0m Could not retrieve music library from Jellyfin: {e}")
        sys.exit(1)
    return None

def get_tracks(parent_id):
    url = f"{JF_URL}/Items?parentId={parent_id}&includeItemTypes=Audio&recursive=true&fields=Path"
    req = urllib.request.Request(url, headers={"Authorization": f'MediaBrowser Token="{TOKEN}"'})
    with urllib.request.urlopen(req, context=ctx, timeout=20) as resp:
        data = json.loads(resp.read().decode())
        return data.get("Items", [])

def fetch_lyrics(artist, title, album, duration_s=None):
    headers = {"User-Agent": "Jellyfin-Homelab-LyricsSync/1.0 (https://github.com/jellyfin)"}
    
    # 1. Try exact get
    params = {"artist_name": artist, "track_name": title}
    if album:
        params["album_name"] = album
    if duration_s:
        params["duration"] = int(duration_s)
        
    get_url = f"https://lrclib.net/api/get?{urllib.parse.urlencode(params)}"
    try:
        req = urllib.request.Request(get_url, headers=headers)
        with urllib.request.urlopen(req, timeout=10) as r:
            res = json.loads(r.read().decode())
            lyrics = res.get("syncedLyrics") or res.get("plainLyrics")
            if lyrics:
                return lyrics
    except urllib.error.HTTPError as e:
        if e.code in (429, 503):
            time.sleep(3)
    except Exception:
        pass

    # 2. Try search fallback (fuzzy matching)
    time.sleep(1.0)
    search_params = {"artist_name": artist, "track_name": title}
    search_url = f"https://lrclib.net/api/search?{urllib.parse.urlencode(search_params)}"
    try:
        req = urllib.request.Request(search_url, headers=headers)
        with urllib.request.urlopen(req, timeout=10) as r:
            res_list = json.loads(r.read().decode())
            if isinstance(res_list, list) and len(res_list) > 0:
                best = res_list[0]
                lyrics = best.get("syncedLyrics") or best.get("plainLyrics")
                if lyrics:
                    return lyrics
    except Exception:
        pass

    return None

def main():
    print("==================================================")
    print("  Jellyfin — Synchronized (.lrc) Lyrics Downloader")
    print("==================================================")
    print(f"[INFO] Connecting to {JF_URL}...")
    
    parent_id = get_music_library_id()
    if not parent_id:
        print("\033[0;31m[ERROR]\033[0m No music library folder found in Jellyfin.")
        sys.exit(1)

    try:
        tracks = get_tracks(parent_id)
    except Exception as e:
        print(f"\033[0;31m[ERROR]\033[0m Could not connect to Jellyfin: {e}")
        sys.exit(1)

    total = len(tracks)
    print(f"[INFO] Found {total} audio tracks in library.")

    downloaded = 0
    skipped = 0
    missing = 0

    for i, t in enumerate(tracks, 1):
        name = t.get("Name", "")
        album = t.get("Album", "")
        artists = t.get("Artists", [""])
        artist = artists[0] if artists else ""
        path = t.get("Path", "")
        run_time_ticks = t.get("RunTimeTicks", 0)
        duration_s = int(run_time_ticks / 10000000) if run_time_ticks else None

        if not path:
            continue

        local_path = path.replace("/data/music", f"{DOCKER_DATA_PATH}/media/music")
        base, _ = os.path.splitext(local_path)
        lrc_path = base + ".lrc"

        if os.path.exists(lrc_path):
            skipped += 1
            continue

        print(f"[{i}/{total}] Searching: {artist} - {name}...")
        lyrics = fetch_lyrics(artist, name, album, duration_s)

        if lyrics:
            try:
                with open(lrc_path, "w", encoding="utf-8") as f:
                    f.write(lyrics)
                try:
                    os.chown(lrc_path, 1000, 1000)
                except (PermissionError, AttributeError):
                    pass
                downloaded += 1
                print(f"  \033[0;32m[OK]\033[0m Saved lyrics: {os.path.basename(lrc_path)}")
            except Exception as e:
                print(f"  \033[0;31m[ERROR]\033[0m Writing {lrc_path}: {e}")
        else:
            missing += 1
            print(f"  \033[1;33m[MISS]\033[0m No lyrics found on LRCLIB.")

        time.sleep(1.2)

    print("\n==================================================")
    print(f"Summary: Total: {total} | Downloaded: {downloaded} | Existing: {skipped} | Not found: {missing}")
    print("==================================================")

    print("[INFO] Triggering Jellyfin library scan...")
    ref_url = f"{JF_URL}/Library/Refresh"
    req = urllib.request.Request(ref_url, method="POST", headers={"Authorization": f'MediaBrowser Token="{TOKEN}"'})
    try:
        urllib.request.urlopen(req, context=ctx, timeout=10)
        print("\033[0;32m[OK]\033[0m Jellyfin refresh triggered successfully!")
    except Exception as e:
        print(f"\033[1;33m[WARN]\033[0m Refresh error: {e}")

if __name__ == "__main__":
    main()
