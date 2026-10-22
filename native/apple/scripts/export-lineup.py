#!/usr/bin/env python3
"""Wrap a private legacy channel list in the oStream lineup format."""

import argparse
import json
import os
from datetime import date
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--name", default="Complete US")
    parser.add_argument("--region", default="US")
    args = parser.parse_args()
    original = json.loads(args.source.read_text())
    lineup = {
        "format": "ostream-lineup",
        "version": 1,
        "name": args.name,
        "region": args.region,
        "updated": date.today().isoformat(),
        "channels": original["channels"],
        "markets": original.get("markets", {}),
    }
    encoded = json.dumps(lineup, ensure_ascii=False, separators=(",", ":")).encode()
    if len(encoded) > 128 * 1024:
        parser.error("Lineup exceeds 128 KB")
    args.destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with args.destination.open("xb") as output:
        os.chmod(args.destination, 0o600)
        output.write(encoded)
    print(f"Exported {len(lineup['channels'])} channels ({len(encoded)} bytes)")


if __name__ == "__main__":
    main()
