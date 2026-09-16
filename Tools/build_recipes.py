#!/usr/bin/env python3
"""Build `recipes.db`, the bundled starter catalogue for COOK.

Run from the package root:

    python3 Tools/build_recipes.py

Not shipped, and not run at build time. `recipes.db` is a checked-in artefact
the same way `food.db` and `exercises.db` are: static data, replaced wholesale
by rerunning this, never migrated.

TWO SOURCES, ONE FILE, LICENSE RECORDED PER ROW
-----------------------------------------------
`ReferenceDatabase`'s own rule is that `food.db` and `exercises.db` are never
joined, because ODbL and CC-BY-SA 3.0 are *mutually incompatible* share-alikes
and separate files keep each obligation scoped to its own file.

That rule does not force a split here, because these two licenses are not in
conflict: public-domain text can be combined into a CC BY-SA 4.0 work, and the
combination is simply BY-SA. Keeping one file therefore costs nothing legally
and halves the API. What it must not cost is traceability, so every row
carries its own `license` and `attribution` and the public-domain rows stay
individually identifiable as public domain.

The file as distributed is CC BY-SA 4.0 overall, because it contains BY-SA
rows. LIFT and Coach are AGPL-3.0, so share-alike is already the house rule.

NUTRITION
---------
UniTools publishes per-serving macros, so those are carried across verbatim.

Gutenberg recipes have none, and this script does **not** invent any. Costing
them would mean converting "1/2 cup sugar" to grams, and the bundled `food.db`
carries no USDA household-measure weights at all (`servingGrams` is null for
all 7,928 rows), so a gram figure would have to come from a density this
script made up. `IngredientParser` refuses exactly that, for exactly the
reason stated in its own doc comment: a confident wrong calorie count is worse
than a visible gap. Only lines already written in a weight unit are costed,
and each recipe records how many of its lines that covered.
"""

from __future__ import annotations

import json
import os
import re
import sqlite3
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Sources" / "LiftReference" / "Resources"
FOOD_DB = RESOURCES / "food.db"
OUT_DB = RESOURCES / "recipes.db"
DATA = ROOT / "Tools" / "data"

# Grams per unit, copied from `IngredientParser.gramsPerUnit`. Weight units
# only -- volume is deliberately absent there and must stay absent here, or
# the two disagree about what a line means.
GRAMS_PER_UNIT = {"g": 1.0, "kg": 1000.0, "mg": 0.001,
                  "oz": 28.3495, "lb": 453.592, "lbs": 453.592}

# Units `IngredientParser` recognises. Anything else leaves the line unparsed,
# which is a visible gap rather than a guess.
KNOWN_UNITS = {
    "g", "kg", "mg", "ml", "l",
    "tsp", "tbsp", "cup", "cups", "oz", "lb", "lbs",
    "clove", "cloves", "slice", "slices", "scoop", "scoops",
    "can", "cans", "pinch", "handful",
}


# --------------------------------------------------------------------------
# UniTools
# --------------------------------------------------------------------------

# UniTools unit tokens -> what a person writes on an ingredient line. Only
# renames; nothing here changes a quantity.
UNITOOLS_UNITS = {
    "g": "g", "kg": "kg", "mg": "mg", "ml": "ml", "l": "l",
    "tbsp": "tbsp", "tsp": "tsp", "cup": "cup", "clove": "clove",
    "slice": "slice", "pinch": "pinch", "sprig": "sprig",
    # A count. Written bare -- "2 eggs", never "2 piece eggs" -- which is the
    # same thing `IngredientParser.countUnit` exists to represent.
    "piece": "",
    # Not a measurement. Left off the front of the line entirely so the parser
    # sees an unquantified ingredient rather than a fake number.
    "toTaste": "",
}


