#!/usr/bin/env python3
"""Build the private dev-sources file the simulators import for testing.

Asks for each source (add-ons, IPTV, network shares, media servers) and the
service keys, then writes them to ~/Developer/openstream-build/signing/dev-sources.json
(owner-only permissions, never in the repo or on OSArchive). Debug builds import
that file at launch with `-OpenStreamDevSources <path>`; see scripts/seed-sim.sh.

Run it again to add, replace or remove entries; existing ones are kept.
Passwords are typed without echo and are never printed.
"""

import getpass
import json
import os
import sys
import urllib.error
import urllib.request

OUT = os.path.expanduser("~/Developer/openstream-build/signing/dev-sources.json")
STREMIO_API = "https://api.strem.io/api"


def ask(prompt, default=None, required=True):
    suffix = f" [{default}]" if default else ""
    while True:
        value = input(f"{prompt}{suffix}: ").strip()
        if not value and default is not None:
            return default
        if value or not required:
            return value
        print("  (required)")


def secret(prompt):
    while True:
        value = getpass.getpass(f"{prompt} (hidden): ")
        if value:
            return value
        print("  (required)")


def yes(prompt, default=True):
    hint = "Y/n" if default else "y/N"
    value = input(f"{prompt} [{hint}]: ").strip().lower()
    return default if not value else value.startswith("y")


def post(path, body):
    request = urllib.request.Request(
        f"{STREMIO_API}/{path}", data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        payload = json.load(response)
    if payload.get("error"):
        raise RuntimeError(payload["error"].get("message", "Stremio error"))
    return payload["result"]


def stremio_account_addons():
    """Every add-on installed on the owner's Stremio account, with its full
    (configured) manifest URL. The Stremio password is used once and not saved."""
    email = ask("Stremio email")
    password = secret("Stremio password")
    auth = post("login", {"type": "Login", "email": email, "password": password, "facebook": False})["authKey"]
    addons = post("addonCollectionGet", {"type": "AddonCollectionGet", "authKey": auth, "update": True})["addons"]
    result = []
    for addon in addons:
        url = addon.get("transportUrl", "")
        name = (addon.get("manifest") or {}).get("name") or url
        if not url.startswith("http"):
            continue
        if yes(f"  include {name}?"):
            result.append({"kind": "stremio", "name": name, "manifestURL": url})
    return result


def add_stremio():
    url = ask("Add-on manifest URL (ends in /manifest.json)")
    return {"kind": "stremio", "name": ask("Name", required=False), "manifestURL": url}


def add_xtream():
    return {
        "kind": "xtream", "name": ask("Name", "IPTV"),
        "serverURL": ask("Server URL (e.g. http://host:port)"),
        "username": ask("Username"), "password": secret("Password"),
        "epgURL": ask("EPG URL (optional)", required=False),
    }


def add_m3u():
    return {
        "kind": "m3u", "name": ask("Name", "IPTV"),
        "playlistURL": secret("Playlist URL (may contain credentials)"),
        "epgURL": ask("EPG URL (optional)", required=False),
    }


def add_smb():
    return {
        "kind": "smb", "name": ask("Name", "ServerPlus"),
        "host": ask("Host", "192.168.1.87"), "port": int(ask("Port", "445")),
        "share": ask("Share"), "path": ask("Folder inside the share (optional)", required=False),
        "username": ask("Username"), "password": secret("Password"),
        "domain": ask("Domain (optional)", required=False),
    }


def add_media_server():
    server = ask("Server type (jellyfin / emby / plex)", "jellyfin").lower()
    entry = {"kind": "mediaServer", "server": server, "name": ask("Name", server.title()),
             "url": ask("Server URL")}
    if server == "plex":
        entry["token"] = secret("Plex token")
    else:
        entry["username"] = ask("Username")
        entry["password"] = secret("Password")
    return entry


FIXTURE = os.path.expanduser("~/Developer/openstream-build/iptv-fixture/dev-sources.json")


def add_fixture_iptv():
    """The local IPTV fixture (Fixture Xtream + Fixture M3U on 127.0.0.1:8790).
    Debug builds only, like every entry here; see the fixture's README.md."""
    if not os.path.exists(FIXTURE):
        raise RuntimeError(f"no fixture at {FIXTURE} — run iptvfixture.py generate first")
    with open(FIXTURE) as handle:
        return json.load(handle)["sources"]


def edit_settings(settings):
    if yes("Set the TMDB API key?", default=not settings.get("tmdbAPIKey")):
        settings["tmdbAPIKey"] = secret("TMDB API key (v3) or read token")
    for arr in ("radarr", "sonarr"):
        if yes(f"Set {arr.title()}?", default=False):
            settings[arr] = {
                "url": ask(f"{arr.title()} URL"), "apiKey": secret(f"{arr.title()} API key"),
                "rootFolderPath": ask("Root folder path", required=False),
                "qualityProfileID": ask("Quality profile ID", required=False),
            }
    if yes("Set Trakt?", default=False):
        settings["traktClientID"] = secret("Trakt client ID")


def describe(entry):
    detail = entry.get("manifestURL") or entry.get("serverURL") or entry.get("host") or entry.get("url") or ""
    host = detail.split("//")[-1].split("/")[0]
    return f"{entry['kind']:11} {entry.get('name') or '(unnamed)'} — {host}"


def load():
    if os.path.exists(OUT):
        with open(OUT) as handle:
            return json.load(handle)
    return {"version": 1, "sources": [], "settings": {}}


def save(data):
    os.makedirs(os.path.dirname(OUT), mode=0o700, exist_ok=True)
    os.chmod(os.path.dirname(OUT), 0o700)
    temp = OUT + ".tmp"
    fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as handle:
        json.dump(data, handle, indent=2)
    os.replace(temp, OUT)
    print(f"\nSaved {len(data['sources'])} sources to {OUT} (owner-only).")


def main():
    data = load()
    actions = {
        "1": ("Import add-ons from my Stremio account", stremio_account_addons),
        "2": ("Add a Stremio add-on by URL", add_stremio),
        "3": ("Add IPTV (Xtream username/password)", add_xtream),
        "4": ("Add IPTV (M3U playlist URL)", add_m3u),
        "5": ("Add a network share (SMB)", add_smb),
        "6": ("Add a media server (Jellyfin / Emby / Plex)", add_media_server),
        "f": ("Add the local IPTV fixture (127.0.0.1:8790)", add_fixture_iptv),
    }
    while True:
        print("\nCurrent sources:")
        for index, entry in enumerate(data["sources"], 1):
            print(f"  {index}. {describe(entry)}")
        if not data["sources"]:
            print("  (none)")
        print()
        for key, (title, _) in actions.items():
            print(f"  {key}) {title}")
        print("  k) Service keys (TMDB, Radarr, Sonarr, Trakt)")
        print("  r) Remove a source")
        print("  s) Save and quit     q) Quit without saving")
        choice = input("> ").strip().lower()
        try:
            if choice in actions:
                added = actions[choice][1]()
                data["sources"].extend(added if isinstance(added, list) else [added])
            elif choice == "k":
                edit_settings(data.setdefault("settings", {}))
            elif choice == "r":
                index = int(ask("Number to remove")) - 1
                removed = data["sources"].pop(index)
                print(f"  removed {describe(removed)}")
            elif choice == "s":
                save(data)
                return
            elif choice == "q":
                return
        except (urllib.error.URLError, RuntimeError, ValueError, IndexError, KeyError) as error:
            print(f"  ! {error}")
        except KeyboardInterrupt:
            print()


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, EOFError):
        print("\nNothing saved.")
        sys.exit(1)
