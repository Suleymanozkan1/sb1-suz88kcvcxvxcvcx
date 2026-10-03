#!/usr/bin/env python3
"""Fails if production code or data contains placeholder markers.

Scans game/src, game/data, game/scenes, game/assets/shaders, game/server and
game/tools for TODO, FIXME, TEMP, PLACEHOLDER, MOCK and FAKE (whole words,
case-sensitive upper-case markers plus "fake data"/"mock data" phrases).
Tests are excluded: test doubles are legitimate there.
Usage: python3 tools/ci/placeholder_scan.py [--report out.json]
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCAN_DIRS = ["game/src", "game/data", "game/scenes", "game/assets/shaders", "game/server", "game/tools"]
EXTENSIONS = {".gd", ".gdshader", ".gdshaderinc", ".json", ".tscn", ".tres", ".cfg", ".py"}
# Upper-case markers are matched exactly; the softer words in any case
# ("temp" alone is allowed in prose such as "temp file").
PATTERN = re.compile(r"\b(TODO|FIXME|TEMP|PLACEHOLDER|MOCK|FAKE)\b|(?i:\b(placeholder|mock|fake|todo|fixme)\b)")
# The scanner's own pattern definition is the only allowed occurrence.
ALLOW = {Path(__file__).resolve()}


def scan() -> list[dict]:
    hits: list[dict] = []
    for rel in SCAN_DIRS:
        base = ROOT / rel
        if not base.exists():
            continue
        for path in sorted(base.rglob("*")):
            if path.suffix not in EXTENSIONS or path.resolve() in ALLOW or ".godot" in path.parts:
                continue
            try:
                text = path.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                continue
            for lineno, line in enumerate(text.splitlines(), start=1):
                match = PATTERN.search(line)
                if match:
                    hits.append({"file": str(path.relative_to(ROOT)), "line": lineno, "marker": match.group(0), "text": line.strip()[:160]})
    return hits


def main() -> int:
    hits = scan()
    if "--report" in sys.argv:
        out = Path(sys.argv[sys.argv.index("--report") + 1])
        out.write_text(json.dumps({"hits": hits, "count": len(hits)}, indent=2))
    for h in hits:
        print(f"{h['file']}:{h['line']}: {h['marker']}: {h['text']}")
    print(f"placeholder scan: {len(hits)} hit(s)")
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main())