def unitools_line(ing: dict) -> str:
    """One ingredient as a person would write it."""
    name = (ing.get("name") or {}).get("en") or ing.get("id") or ""
    name = name.strip()
    qty = ing.get("quantity")
    unit = UNITOOLS_UNITS.get(ing.get("unit") or "", "")

    if ing.get("unit") == "toTaste" or qty in (None, 0):
        line = name
    elif unit:
        line = f"{trim_number(qty)} {unit} {name}"
    else:
        line = f"{trim_number(qty)} {name}"

    note = (ing.get("note") or {}).get("en") if isinstance(ing.get("note"), dict) else None
    if note:
        line = f"{line}, {note.strip()}"
    return re.sub(r"\s+", " ", line).strip()


def load_unitools(path: Path) -> list[dict]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    license_ = payload.get("license", "CC BY-SA 4.0")
    attribution = payload.get("attribution", "UniTools — theunitools.com")
    out = []

    for r in payload.get("recipes", []):
        name = (r.get("name") or {}).get("en")
        if not name:
            continue
        n = r.get("nutritionPerServing") or {}
        steps = [s["text"]["en"].strip()
                 for s in (r.get("steps") or [])
                 if isinstance(s.get("text"), dict) and s["text"].get("en")]

        out.append({
            "id": f"unitools:{r['slug']}",
            "name": name.strip(),
            "summary": ((r.get("summary") or {}).get("en") or "").strip() or None,
            "country": r.get("country"),
            "category": r.get("category"),
            "servings": float(r.get("baseServings") or 1),
            "prepMinutes": r.get("prepMinutes"),
            "cookMinutes": r.get("cookMinutes"),
            "calories": n.get("calories"),
            "protein": n.get("protein"),
            "carbs": n.get("carbs"),
            "fat": n.get("fat"),
            # The publisher measured the dish; we did not resolve it against a
            # food database, so it is still an estimate by `Recipe`'s own
            # definition of that flag.
            "estimated": 1,
            "nutritionNote": None,
            "steps": steps,
            "ingredients": [unitools_line(i) for i in (r.get("ingredients") or [])],
            "source": "unitools",
            "license": license_,
            "attribution": attribution,
            "sourceURL": f"https://theunitools.com/recipes/{r['slug']}",
        })
    return out


# --------------------------------------------------------------------------
# Project Gutenberg
# --------------------------------------------------------------------------

# Archaic and abbreviated measures, expanded to what `IngredientParser` reads.
# Expansions only: every replacement means the same thing the book meant.
MODERNISE = [
    (r"\btblsp\.?\b", "tbsp"), (r"\btbsp\.\B", "tbsp"),
    (r"\btablespoonfuls?\b", "tbsp"), (r"\btablespoons?\b", "tbsp"),
    (r"\bteasp\.?\b", "tsp"), (r"\bteaspoonfuls?\b", "tsp"),
    (r"\bteaspoons?\b", "tsp"),
    (r"\bcupfuls?\b", "cup"), (r"\bcups?\b", "cup"),
    (r"\bpounds?\b", "lb"), (r"\blbs?\.\B", "lb"),
    (r"\bounces?\b", "oz"), (r"\boz\.\B", "oz"),
    (r"\bquarts?\b", "quart"), (r"\bpints?\b", "pint"),
    (r"\bsaltspoonfuls?\b", "pinch"), (r"\bsaltspoons?\b", "pinch"),
]


def modernise(line: str) -> str:
    """Expand archaic measure words. Never changes a quantity."""
    text = unicodedata.normalize("NFKC", line).strip()
    # "1-1/2" is how these books write a mixed number; the parser reads
    # "1 1/2". Only touched between digits so a hyphenated word survives.
    text = re.sub(r"(?<=\d)-(?=\d/\d)", " ", text)
    for pattern, replacement in MODERNISE:
        text = re.sub(pattern, replacement, text, flags=re.IGNORECASE)
    return re.sub(r"\s+", " ", text).strip()


TITLE_RE = re.compile(r"^[A-Z][A-Z0-9 '\-\.,&()_]{3,60}$")


