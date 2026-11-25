#!/usr/bin/env python3
"""
Extract Create Mechanical Crafting recipes (type == "create:mechanical_crafting")
from a Minecraft modpack directory (mods/*.jar, datapacks/, kubejs/data/, saves/*/datapacks/)
into a CC: Tweaked textutils.unserialize-compatible Lua table database.
Uses Python 3 standard library only.
"""

import argparse
import json
import re
import sys
import zipfile
from pathlib import Path

RECIPE_PATH_RE = re.compile(r"^data/([^/]+)/recipes?/(.+)\.json$")


def normalize_ingredient(spec):
    """Resolve an ingredient JSON spec into an exact item ID or '#tag' matcher."""
    if isinstance(spec, str):
        return spec
    if isinstance(spec, dict):
        if "tag" in spec and isinstance(spec["tag"], str):
            return "#" + spec["tag"]
        if "item" in spec and isinstance(spec["item"], str):
            return spec["item"]
        if "ingredient" in spec:
            return normalize_ingredient(spec["ingredient"])
    if isinstance(spec, list) and spec:
        for entry in spec:
            if isinstance(entry, dict) and "tag" in entry and isinstance(entry["tag"], str):
                return "#" + entry["tag"]
        for entry in spec:
            resolved = normalize_ingredient(entry)
            if resolved:
                return resolved
    return None


def extract_result(res_obj):
    """Support both MC 1.21.1 ({id, count}) and MC 1.20 ({item, count}) result objects."""
    if isinstance(res_obj, str):
        return res_obj, 1
    if isinstance(res_obj, dict):
        item_id = res_obj.get("id") or res_obj.get("item")
        count = int(res_obj.get("count") or 1)
        return item_id, max(1, count)
    return None, 1


def humanize_item_id(item_id):
    short = str(item_id).split(":", 1)[-1]
    words = [w for w in short.replace("-", "_").split("_") if w]
    return " ".join(w[:1].upper() + w[1:] for w in words) if words else str(item_id)


def lua_quote(s):
    escaped = (
        str(s)
        .replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\r", "\\r")
    )
    return f'"{escaped}"'


def parse_recipe_json(raw_bytes, max_width, max_height):
    data = json.loads(raw_bytes.decode("utf-8-sig", errors="ignore"))
    if not isinstance(data, dict):
        return None, "not_dict"
    if data.get("type") != "create:mechanical_crafting":
        return None, "other_type"

    pattern = data.get("pattern")
    key_map = data.get("key")
    if not isinstance(pattern, list) or not pattern or not isinstance(key_map, dict):
        return None, "invalid_pattern"

    height = len(pattern)
    width = max((len(str(row)) for row in pattern), default=0)
    if height > max_height or width > max_width:
        return None, f"oversized:{width}x{height}"

    result_id, result_count = extract_result(data.get("result"))
    if not result_id:
        return None, "missing_result"

    layout = {}
    ingredients = {}
    total_count = 0

    for r_idx, row in enumerate(pattern):
        row_str = str(row)
        for c_idx, ch in enumerate(row_str):
            if ch == " ":
                continue
            spec = key_map.get(ch)
            matcher = normalize_ingredient(spec)
            if not matcher:
                return None, f"unresolved_key:{ch}"
            slot_idx = r_idx * max_width + c_idx + 1
            layout[slot_idx] = matcher
            ingredients[matcher] = ingredients.get(matcher, 0) + 1
            total_count += 1

    if total_count == 0:
        return None, "empty_pattern"

    return {
        "name": humanize_item_id(result_id),
        "result": result_id,
        "resultCount": result_count,
        "totalCount": total_count,
        "ingredients": ingredients,
        "layout": layout,
    }, None


def scan_zip_archive(archive_path, stats, raw_recipes, max_width, max_height):
    try:
        with zipfile.ZipFile(archive_path, "r") as zf:
            for member in sorted(zf.namelist()):
                m = RECIPE_PATH_RE.match(member)
                if not m:
                    continue
                namespace, rel_path = m.group(1), m.group(2)
                recipe_id = f"{namespace}:{rel_path}"
                try:
                    raw = zf.read(member)
                    parsed, reason = parse_recipe_json(raw, max_width, max_height)
                    if parsed:
                        raw_recipes[recipe_id] = parsed
                    elif reason and reason.startswith("oversized:"):
                        stats["skipped_oversized"].append((recipe_id, reason))
                    elif reason != "other_type":
                        stats["skipped_invalid"].append((recipe_id, reason))
                except Exception as exc:
                    stats["skipped_invalid"].append((recipe_id, str(exc)))
    except Exception as exc:
        stats["warnings"].append(f"Failed reading archive {archive_path}: {exc}")


def scan_open_datapack_dir(data_dir: Path, stats, raw_recipes, max_width, max_height):
    if not data_dir.is_dir():
        return
    for json_path in sorted(data_dir.rglob("*.json")):
        try:
            rel = json_path.relative_to(data_dir)
        except ValueError:
            continue
        parts = rel.parts
        if len(parts) < 3 or parts[1] not in ("recipe", "recipes"):
            continue
        namespace = parts[0]
        rel_recipe = "/".join(parts[2:])[:-5]  # strip .json
        recipe_id = f"{namespace}:{rel_recipe}"
        try:
            raw = json_path.read_bytes()
            parsed, reason = parse_recipe_json(raw, max_width, max_height)
            if parsed:
                raw_recipes[recipe_id] = parsed
            elif reason and reason.startswith("oversized:"):
                stats["skipped_oversized"].append((recipe_id, reason))
            elif reason != "other_type":
                stats["skipped_invalid"].append((recipe_id, reason))
        except Exception as exc:
            stats["skipped_invalid"].append((recipe_id, str(exc)))


