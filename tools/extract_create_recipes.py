#!/usr/bin/env python3
"""
Extract Create Mechanical Crafting ("create:mechanical_crafting") and
Create Sequenced Assembly ("create:sequenced_assembly") recipes
from a Minecraft modpack directory (mods/*.jar, datapacks/, kubejs/data/, saves/*/datapacks/)
into CC: Tweaked textutils.unserialize-compatible Lua table databases.
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


def normalize_fluid(spec):
    """Resolve a NeoForge/Create fluid ingredient JSON spec into a fluid ID or '#tag'."""
    if isinstance(spec, str):
        return spec
    if isinstance(spec, dict):
        if "fluid" in spec and isinstance(spec["fluid"], str):
            return spec["fluid"]
        if "tag" in spec and isinstance(spec["tag"], str):
            return "#" + spec["tag"]
        if "fluidTag" in spec and isinstance(spec["fluidTag"], str):
            return "#" + spec["fluidTag"]
        if "fluids" in spec:
            return normalize_fluid(spec["fluids"])
    if isinstance(spec, list) and spec:
        for entry in spec:
            resolved = normalize_fluid(entry)
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


def compute_primary_chance(results_list):
    """Calculate primary result probability from Create ProcessingOutput weights/chances."""
    if not isinstance(results_list, list) or not results_list:
        return 1.0
    first = results_list[0]
    if len(results_list) == 1:
        if isinstance(first, dict) and "chance" in first:
            c = float(first["chance"])
            return round(c, 4) if c <= 1.0 else 1.0
        return 1.0

    weights = []
    for entry in results_list:
        if isinstance(entry, dict) and "chance" in entry:
            weights.append(max(0.0, float(entry["chance"])))
        else:
            weights.append(1.0)
    total_w = sum(weights)
    if total_w <= 0.0:
        return 1.0
    if total_w <= 1.0001:
        return round(weights[0], 4)
    return round(weights[0] / total_w, 4)


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


def parse_mechanical_recipe(data, max_width, max_height):
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


def parse_sequenced_recipe(data):
    base_ing = normalize_ingredient(data.get("ingredient"))
    if not base_ing:
        return None, "missing_base_ingredient"

    trans_raw = data.get("transitional_item") or data.get("transitionalItem")
    trans_id, _ = extract_result(trans_raw)
    if not trans_id:
        return None, "missing_transitional_item"

    results_list = data.get("results")
    if not isinstance(results_list, list) or not results_list:
        return None, "missing_results"
    result_id, result_count = extract_result(results_list[0])
    if not result_id:
        return None, "missing_result_id"

    loops = max(1, int(data.get("loops") or 1))
    chance = compute_primary_chance(results_list)

    seq_raw = data.get("sequence")
    if not isinstance(seq_raw, list) or not seq_raw:
        return None, "empty_sequence"

    ingredients = {base_ing: 1}
    total_count = 1
    sequence = []

    for step in seq_raw:
        if not isinstance(step, dict):
            return None, "invalid_step"
        stype = str(step.get("type") or "")
        step_ings = step.get("ingredients") or []

        if stype == "create:deploying":
            if len(step_ings) < 2:
                return None, "deploying_missing_held_item"
            held_matcher = normalize_ingredient(step_ings[1])
            if not held_matcher:
                return None, "deploying_unresolved_item"
            keep_held = bool(step.get("keep_held_item") or step.get("keepHeldItem"))
            step_entry = {"type": "deploying", "item": held_matcher}
            if keep_held:
                step_entry["keepHeldItem"] = True
            else:
                ingredients[held_matcher] = ingredients.get(held_matcher, 0) + loops
                total_count += loops
            sequence.append(step_entry)

        elif stype == "create:pressing":
            sequence.append({"type": "pressing"})

        elif stype == "create:cutting":
            sequence.append({"type": "cutting"})

        elif stype == "create:filling":
            fluid_spec = step_ings[1] if len(step_ings) >= 2 else None
            if fluid_spec is None:
                f_ings = step.get("fluidIngredients") or step.get("fluid_ingredients") or []
                fluid_spec = f_ings[0] if f_ings else None
            fluid_id = normalize_fluid(fluid_spec)
            if not fluid_id:
                return None, "filling_unresolved_fluid"
            sequence.append({"type": "filling", "fluid": fluid_id})

        else:
            return None, f"unsupported_step:{stype}"

    return {
        "name": humanize_item_id(result_id),
        "result": result_id,
        "resultCount": result_count,
        "chance": chance,
        "baseIngredient": base_ing,
        "transitionalItem": trans_id,
        "loops": loops,
        "totalCount": total_count,
        "ingredients": ingredients,
        "sequence": sequence,
    }, None


def process_raw_json(recipe_id, raw_bytes, max_width, max_height, mech_raw, seq_raw, stats):
    data = json.loads(raw_bytes.decode("utf-8-sig", errors="ignore"))
    if not isinstance(data, dict):
        return
    rtype = data.get("type")
    if rtype == "create:mechanical_crafting":
        parsed, reason = parse_mechanical_recipe(data, max_width, max_height)
        if parsed:
            mech_raw[recipe_id] = parsed
        elif reason and reason.startswith("oversized:"):
            stats["skipped_oversized"].append((recipe_id, reason))
        else:
            stats["skipped_invalid"].append((recipe_id, reason))
    elif rtype == "create:sequenced_assembly":
        parsed, reason = parse_sequenced_recipe(data)
        if parsed:
            seq_raw[recipe_id] = parsed
        elif reason and reason.startswith("unsupported_step:"):
            stats["skipped_unsupported_seq"].append((recipe_id, reason))
        else:
            stats["skipped_invalid_seq"].append((recipe_id, reason))


def scan_zip_archive(archive_path, stats, mech_raw, seq_raw, max_width, max_height):
    try:
        with zipfile.ZipFile(archive_path, "r") as zf:
            for member in sorted(zf.namelist()):
                m = RECIPE_PATH_RE.match(member)
                if not m:
                    continue
                namespace, rel_path = m.group(1), m.group(2)
                recipe_id = f"{namespace}:{rel_path}"
                try:
                    process_raw_json(
                        recipe_id, zf.read(member), max_width, max_height, mech_raw, seq_raw, stats
                    )
                except Exception as exc:
                    stats["skipped_invalid"].append((recipe_id, str(exc)))
    except Exception as exc:
        stats["warnings"].append(f"Failed reading archive {archive_path}: {exc}")


def scan_open_datapack_dir(data_dir: Path, stats, mech_raw, seq_raw, max_width, max_height):
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
        rel_recipe = "/".join(parts[2:])[:-5]
        recipe_id = f"{namespace}:{rel_recipe}"
        try:
            process_raw_json(
                recipe_id, json_path.read_bytes(), max_width, max_height, mech_raw, seq_raw, stats
            )
        except Exception as exc:
            stats["skipped_invalid"].append((recipe_id, str(exc)))


def scan_datapacks_container(container_dir: Path, stats, mech_raw, seq_raw, max_width, max_height):
    if not container_dir.is_dir():
        return
    for entry in sorted(container_dir.iterdir()):
        if entry.is_file() and entry.suffix.lower() == ".zip":
            stats["archives_scanned"] += 1
            scan_zip_archive(entry, stats, mech_raw, seq_raw, max_width, max_height)
        elif entry.is_dir():
            data_sub = entry / "data"
            if data_sub.is_dir():
                scan_open_datapack_dir(data_sub, stats, mech_raw, seq_raw, max_width, max_height)


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
        if "chance" in rec:
            lines.append(f"    chance = {rec['chance']},")
        if "baseIngredient" in rec:
            lines.append(f"    baseIngredient = {lua_quote(rec['baseIngredient'])},")
        if "transitionalItem" in rec:
            lines.append(f"    transitionalItem = {lua_quote(rec['transitionalItem'])},")
        if "loops" in rec:
            lines.append(f"    loops = {int(rec['loops'])},")
        lines.append(f"    totalCount = {int(rec['totalCount'])},")

        ing_parts = []
        for mat in sorted(rec["ingredients"].keys()):
            ing_parts.append(f"[{lua_quote(mat)}] = {int(rec['ingredients'][mat])}")
        lines.append("    ingredients = { " + ", ".join(ing_parts) + " },")

        if "layout" in rec:
            lay_parts = []
            for slot in sorted(rec["layout"].keys()):
                lay_parts.append(f"[{int(slot)}] = {lua_quote(rec['layout'][slot])}")
            lines.append("    layout = { " + ", ".join(lay_parts) + " },")

        if "sequence" in rec:
            seq_parts = []
            for step in rec["sequence"]:
                fields = [f"type = {lua_quote(step['type'])}"]
                if "item" in step:
                    fields.append(f"item = {lua_quote(step['item'])}")
                if "fluid" in step:
                    fields.append(f"fluid = {lua_quote(step['fluid'])}")
                if step.get("keepHeldItem"):
                    fields.append("keepHeldItem = true")
                seq_parts.append("{ " + ", ".join(fields) + " }")
            lines.append("    sequence = { " + ", ".join(seq_parts) + " },")

        comma = "," if idx < len(keys) - 1 else ""
        lines.append(f"  }}{comma}")
    lines.append("}")
    return "\n".join(lines) + "\n"


def extract_all_modpack_recipes(modpack_dir: Path, max_width=5, max_height=5):
    stats = {
        "jars_scanned": 0,
        "archives_scanned": 0,
        "skipped_oversized": [],
        "skipped_invalid": [],
        "skipped_unsupported_seq": [],
        "skipped_invalid_seq": [],
        "warnings": [],
    }
    mech_raw = {}
    seq_raw = {}

    mods_dir = modpack_dir / "mods"
    if mods_dir.is_dir():
        for jar in sorted(mods_dir.glob("*.jar")):
            stats["jars_scanned"] += 1
            scan_zip_archive(jar, stats, mech_raw, seq_raw, max_width, max_height)

    # Datapacks & KubeJS override mod JAR recipes in order
    scan_datapacks_container(modpack_dir / "datapacks", stats, mech_raw, seq_raw, max_width, max_height)
    scan_open_datapack_dir(modpack_dir / "kubejs" / "data", stats, mech_raw, seq_raw, max_width, max_height)

    saves_dir = modpack_dir / "saves"
    if saves_dir.is_dir():
        for world_dir in sorted(saves_dir.iterdir()):
            if world_dir.is_dir():
                scan_datapacks_container(world_dir / "datapacks", stats, mech_raw, seq_raw, max_width, max_height)

    return build_final_db(mech_raw), build_final_db(seq_raw), stats


def extract_modpack_recipes(modpack_dir: Path, max_width=5, max_height=5):
    """Backward-compatible helper returning (mechanical_db, stats)."""
    mech_db, _, stats = extract_all_modpack_recipes(modpack_dir, max_width, max_height)
    return mech_db, stats


def main():
    parser = argparse.ArgumentParser(
        description="Extract Create Mechanical Crafting and Sequenced Assembly recipes into Drunken Crafter Lua DBs."
    )
    parser.add_argument("--modpack-dir", required=True, help="Path to Minecraft modpack instance directory")
    parser.add_argument(
        "--type",
        choices=("all", "mechanical", "sequenced"),
        default="all",
        help="Recipe category to extract (default: all)",
    )
    parser.add_argument("--output", default="data/crafter_recipes_default.db", help="Mechanical Lua DB output path")
    parser.add_argument(
        "--sequenced-output",
        default="data/sequenced_recipes_default.db",
        help="Sequenced Assembly Lua DB output path",
    )
    parser.add_argument("--max-width", type=int, default=5, help="Max Crafter grid width (default: 5)")
    parser.add_argument("--max-height", type=int, default=5, help="Max Crafter grid height (default: 5)")
    args = parser.parse_args()

    modpack_dir = Path(args.modpack_dir)
    if not modpack_dir.is_dir():
        print(f"ERROR: Modpack directory not found: {modpack_dir}", file=sys.stderr)
        return 1

    mech_db, seq_db, stats = extract_all_modpack_recipes(modpack_dir, args.max_width, args.max_height)

    print("=== Create Recipe Extraction Summary ===")
    print(f"Modpack dir           : {modpack_dir}")
    print(f"JAR files scanned     : {stats['jars_scanned']}")
    print(f"ZIP datapacks         : {stats['archives_scanned']}")

    if args.type in ("all", "mechanical"):
        mech_path = Path(args.output)
        mech_path.parent.mkdir(parents=True, exist_ok=True)
        mech_text = format_lua_db(mech_db)
        mech_path.write_text(mech_text, encoding="utf-8")
        print(f"Mechanical exported   : {len(mech_db)} -> {mech_path} ({len(mech_text.encode('utf-8'))} bytes)")
        print(f"Mechanical oversized  : {len(stats['skipped_oversized'])}")
        for rid, reason in stats["skipped_oversized"][:5]:
            print(f"  [SKIP OVERSIZED] {rid} ({reason})")

    if args.type in ("all", "sequenced"):
        seq_output = args.output if (args.type == "sequenced" and args.output != "data/crafter_recipes_default.db") else args.sequenced_output
        seq_path = Path(seq_output)
        seq_path.parent.mkdir(parents=True, exist_ok=True)
        seq_text = format_lua_db(seq_db)
        seq_path.write_text(seq_text, encoding="utf-8")
        print(f"Sequenced exported    : {len(seq_db)} -> {seq_path} ({len(seq_text.encode('utf-8'))} bytes)")
        print(f"Sequenced unsupported : {len(stats['skipped_unsupported_seq'])}")
        for rid, reason in stats["skipped_unsupported_seq"][:5]:
            print(f"  [SKIP UNSUPPORTED] {rid} ({reason})")

    for w in stats["warnings"]:
        print(f"  [WARN] {w}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