def parse_gutenberg(text: str, book: str, book_id: int) -> list[dict]:
    """Pull recipes out of a plain-text cookbook.

    The shape this reads is: a title in capitals, a blank line, a run of
    indented ingredient lines, a blank line, then the method in prose. Books
    that do not follow it yield nothing rather than garbage -- a recipe whose
    ingredients are actually a paragraph of prose is worse than no recipe.
    """
    body = text
    start = re.search(r"\*\*\* ?START OF TH[EIS]+ PROJECT GUTENBERG EBOOK.*?\*\*\*", body)
    end = re.search(r"\*\*\* ?END OF TH[EIS]+ PROJECT GUTENBERG EBOOK.*?\*\*\*", body)
    if start:
        body = body[start.end():]
    if end:
        body = body[:end.start()] if not start else body[:end.start() - start.end()]

    lines = body.replace("\r\n", "\n").split("\n")
    out: list[dict] = []
    i = 0
    while i < len(lines):
        title = lines[i].strip()
        if not TITLE_RE.match(title) or len(title.split()) > 8:
            i += 1
            continue
        # Italic markers appear as _and_ in these transcriptions.
        clean_title = re.sub(r"_", "", title).strip()

        j = i + 1
        while j < len(lines) and not lines[j].strip():
            j += 1

        ingredients: list[str] = []
        while j < len(lines) and lines[j].startswith("  ") and lines[j].strip():
            ingredients.append(modernise(lines[j]))
            j += 1

        # Fewer than two lines is a heading, a caption or a page artefact.
        if len(ingredients) < 2:
            i += 1
            continue

        while j < len(lines) and not lines[j].strip():
            j += 1
        method: list[str] = []
        while j < len(lines) and lines[j].strip() and not TITLE_RE.match(lines[j].strip()):
            method.append(lines[j].strip())
            j += 1
        if not method:
            i += 1
            continue

        out.append({
            "id": f"gutenberg-{book_id}:{slugify(clean_title)}",
            "name": titlecase(clean_title),
            "summary": None,
            "country": None,
            "category": None,
            # These books almost never state a yield, and a guessed one
            # divides every macro by a number nobody chose.
            "servings": None,
            "prepMinutes": None,
            "cookMinutes": None,
            "steps": [" ".join(method)],
            "ingredients": ingredients,
            "source": f"gutenberg-{book_id}",
            "license": "Public domain",
            "attribution": f"{book} (Project Gutenberg #{book_id})",
            "sourceURL": f"https://www.gutenberg.org/ebooks/{book_id}",
        })
        i = j
    return out


def titlecase(text: str) -> str:
    small = {"and", "or", "of", "with", "in", "a", "the", "for"}
    words = text.lower().split()
    return " ".join(w if i and w in small else w.capitalize() for i, w in enumerate(words))


