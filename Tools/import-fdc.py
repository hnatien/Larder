#!/usr/bin/env python3
"""Rewrite the seed foods' nutrients from USDA FoodData Central (CC0), following Tools/fdc-mapping.json.

Run: python3 -I Tools/import-fdc.py --foundation <Foundation Foods JSON> --sr-legacy <SR Legacy JSON>

Each mapped food gets per100g from its FDC record, source fdcFoundation or srLegacy, and fdcId. Every nutrient
key is written, with null where FDC has no value. Slug, name, food group, tags, allergens, portions and density
stay as the seed has them unless the mapping overrides portions. Unmatched foods are left untouched.

Nutrient IDs, first present wins:
- energy: 1008 (Energy, kcal), the only energy SR Legacy has. Many Foundation foods lack it; for those, 2048
  (Atwater Specific Factors) comes before 2047 (Atwater General Factors), because SR Legacy's 1008 was computed
  with specific factors and the general 4-9-4 factors overstate nuts by about 7% and leafy vegetables by up
  to 25%.
- fat: 1004 (Total lipid), then 1085 (Total fat, NLEA). Carbohydrate: 1005 (by difference), then 1050 (by
  summation). Fibre: 1079, then 2033 (AOAC 2011.25). Total sugars: 2000, then 1063.
- added sugars (1235) is in neither dataset, so addedSugarG is always null.
A negative amount (carbohydrate by difference can come out below zero) is written as 0 and reported.
"""
import argparse
import json
import math
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SEED_FOODS = ROOT / "App" / "Larder" / "Resources" / "Seed" / "seed-foods.json"
MAPPING = ROOT / "Tools" / "fdc-mapping.json"

DATASETS = {
    "foundation": {"root": "FoundationFoods", "dataType": "Foundation", "source": "fdcFoundation"},
    "srLegacy": {"root": "SRLegacyFoods", "dataType": "SR Legacy", "source": "srLegacy"},
}
# Seed nutrient key to (FDC nutrient IDs in order of preference, unit).
NUTRIENTS = {
    "energyKcal": ((1008, 2048, 2047), "kcal"),
    "proteinG": ((1003,), "g"),
    "fatG": ((1004, 1085), "g"),
    "saturatedFatG": ((1258,), "g"),
    "monounsaturatedFatG": ((1292,), "g"),
    "polyunsaturatedFatG": ((1293,), "g"),
    "carbohydrateG": ((1005, 1050), "g"),
    "fiberG": ((1079, 2033), "g"),
    "totalSugarG": ((2000, 1063), "g"),
    "addedSugarG": ((1235,), "g"),
    "sodiumMg": ((1093,), "mg"),
    "potassiumMg": ((1092,), "mg"),
    "calciumMg": ((1087,), "mg"),
    "ironMg": ((1089,), "mg"),
    "vitaminDMcg": ((1114,), "µg"),
    "vitaminB12Mcg": ((1178,), "µg"),
}
# Nutrients the planner scores; a mapped food missing one is listed in the summary.
PLANNER = ("energyKcal", "proteinG", "fatG", "saturatedFatG", "carbohydrateG", "fiberG", "sodiumMg", "potassiumMg")


class FDCImportError(Exception):
    pass


def is_number(v):
    """A finite JSON number; Python's json module also accepts NaN and Infinity."""
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)


def tidy(v):
    """Integral floats as ints, so 40.0 is written as 40 like the rest of the seed."""
    return int(v) if isinstance(v, float) and v.is_integer() else v


def read_json(path, what):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, json.JSONDecodeError) as e:
        raise FDCImportError(f"cannot read {what} {path}: {e}")


