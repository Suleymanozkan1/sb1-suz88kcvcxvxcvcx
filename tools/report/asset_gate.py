#!/usr/bin/env python3
"""Asset gate register (REQ-305, REQ-328): coverage check and readable report.

The register game/data/art/asset_gate.json holds one entry per asset, judged
against docs/ART_DIRECTION.md on the gate columns (style, scale, perspective,
material, lighting, topology, texture, animation, readability, mobile_cost)
with a verdict and a note. An entry names either a file ("path", which may be
a glob such as game/assets/audio/music/neon_core*.wav) or a code-built asset
("builder" plus "source", the file that builds it, and "anchor", a string that
must appear in that file).

--check fails (exit 1, listing every problem) when
  * an asset file under game/ is not covered by an entry path or glob
    (shaders, audio, images and icons, fonts, 3D models; the directories the
    export excludes - tests, tools, server, build - and .godot are skipped),
  * an entry path or glob matches no file, a builder's source file is missing
    or its anchor no longer appears in it,
  * a required field or gate column is missing or empty, a kind or verdict is
    unknown, an id is duplicated, or a pass_with_note entry has no note,
  * the core-skin and trail style entries do not match the styles and items
    used in game/data/cosmetics/cosmetics.json,
  * docs/ASSET_GATE.md differs from what --write would render.
--write renders docs/ASSET_GATE.md from the register (after validating it).

Python 3.11 standard library only.
Usage: python3 tools/report/asset_gate.py --check | --write
"""
from __future__ import annotations

import fnmatch
import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REGISTER = ROOT / "game" / "data" / "art" / "asset_gate.json"
DOC = ROOT / "docs" / "ASSET_GATE.md"
COSMETICS = ROOT / "game" / "data" / "cosmetics" / "cosmetics.json"
SCAN_ROOT = ROOT / "game"
# Not shipped (export_presets.cfg exclude_filter) or engine cache.
SKIP_DIRS = {".godot", "build", "tests", "tools", "server"}
ASSET_GROUPS: dict[str, tuple[str, ...]] = {
    "shaders": (".gdshader", ".gdshaderinc"),
    "audio": (".wav", ".ogg", ".mp3"),
    "images": (".svg", ".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tga", ".exr", ".hdr", ".ktx", ".ktx2"),
    "fonts": (".woff2", ".woff", ".ttf", ".otf", ".fnt"),
    "models": (".glb", ".gltf", ".obj", ".fbx", ".dae", ".blend"),
}
COLUMNS = ["style", "scale", "perspective", "material", "lighting", "topology", "texture", "animation",
           "readability", "mobile_cost"]
COLUMN_TITLES = {
    "style": "Style", "scale": "Scale", "perspective": "Perspective", "material": "Material",
    "lighting": "Lighting", "topology": "Topology", "texture": "Texture", "animation": "Animation",
    "readability": "Readability", "mobile_cost": "Mobile cost",
}
KINDS = ["shader", "mesh_builder", "texture_generator", "icon", "font", "audio", "cosmetic_style"]
KIND_TITLES = {
    "shader": "Shaders",
    "mesh_builder": "Code-built meshes",
    "texture_generator": "Generated textures",
    "icon": "Icons",
    "font": "Fonts",
    "audio": "Audio",
    "cosmetic_style": "Cosmetic styles (core skins and trails)",
}
VERDICTS = ("pass", "pass_with_note")
STYLE_CATEGORIES = ("core_skin", "trail")


def load_register() -> dict:
    return json.loads(REGISTER.read_text(encoding="utf-8"))


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def scan_assets() -> dict[str, str]:
    """Repo-relative asset path -> group, for every asset file under game/."""
    found: dict[str, str] = {}
    ext_group = {ext: group for group, exts in ASSET_GROUPS.items() for ext in exts}
    for path in sorted(SCAN_ROOT.rglob("*")):
        if not path.is_file():
            continue
        parts = path.relative_to(SCAN_ROOT).parts
        if parts and parts[0] in SKIP_DIRS:
            continue
        group = ext_group.get(path.suffix.lower())
        if group:
            found[rel(path)] = group
    return found


def is_glob(pattern: str) -> bool:
    return any(ch in pattern for ch in "*?[")


def matches(pattern: str, candidate: str) -> bool:
    return fnmatch.fnmatchcase(candidate, pattern) if is_glob(pattern) else candidate == pattern