def slugify(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")[:60]


# --------------------------------------------------------------------------
# Costing -- weight units only
# --------------------------------------------------------------------------

def parse_line(line: str) -> tuple[float | None, str | None, str | None]:
    """A deliberately small mirror of `IngredientParser.parse`."""
    m = re.match(r"^\s*(\d+\s+\d+/\d+|\d+/\d+|\d+(?:\.\d+)?)\s*(.*)$", line)
    if not m:
        return None, None, None
    raw_qty, rest = m.group(1), m.group(2)
    if " " in raw_qty:
        whole, frac = raw_qty.split()
        num, den = frac.split("/")
        qty = float(whole) + float(num) / float(den)
    elif "/" in raw_qty:
        num, den = raw_qty.split("/")
        qty = float(num) / float(den)
    else:
        qty = float(raw_qty)

    parts = rest.split(None, 1)
    unit = None
    if parts:
        candidate = parts[0].lower().strip(".,")
        if candidate in KNOWN_UNITS:
            unit = candidate
            rest = parts[1] if len(parts) > 1 else ""
    item = rest.split(",")[0].strip() or None
    return qty, unit, item


def cost(recipe: dict, food: sqlite3.Connection) -> None:
    """Fill in macros from weighable lines only, and record the coverage."""
    if recipe.get("calories") is not None:
        return

    totals = {"calories": 0.0, "protein": 0.0, "carbs": 0.0, "fat": 0.0}
    priced, unpriced = 0, []

    for line in recipe["ingredients"]:
        qty, unit, item = parse_line(line)
        grams = qty * GRAMS_PER_UNIT[unit] if (qty and unit in GRAMS_PER_UNIT) else None
        if grams is None or not item:
            unpriced.append(line)
            continue
        row = best_match(food, item)
        if not row:
            unpriced.append(line)
            continue
        f = grams / 100.0
        totals["calories"] += row[0] * f
        totals["protein"] += row[1] * f
        totals["carbs"] += row[2] * f
        totals["fat"] += row[3] * f
        priced += 1

    total_lines = len(recipe["ingredients"])
    if priced == 0:
        recipe["nutritionNote"] = (
            f"No macros: none of this recipe's {total_lines} ingredients is written in a "
            "weight, and converting a cup to grams would mean inventing a density.")
        return

    coverage = (f"Costed here from {priced} of {total_lines} ingredients; the rest are not "
                "written in a weight, so the figures are short by whatever those contribute."
                if unpriced else
                f"Costed here from all {total_lines} ingredients.")

    recipe["estimated"] = 1
    servings = recipe.get("servings")

    if servings:
        recipe["calories"] = round(totals["calories"] / servings, 1)
        recipe["protein"] = round(totals["protein"] / servings, 1)
        recipe["carbs"] = round(totals["carbs"] / servings, 1)
        recipe["fat"] = round(totals["fat"] / servings, 1)
        recipe["nutritionNote"] = coverage
        return

    # No stated yield. Publishing these as "per serving" would silently claim
    # the whole pot feeds one, so they are recorded as the whole dish and the
    # per-serving columns stay null until a reader says how many it feeds.
    recipe["caloriesTotal"] = round(totals["calories"], 1)
    recipe["proteinTotal"] = round(totals["protein"], 1)
    recipe["carbsTotal"] = round(totals["carbs"], 1)
    recipe["fatTotal"] = round(totals["fat"], 1)
    recipe["nutritionNote"] = (
        coverage + " The book states no yield, so these are for the whole dish: "
        "set how many it serves and the per-serving figures follow.")
    return


_MATCH_CACHE: dict[str, tuple | None] = {}


def best_match(food: sqlite3.Connection, item: str) -> tuple | None:
    key = item.lower()
    if key in _MATCH_CACHE:
        return _MATCH_CACHE[key]
    words = [w for w in re.findall(r"[a-z]+", key) if len(w) > 2]
    row = None
    if words:
        pattern = " ".join(f'"{w}"' for w in words)
        try:
            row = food.execute(
                "SELECT f.caloriesPer100g, f.proteinPer100g, f.carbsPer100g, f.fatPer100g "
                "FROM foods f JOIN foods_fts ON foods_fts.rowid = f.rowid "
                "WHERE foods_fts MATCH ? ORDER BY bm25(foods_fts), length(f.name) LIMIT 1",
                (pattern,)).fetchone()
        except sqlite3.OperationalError:
            row = None
    _MATCH_CACHE[key] = row
    return row


def trim_number(value) -> str:
    f = float(value)
    return str(int(f)) if f == int(f) else f"{f:g}"


# --------------------------------------------------------------------------
# Writing
# --------------------------------------------------------------------------

SCHEMA = """
CREATE TABLE recipes (
  id                  TEXT PRIMARY KEY,
  name                TEXT NOT NULL,
  summary             TEXT,
  country             TEXT,
  category            TEXT,
  servings            REAL,
  prepMinutes         INTEGER,
  cookMinutes         INTEGER,
  caloriesPerServing  REAL,
  proteinPerServing   REAL,
  carbsPerServing     REAL,
  fatPerServing       REAL,
  -- Whole finished dish. Used when a source states no yield, so a per-serving
  -- figure would have to be invented: the reader supplies the serving count on
  -- import and the division happens then, the same way the link importer asks.
  caloriesTotal       REAL,
  proteinTotal        REAL,
  carbsTotal          REAL,
  fatTotal            REAL,
  nutritionIsEstimated INTEGER NOT NULL DEFAULT 0,
  nutritionNote       TEXT,
  steps               TEXT NOT NULL,
  source              TEXT NOT NULL,
  license             TEXT NOT NULL,
  attribution         TEXT NOT NULL,
  sourceURL           TEXT
);

CREATE TABLE recipe_ingredients (
  recipeID  TEXT NOT NULL,
  sortOrder INTEGER NOT NULL,
  rawText   TEXT NOT NULL,
  PRIMARY KEY (recipeID, sortOrder)
);

CREATE VIRTUAL TABLE recipes_fts USING fts5(
  name, summary, country,
  content='recipes', content_rowid='rowid',
  tokenize='porter unicode61'
);
"""


def write(recipes: list[dict], out: Path) -> None:
    if out.exists():
        out.unlink()
    db = sqlite3.connect(out)
    db.executescript(SCHEMA)

    for r in recipes:
        db.execute(
            "INSERT INTO recipes VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (r["id"], r["name"], r.get("summary"), r.get("country"), r.get("category"),
             r.get("servings"), r.get("prepMinutes"), r.get("cookMinutes"),
             r.get("calories"), r.get("protein"), r.get("carbs"), r.get("fat"),
             r.get("caloriesTotal"), r.get("proteinTotal"),
             r.get("carbsTotal"), r.get("fatTotal"),
             r.get("estimated", 0), r.get("nutritionNote"),
             "\n".join(r["steps"]), r["source"], r["license"], r["attribution"],
             r.get("sourceURL")))
        for n, line in enumerate(r["ingredients"]):
            db.execute("INSERT INTO recipe_ingredients VALUES (?,?,?)", (r["id"], n, line))

    db.execute("INSERT INTO recipes_fts(recipes_fts) VALUES('rebuild')")
    db.commit()
    # VACUUM cannot run inside a transaction, and sqlite3 opens one implicitly
    # for the inserts above.
    db.isolation_level = None
    db.execute("VACUUM")
    db.close()