def load_mapping(seed_slugs):
    data = read_json(MAPPING, "mapping")
    entries = data.get("foods") if isinstance(data, dict) else None
    if not isinstance(entries, list):
        raise FDCImportError("mapping: expected an object with a 'foods' list")
    mapping = {}
    for entry in entries:
        slug = entry.get("slug") if isinstance(entry, dict) else None
        if not isinstance(slug, str):
            raise FDCImportError(f"mapping: entry without a slug: {entry!r}")
        if slug in mapping:
            raise FDCImportError(f"mapping: {slug} appears more than once")
        if "unmatched" in entry:
            if not isinstance(entry["unmatched"], str) or not entry["unmatched"] or "dataset" in entry:
                raise FDCImportError(f"mapping: {slug} needs a non-empty unmatched reason and no dataset")
        else:
            if entry.get("dataset") not in DATASETS:
                raise FDCImportError(f"mapping: {slug} has unknown dataset {entry.get('dataset')!r}")
            fdc_id = entry.get("fdcId")
            if isinstance(fdc_id, bool) or not isinstance(fdc_id, int) or fdc_id <= 0:
                raise FDCImportError(f"mapping: {slug} fdcId must be a positive integer")
            if not isinstance(entry.get("description"), str):
                raise FDCImportError(f"mapping: {slug} needs FDC's description")
        mapping[slug] = entry
    missing = [s for s in seed_slugs if s not in mapping]
    unknown = sorted(set(mapping) - set(seed_slugs))
    if missing or unknown:
        raise FDCImportError(f"mapping: seed foods without an entry {missing}, entries without a seed food {unknown}")
    return mapping


def load_records(path, dataset, wanted):
    """The records of `dataset` whose fdcId is in `wanted`, keyed by fdcId, plus a count of non-object entries."""
    spec = DATASETS[dataset]
    data = read_json(path, dataset)
    foods = data.get(spec["root"]) if isinstance(data, dict) else None
    if not isinstance(foods, list):
        raise FDCImportError(f"{path}: expected an object with a '{spec['root']}' list")
    records, skipped = {}, 0
    for food in foods:
        if not isinstance(food, dict):
            skipped += 1
            continue
        fdc_id = food.get("fdcId")
        if isinstance(fdc_id, int) and fdc_id in wanted:
            if food.get("dataType") != spec["dataType"]:
                raise FDCImportError(f"{path}: fdcId {fdc_id} has dataType {food.get('dataType')!r}")
            if fdc_id in records:
                raise FDCImportError(f"{path}: fdcId {fdc_id} appears more than once")
            records[fdc_id] = food
    return records, skipped


def amounts(record):
    """FDC nutrient ID to (amount, unit) for one record."""
    out = {}
    for fn in record.get("foodNutrients") or []:
        nutrient = fn.get("nutrient") if isinstance(fn, dict) else None
        if isinstance(nutrient, dict) and isinstance(nutrient.get("id"), int) and is_number(fn.get("amount")):
            out[nutrient["id"]] = (fn["amount"], nutrient.get("unitName"))
    return out


def per100g(slug, record, clamped, energy_ids):
    found = amounts(record)
    per = {}
    for key, (ids, unit) in NUTRIENTS.items():
        value = None
        for nid in ids:
            if nid in found:
                amount, got_unit = found[nid]
                if got_unit != unit:
                    raise FDCImportError(f"{slug}: nutrient {nid} is in {got_unit!r}, expected {unit!r}")
                if amount < 0:
                    clamped.append(f"{slug} {key} {amount} -> 0")
                    amount = 0
                value = tidy(amount)
                if key == "energyKcal":
                    energy_ids[slug] = nid
                break
        per[key] = value
    if per["energyKcal"] is None:
        raise FDCImportError(f"{slug}: FDC {record['fdcId']} has no energy value; map it to another record")
    return per


def write_atomically(path, text):
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".seed-foods.", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.replace(tmp, path)
    except BaseException:
        os.unlink(tmp)
        raise