def validate_entries(reg: dict) -> list[str]:
    """Field, kind, verdict, file, builder-anchor and cosmetics checks (no doc check)."""
    problems: list[str] = []
    entries = reg.get("entries")
    if not isinstance(entries, list) or not entries:
        return [f"{rel(REGISTER)}: 'entries' must be a non-empty list"]
    if reg.get("columns") != COLUMNS:
        problems.append(f"{rel(REGISTER)}: 'columns' must be {COLUMNS}")
    seen: Counter[str] = Counter()
    for n, e in enumerate(entries):
        eid = str(e.get("id", "")) if isinstance(e, dict) else ""
        label = eid or f"entry #{n}"
        if not isinstance(e, dict):
            problems.append(f"{label}: not an object")
            continue
        if not eid:
            problems.append(f"{label}: missing id")
        seen[eid] += 1
        if e.get("kind") not in KINDS:
            problems.append(f"{label}: kind '{e.get('kind')}' is not one of {KINDS}")
        for field in ["role", *COLUMNS]:
            value = e.get(field)
            if not isinstance(value, str) or not value.strip():
                problems.append(f"{label}: missing or empty '{field}'")
        if e.get("verdict") not in VERDICTS:
            problems.append(f"{label}: verdict '{e.get('verdict')}' is not one of {VERDICTS}")
        note = e.get("note")
        if not isinstance(note, str):
            problems.append(f"{label}: missing 'note' (use \"\" for none)")
        elif e.get("verdict") == "pass_with_note" and not note.strip():
            problems.append(f"{label}: pass_with_note needs a note")
        has_path = "path" in e
        has_builder = "builder" in e
        if has_path == has_builder:
            problems.append(f"{label}: needs exactly one of 'path' or 'builder'")
        if has_path:
            pattern = str(e["path"])
            if is_glob(pattern):
                if not any(fnmatch.fnmatchcase(rel(p), pattern) for p in ROOT.glob(pattern)):
                    problems.append(f"{label}: glob '{pattern}' matches no file")
            elif not (ROOT / pattern).is_file():
                problems.append(f"{label}: file '{pattern}' does not exist")
        if has_builder:
            source = str(e.get("source", ""))
            anchor = str(e.get("anchor", ""))
            if not source or not anchor:
                problems.append(f"{label}: builder entries need 'source' and 'anchor'")
            elif not (ROOT / source).is_file():
                problems.append(f"{label}: source '{source}' does not exist")
            elif anchor not in (ROOT / source).read_text(encoding="utf-8"):
                problems.append(f"{label}: anchor {anchor!r} not found in {source} (builder renamed or removed?)")
    for eid, count in seen.items():
        if eid and count > 1:
            problems.append(f"{eid}: id used {count} times")
    problems.extend(check_cosmetic_styles(entries))
    return problems


def check_cosmetic_styles(entries: list) -> list[str]:
    """Every core-skin / trail style used by an item has one entry listing exactly those items."""
    problems: list[str] = []
    items = json.loads(COSMETICS.read_text(encoding="utf-8")).get("items", [])
    for category in STYLE_CATEGORIES:
        used: dict[int, list[str]] = {}
        for item in items:
            if item.get("category") == category:
                style = int((item.get("params") or {}).get("style", -1))
                used.setdefault(style, []).append(str(item.get("id")))
        listed: dict[int, dict] = {}
        for e in entries:
            if isinstance(e, dict) and e.get("kind") == "cosmetic_style" and e.get("category") == category:
                sid = e.get("style_id")
                if not isinstance(sid, int):
                    problems.append(f"{e.get('id')}: cosmetic_style entries need an integer 'style_id'")
                    continue
                if sid in listed:
                    problems.append(f"{e.get('id')}: {category} style {sid} listed twice")
                listed[sid] = e
        for sid in sorted(set(used) - set(listed)):
            problems.append(f"{category} style {sid} (items {sorted(used[sid])}) has no asset gate entry")
        for sid in sorted(set(listed) - set(used)):
            problems.append(f"{listed[sid].get('id')}: {category} style {sid} is not used by any item")
        for sid in sorted(set(used) & set(listed)):
            if sorted(listed[sid].get("items", [])) != sorted(used[sid]):
                problems.append(
                    f"{listed[sid].get('id')}: items {sorted(listed[sid].get('items', []))} "
                    f"!= cosmetics.json {sorted(used[sid])}"
                )
    return problems


def coverage(reg: dict, assets: dict[str, str]) -> list[str]:
    patterns = [str(e["path"]) for e in reg.get("entries", []) if isinstance(e, dict) and "path" in e]
    return [f"{path}: {group} asset not covered by any asset gate entry"
            for path, group in assets.items() if not any(matches(p, path) for p in patterns)]


def cell(text: object) -> str:
    return str(text).replace("|", "\\|").replace("\n", " ").strip() or "—"


def asset_label(e: dict) -> str:
    if "path" in e:
        return f"`{e['path']}`"
    return f"`{e['builder']}` ({e['source']})"


