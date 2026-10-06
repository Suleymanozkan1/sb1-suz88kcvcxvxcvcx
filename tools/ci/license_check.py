#!/usr/bin/env python3
"""Checks that every binary/third-party asset in the game is accounted for.

Rules:
  * Every file under game/assets/fonts must be listed in game/assets/LICENSES.json
    with a license from the allow-list, and the license text file must exist.
  * Every generated asset (audio, icons, the boot splash, baked backdrops) must be
    produced by an in-repo tool recorded in game/assets/LICENSES.json
    ("generated_by").
  * AI image generations (two painted backdrops) are listed under their own
    license tag, naming the provider: its terms must be checked before a store
    release (docs/ASSET_GATE.md notes it on each).
  * No asset may come from a non-allow-listed license.
Usage: python3 tools/ci/license_check.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "game" / "assets"
MANIFEST = ASSETS / "LICENSES.json"
AI_GENERATED = "AI-generated (provider terms)"
ALLOWED = {"OFL-1.1", "MIT", "CC0-1.0", "Original (project)", AI_GENERATED}
CHECK_DIRS = ["fonts", "audio", "icons", "splash", "backdrops"]
SKIP_SUFFIXES = {".import", ".tres", ".md", ".txt", ".json"}


def main() -> int:
    if not MANIFEST.exists():
        print("missing game/assets/LICENSES.json")
        return 1
    manifest = json.loads(MANIFEST.read_text())
    entries = manifest.get("entries", [])
    problems: list[str] = []
    covered: dict[str, dict] = {}
    for e in entries:
        lic = e.get("license", "")
        if lic not in ALLOWED:
            problems.append(f"{e.get('path')}: license '{lic}' not allowed")
        text = e.get("license_file")
        if text and not (ROOT / text).exists():
            problems.append(f"{e.get('path')}: license file {text} missing")
        gen = e.get("generated_by")
        if gen and not (ROOT / gen).exists():
            problems.append(f"{e.get('path')}: generator {gen} missing")
        if lic == AI_GENERATED and not e.get("provider"):
            problems.append(f"{e.get('path')}: an AI generation must name its provider")
        covered[e.get("path", "")] = e
    for d in CHECK_DIRS:
        base = ASSETS / d
        if not base.exists():
            continue
        for path in sorted(base.rglob("*")):
            if not path.is_file() or path.suffix in SKIP_SUFFIXES:
                continue
            rel = str(path.relative_to(ROOT))
            if not any(rel == p or (p.endswith("/") and rel.startswith(p)) for p in covered):
                problems.append(f"{rel}: not listed in LICENSES.json")
    for p in problems:
        print(p)
    print(f"license check: {len(problems)} problem(s), {len(entries)} manifest entries")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