def run(args):
    seed = read_json(SEED_FOODS, "seed")
    foods = seed.get("foods") if isinstance(seed, dict) else None
    if not isinstance(foods, list) or not all(isinstance(f, dict) and "slug" in f for f in foods):
        raise FDCImportError(f"{SEED_FOODS}: expected an object with a 'foods' list of objects with slugs")
    mapping = load_mapping([f["slug"] for f in foods])

    paths = {"foundation": args.foundation, "srLegacy": args.sr_legacy}
    records = {}
    for dataset, path in paths.items():
        wanted = {e["fdcId"] for e in mapping.values() if e.get("dataset") == dataset}
        found, skipped = load_records(path, dataset, wanted)
        if skipped:
            print(f"{dataset}: skipped {skipped} entries that are not food objects")
        for e in mapping.values():
            if e.get("dataset") != dataset:
                continue
            record = found.get(e["fdcId"])
            if record is None:
                raise FDCImportError(f"{e['slug']}: fdcId {e['fdcId']} is not in the {dataset} data ({path})")
            if record.get("description") != e["description"]:
                raise FDCImportError(f"{e['slug']}: fdcId {e['fdcId']} is {record.get('description')!r}, "
                                   f"mapping says {e['description']!r}")
            records[e["slug"]] = record

    clamped, energy_ids, deltas, gaps, overrides = [], {}, [], [], []
    for food in foods:
        slug, entry = food["slug"], mapping[food["slug"]]
        if "unmatched" in entry:
            if food.get("source") != "seedApproximate" or "fdcId" in food:
                raise FDCImportError(f"{slug}: unmatched in the mapping but the seed holds FDC data; "
                                   "restore its approximate values from git first")
            continue
        old_kcal = food.get("per100g", {}).get("energyKcal")
        food["per100g"] = per100g(slug, records[slug], clamped, energy_ids)
        food["source"] = DATASETS[entry["dataset"]]["source"]
        food["fdcId"] = entry["fdcId"]
        for key in ("portions", "densityGPerMl"):
            if key in entry and food.get(key) != entry[key]:
                food[key] = entry[key]
                overrides.append(f"{slug} {key}")
        if is_number(old_kcal):
            deltas.append((food["per100g"]["energyKcal"] - old_kcal, slug, old_kcal, food["per100g"]["energyKcal"]))
        missing = [k for k in PLANNER if food["per100g"][k] is None]
        if missing:
            gaps.append(f"{slug}: {', '.join(missing)}")

    write_atomically(SEED_FOODS, json.dumps(seed, indent=2, sort_keys=True, ensure_ascii=False) + "\n")

    counts = {d: sum(1 for e in mapping.values() if e.get("dataset") == d) for d in DATASETS}
    unmatched = [(s, e["unmatched"]) for s, e in mapping.items() if "unmatched" in e]
    print(f"wrote {SEED_FOODS.relative_to(ROOT)}")
    print(f"matched: foundation {counts['foundation']}, srLegacy {counts['srLegacy']}; unmatched {len(unmatched)}")
    for slug, reason in unmatched:
        print(f"  unmatched {slug}: {reason}")
    used = {nid: sum(1 for v in energy_ids.values() if v == nid) for nid in NUTRIENTS["energyKcal"][0]}
    print("energy from nutrient", ", ".join(f"{nid}: {n}" for nid, n in used.items()))
    print(f"planner nutrients FDC leaves null ({len(gaps)} foods):")
    for line in gaps:
        print(f"  {line}")
    print("negative amounts written as 0:", "; ".join(clamped) if clamped else "none")
    print("portion overrides:", ", ".join(overrides) if overrides else "none")
    print("biggest energy changes vs the previous file (kcal per 100 g):")
    for delta, slug, old, new in sorted(deltas, key=lambda d: (-abs(d[0]), d[1]))[:12]:
        print(f"  {slug}: {old} -> {new} ({delta:+.1f})")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--foundation", required=True, type=Path, help="FDC Foundation Foods JSON")
    parser.add_argument("--sr-legacy", required=True, type=Path, help="FDC SR Legacy JSON")
    try:
        run(parser.parse_args())
    except FDCImportError as e:
        print(f"import-fdc: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
