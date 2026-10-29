#!/usr/bin/env python3
"""Export `recipes.db` as `data/recipes.json`, for the builds that cannot open it.

The iPhone apps read the catalogue straight out of `LiftReference`'s SQLite
file. LIFT Android, Coach Android, LIFT web and Coach web bundle this JSON
instead, copied verbatim with `data/recipes.sha256` beside it, exactly as they
copy `road-food.json`. The database stays the one source: this file is derived
from it and never edited by hand.

Every column travels, under the database's own names, so a port never has to
go back to SQLite for a field. `ingredients` and `steps` are arrays in their
stored order. A null stays null -- in particular `servings`, which is null for
the recipes whose source states no yield: those carry whole-dish totals and the
reader supplies the serving count on import, the rule the iPhones hold.

`license` and `attribution` are per recipe and must be shown wherever a recipe
is shown. The file as a whole is CC BY-SA 4.0 (see `build_recipes.py`).

Usage:
  tools/export_recipes_json.py            write data/recipes.json and .sha256
  tools/export_recipes_json.py --check    exit 1 if either is out of date
"""
import hashlib
import json
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / "Sources/LiftReference/Resources/recipes.db"
OUT = ROOT / "data/recipes.json"
SUM = ROOT / "data/recipes.sha256"

COLUMNS = [
    "id", "name", "summary", "country", "category", "servings",
    "prepMinutes", "cookMinutes",
    "caloriesPerServing", "proteinPerServing", "carbsPerServing", "fatPerServing",
    "caloriesTotal", "proteinTotal", "carbsTotal", "fatTotal",
    "nutritionIsEstimated", "nutritionNote",
    "steps", "source", "license", "attribution", "sourceURL",
]


def export() -> bytes:
    db = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    ingredients: dict[str, list[str]] = {}
    for rid, text in db.execute(
            "SELECT recipeID, rawText FROM recipe_ingredients ORDER BY recipeID, sortOrder"):
        ingredients.setdefault(rid, []).append(text)

    recipes = []
    for row in db.execute(f"SELECT {', '.join(COLUMNS)} FROM recipes ORDER BY id"):
        r = dict(zip(COLUMNS, row))
        r["nutritionIsEstimated"] = bool(r["nutritionIsEstimated"])
        r["steps"] = [s for s in r["steps"].split("\n") if s.strip()]
        r["ingredients"] = ingredients.get(r["id"], [])
        recipes.append(r)
    db.close()

    doc = {
        "license": "CC BY-SA 4.0",
        "note": "Derived from LiftReference's recipes.db by tools/export_recipes_json.py. "
                "Never edit by hand. Show each recipe's own license and attribution.",
        "recipes": recipes,
    }
    return (json.dumps(doc, ensure_ascii=False, indent=1) + "\n").encode("utf-8")


def main() -> int:
    data = export()
    digest = hashlib.sha256(data).hexdigest() + "\n"
    if "--check" in sys.argv[1:]:
        stale = [p.name for p, want in ((OUT, data), (SUM, digest.encode()))
                 if not p.exists() or p.read_bytes() != want]
        if stale:
            print(f"out of date: {', '.join(stale)} -- run tools/export_recipes_json.py",
                  file=sys.stderr)
            return 1
        print(f"recipes.json matches recipes.db ({len(json.loads(data)['recipes'])} recipes)")
        return 0
    OUT.write_bytes(data)
    SUM.write_text(digest)
    print(f"wrote {OUT.relative_to(ROOT)} ({len(data):,} bytes) and {SUM.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