def render(reg: dict, assets: dict[str, str]) -> str:
    entries: list[dict] = reg["entries"]
    by_kind: dict[str, list[dict]] = {k: [e for e in entries if e["kind"] == k] for k in KINDS}
    groups = Counter(assets.values())
    path_entries = sum(1 for e in entries if "path" in e)
    builder_entries = len(entries) - path_entries
    out: list[str] = [
        "# FLUX DROP — Asset Gate Register",
        "",
        "<!-- Generated by tools/report/asset_gate.py --write from game/data/art/asset_gate.json. "
        "Edit the JSON, then re-run --write; CI runs --check. -->",
        "",
        "Every shipped asset, checked against the art language of `docs/ART_DIRECTION.md` before inclusion "
        "(REQ-305) on the per-asset gate of §12 / REQ-328. The register is "
        "`game/data/art/asset_gate.json`; `python3 tools/report/asset_gate.py --check` (CI, lint job) fails when an "
        "asset file is not covered, an entry points to a missing file or builder, a gate column is missing, the "
        "core-skin / trail styles drift from `game/data/cosmetics/cosmetics.json`, or this page is stale.",
        "",
        "## Counts",
        "",
        "| Kind | Entries | pass | pass_with_note |",
        "|---|---|---|---|",
    ]
    for kind in KINDS:
        rows = by_kind[kind]
        v = Counter(e["verdict"] for e in rows)
        out.append(f"| {KIND_TITLES[kind]} | {len(rows)} | {v['pass']} | {v['pass_with_note']} |")
    total = Counter(e["verdict"] for e in entries)
    out.append(f"| **Total** | **{len(entries)}** | **{total['pass']}** | **{total['pass_with_note']}** |")
    out += [
        "",
        f"Asset files found under `game/` (shipped directories): {len(assets)} ("
        + ", ".join(f"{g} {groups[g]}" for g in ASSET_GROUPS if groups[g])
        + ")"
        + f". They are covered by {path_entries} path/glob entries; {builder_entries} entries cover code-built "
        "assets (meshes, generated textures, glyph systems, shader styles). No entry fails the gate: assets that "
        "deviate from the art direction or were not verified are `pass_with_note`, and the note says why.",
        "",
        "## Method",
        "",
    ]
    out += [f"- {line}" for line in reg.get("method", [])]
    out += [
        "- Gate columns map to the §12 / REQ-328 checklist: style (consistent style), scale (correct scale), "
        "perspective, material, lighting, topology (sensible topology, no weird geometry), texture (texture "
        "resolution, no visible repetition, no artefacts), animation, readability (unambiguous meaning) and "
        "mobile_cost (acceptable mobile cost). `n/a` marks a column that does not apply to the asset kind.",
        "",
    ]
    for kind in KINDS:
        rows = by_kind[kind]
        if not rows:
            continue
        out += [f"## {KIND_TITLES[kind]}", "", "| ID | Asset | Role | Verdict | Note |", "|---|---|---|---|---|"]
        for e in rows:
            out.append(
                f"| {cell(e['id'])} | {cell(asset_label(e))} | {cell(e['role'])} | {cell(e['verdict'])} "
                f"| {cell(e['note'])} |"
            )
        out += [
            "",
            f"Gate detail — {KIND_TITLES[kind].lower()}:",
            "",
            "| ID | " + " | ".join(COLUMN_TITLES[c] for c in COLUMNS) + " |",
            "|---|" + "---|" * len(COLUMNS),
        ]
        for e in rows:
            out.append(f"| {cell(e['id'])} | " + " | ".join(cell(e[c]) for c in COLUMNS) + " |")
        out.append("")
    return "\n".join(out).rstrip() + "\n"


def main(argv: list[str]) -> int:
    if len(argv) != 1 or argv[0] not in ("--check", "--write"):
        print(__doc__.strip().splitlines()[-1])
        return 2
    try:
        reg = load_register()
    except (OSError, json.JSONDecodeError) as exc:
        print(f"{rel(REGISTER)}: cannot read register: {exc}")
        return 1
    assets = scan_assets()
    problems = validate_entries(reg) + coverage(reg, assets)
    if argv[0] == "--write":
        if problems:
            for p in problems:
                print(p)
            print(f"asset gate: {len(problems)} problem(s); {rel(DOC)} not written")
            return 1
        DOC.write_text(render(reg, assets), encoding="utf-8")
        print(f"asset gate: wrote {rel(DOC)} ({len(reg['entries'])} entries, {len(assets)} asset files)")
        return 0
    if not problems:
        current = DOC.read_text(encoding="utf-8") if DOC.exists() else ""
        if current != render(reg, assets):
            problems.append(f"{rel(DOC)} is out of date: run python3 tools/report/asset_gate.py --write")
    for p in problems:
        print(p)
    print(f"asset gate: {len(problems)} problem(s), {len(reg.get('entries', []))} entries, {len(assets)} asset files")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