def scan_datapacks_container(container_dir: Path, stats, raw_recipes, max_width, max_height):
    if not container_dir.is_dir():
        return
    for entry in sorted(container_dir.iterdir()):
        if entry.is_file() and entry.suffix.lower() == ".zip":
            stats["archives_scanned"] += 1
            scan_zip_archive(entry, stats, raw_recipes, max_width, max_height)
        elif entry.is_dir():
            data_sub = entry / "data"
            if data_sub.is_dir():
                scan_open_datapack_dir(data_sub, stats, raw_recipes, max_width, max_height)


def build_final_db(raw_recipes):
    db = {}
    used_result_counts = {}

    for recipe_id in sorted(raw_recipes.keys()):
        rec = dict(raw_recipes[recipe_id])
        base_key = rec["result"]
        seq = used_result_counts.get(base_key, 0) + 1
        used_result_counts[base_key] = seq
        if seq == 1:
            final_key = base_key
        else:
            final_key = f"{base_key}_{seq}"
            rec["name"] = f"{rec['name']} #{seq}"
        db[final_key] = rec
    return db


def format_lua_db(db):
    lines = ["{"]
    keys = sorted(db.keys())
    for idx, key in enumerate(keys):
        rec = db[key]
        lines.append(f"  [{lua_quote(key)}] = {{")
        lines.append(f"    name = {lua_quote(rec['name'])},")
        lines.append(f"    result = {lua_quote(rec['result'])},")
        lines.append(f"    resultCount = {int(rec['resultCount'])},")
        lines.append(f"    totalCount = {int(rec['totalCount'])},")

        ing_parts = []
        for mat in sorted(rec["ingredients"].keys()):
            ing_parts.append(f"[{lua_quote(mat)}] = {int(rec['ingredients'][mat])}")
        lines.append("    ingredients = { " + ", ".join(ing_parts) + " },")

        lay_parts = []
        for slot in sorted(rec["layout"].keys()):
            lay_parts.append(f"[{int(slot)}] = {lua_quote(rec['layout'][slot])}")
        lines.append("    layout = { " + ", ".join(lay_parts) + " },")

        comma = "," if idx < len(keys) - 1 else ""
        lines.append(f"  }}{comma}")
    lines.append("}")
    return "\n".join(lines) + "\n"


def extract_modpack_recipes(modpack_dir: Path, max_width=5, max_height=5):
    stats = {
        "jars_scanned": 0,
        "archives_scanned": 0,
        "skipped_oversized": [],
        "skipped_invalid": [],
        "warnings": [],
    }
    raw_recipes = {}

    mods_dir = modpack_dir / "mods"
    if mods_dir.is_dir():
        for jar in sorted(mods_dir.glob("*.jar")):
            stats["jars_scanned"] += 1
            scan_zip_archive(jar, stats, raw_recipes, max_width, max_height)

    # Datapacks & KubeJS override mod JAR recipes in order
    scan_datapacks_container(modpack_dir / "datapacks", stats, raw_recipes, max_width, max_height)
    scan_open_datapack_dir(modpack_dir / "kubejs" / "data", stats, raw_recipes, max_width, max_height)

    saves_dir = modpack_dir / "saves"
    if saves_dir.is_dir():
        for world_dir in sorted(saves_dir.iterdir()):
            if world_dir.is_dir():
                scan_datapacks_container(world_dir / "datapacks", stats, raw_recipes, max_width, max_height)

    db = build_final_db(raw_recipes)
    return db, stats


def main():
    parser = argparse.ArgumentParser(
        description="Extract Create Mechanical Crafting recipes from a Minecraft modpack into a Drunken Crafter Lua DB."
    )
    parser.add_argument("--modpack-dir", required=True, help="Path to Minecraft modpack instance directory")
    parser.add_argument("--output", default="data/crafter_recipes_default.db", help="Output Lua DB path")
    parser.add_argument("--max-width", type=int, default=5, help="Max Crafter grid width (default: 5)")
    parser.add_argument("--max-height", type=int, default=5, help="Max Crafter grid height (default: 5)")
    args = parser.parse_args()

    modpack_dir = Path(args.modpack_dir)
    if not modpack_dir.is_dir():
        print(f"ERROR: Modpack directory not found: {modpack_dir}", file=sys.stderr)
        return 1

    db, stats = extract_modpack_recipes(modpack_dir, args.max_width, args.max_height)
    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    lua_text = format_lua_db(db)
    out_path.write_text(lua_text, encoding="utf-8")

    print("=== Create Mechanical Crafting Recipe Extraction Summary ===")
    print(f"Modpack dir       : {modpack_dir}")
    print(f"JAR files scanned : {stats['jars_scanned']}")
    print(f"ZIP datapacks     : {stats['archives_scanned']}")
    print(f"Recipes exported  : {len(db)}")
    print(f"Skipped oversized : {len(stats['skipped_oversized'])}")
    print(f"Skipped invalid   : {len(stats['skipped_invalid'])}")
    print(f"Output file       : {out_path} ({len(lua_text.encode('utf-8'))} bytes)")
    for rid, reason in stats["skipped_oversized"][:10]:
        print(f"  [SKIP OVERSIZED] {rid} ({reason})")
    for w in stats["warnings"]:
        print(f"  [WARN] {w}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