def main() -> int:
    if not FOOD_DB.exists():
        print(f"missing {FOOD_DB}", file=sys.stderr)
        return 1

    recipes: list[dict] = []

    unitools = DATA / "unitools-recipes-v1.json"
    if unitools.exists():
        got = load_unitools(unitools)
        print(f"UniTools:  {len(got)} recipes")
        recipes += got
    else:
        print(f"UniTools:  skipped (no {unitools})")

    for path in sorted(DATA.glob("gutenberg-*.txt")):
        book_id = int(re.search(r"gutenberg-(\d+)", path.name).group(1))
        title = path.stem.split("-", 2)[-1].replace("-", " ").title()
        got = parse_gutenberg(path.read_text(encoding="utf-8", errors="ignore"), title, book_id)
        print(f"Gutenberg #{book_id}: {len(got)} recipes ({title})")
        recipes += got

    if not recipes:
        print("nothing to build", file=sys.stderr)
        return 1

    food = sqlite3.connect(FOOD_DB)
    for r in recipes:
        r.setdefault("estimated", 0)
        cost(r, food)
    food.close()

    write(recipes, OUT_DB)

    with_macros = sum(1 for r in recipes if r.get("calories") is not None)
    print(f"\nwrote {OUT_DB.relative_to(ROOT)}  "
          f"{len(recipes)} recipes, {with_macros} with macros, "
          f"{os.path.getsize(OUT_DB) / 1024:.0f} KB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
