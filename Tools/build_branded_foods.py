#!/usr/bin/env python3
"""Build the barcode bundle: USDA FoodData Central's branded foods, compacted.

In-house programme, project 2 (LIFT superproject,
`docs/superpowers/specs/2026-10-29-in-house-project-2-design.md`). LIFT
Android, LIFT iPhone and LIFT web look a scanned barcode up in this file and
search its product names, instead of asking Open Food Facts. Coach never
scans, so no Coach build carries it, and it is not in `LiftReference`.

The file is never committed anywhere -- not here, not in an app repo. It is a
release asset of this repository, and each app pins `branded-foods.json` (the
manifest this script writes beside it), which says where the asset is and what
its bytes hash to. See `data/README.md`, "Branded foods".

INPUT
-----
USDA's branded-food CSV download, `FoodData_Central_branded_food_csv_<date>.zip`
(public domain, CC0 1.0), given as the zip itself -- read in place, never
unpacked -- or as a directory holding its CSVs. Four files are read, by
column name, so a column USDA adds or reorders changes nothing:

  nutrient.csv        checked: every nutrient id below must still mean what it
                      meant, or the build stops rather than store sugar as fat
  food.csv            fdc_id, data_type, description (the product's name)
  branded_food.csv    fdc_id, brand_owner, brand_name, gtin_upc, serving_size,
                      serving_size_unit, modified_date, available_date,
                      discontinued_date
  food_nutrient.csv   fdc_id, nutrient_id, amount -- per 100 g, or per 100 ml
                      when the serving is in millilitres

WHAT IS KEPT
------------
One product per barcode, read the way every LIFT build reads a scan:

1. **A code that could never come off a real scan is dropped**: anything but
   digits (spaces and dashes aside), fewer than 8 or more than 14 digits, all
   zeros, or a GS1 check digit that fails. 9 to 11 digits are accepted as a
   GTIN whose leading zeros USDA's source already dropped; left-padding with
   zeros changes no check digit, so this needs no guess. An 8-digit code is
   EAN-8, as LIFT reads a typed one: only the scanner knows a UPC-E, and the
   report counts the 8-digit codes that would have passed as one.
2. **Leading zeros are stripped**, so UPC-A, EAN-13 and GTIN-14 spellings of a
   product are one integer key.
3. **The newest record speaks for a code** (available date, then modified
   date, then fdc_id). If it says discontinued, the code is out.
4. Otherwise the newest record that is **not discontinued and carries all of
   calories, protein, carbohydrate and fat** wins. None does: the code is out,
   because a bundle cannot serve a product without them any better than a
   lookup could.

A negative or unreadable amount is unknown, never zero. Nothing is invented:
USDA's figure is stored as it is, rounded to a tenth.

OUTPUT (in --out, default .build/branded-foods/)
------
  branded-foods-<YYYY-MM>.<n>.db      the database the apps open
  branded-foods-<YYYY-MM>.<n>.db.gz   the release asset (gzip, mtime 0)
  branded-foods.json                  the manifest the apps pin

The same input and the same SQLite give the same bytes. A different SQLite may
lay pages out differently, so the manifest also carries `rowsSha256`, a digest
of the rows themselves, which any build of the same data reproduces.

Usage (stdlib only; run isolated, because the input is downloaded data):
  python3 -I Tools/build_branded_foods.py FoodData_Central_branded_food_csv_2026-04-30.zip
  python3 -I Tools/build_branded_foods.py DIR --released 2026-04-30 [--build 2] [--out DIR]
"""
from __future__ import annotations

import argparse
import csv
import gzip
import hashlib
import io
import json
import re
import shutil
import sqlite3
import sys
import tempfile
import zipfile
from decimal import ROUND_HALF_UP, Decimal, InvalidOperation
from pathlib import Path

FORMAT = 1
REPO = "dougray/dugcanlift-kit"
SOURCE = "USDA FoodData Central, Branded Foods"
LICENSE = "CC0 1.0 Universal (public domain)"
# "LIFT" in ASCII, so an app can tell this file from any other SQLite file.
APPLICATION_ID = 0x4C494654

# Column -> (USDA nutrient id, the name and unit nutrient.csv must give it).
NUTRIENTS = {
    "kcal": (1008, "Energy", "KCAL"),
    "protein": (1003, "Protein", "G"),
    "carbs": (1005, "Carbohydrate, by difference", "G"),
    "fat": (1004, "Total lipid (fat)", "G"),
    "fiber": (1079, "Fiber, total dietary", "G"),
    # Named "Sugars, total including NLEA" in older releases; "Total Sugars"
    # in 2026-04-30's, with the same nutrient_nbr (269), so the same nutrient.
    "sugar": (2000, "Total Sugars", "G"),
    "satfat": (1258, "Fatty acids, total saturated", "G"),
    "sodium": (1093, "Sodium, Na", "MG"),
}
COLUMNS = list(NUTRIENTS)
CORE = ("kcal", "protein", "carbs", "fat")
BY_ID = {nid: col for col, (nid, _, _) in NUTRIENTS.items()}

GRAMS = {"g", "grm", "gm", "gram", "grams"}
MILLILITRES = {"ml", "mlt"}

SCHEMA = """
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
CREATE TABLE brands (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
CREATE TABLE products (
    code    INTEGER PRIMARY KEY,
    name    TEXT NOT NULL,
    brand   INTEGER REFERENCES brands(id),
    kcal    INTEGER NOT NULL,
    protein INTEGER NOT NULL,
    carbs   INTEGER NOT NULL,
    fat     INTEGER NOT NULL,
    fiber   INTEGER,
    sugar   INTEGER,
    satfat  INTEGER,
    sodium  INTEGER,
    serving INTEGER,
    ml      INTEGER NOT NULL DEFAULT 0
);
CREATE VIRTUAL TABLE search USING fts5(
    text, content='', detail=none, tokenize='unicode61 remove_diacritics 2'
);
"""

NEEDED = {
    "nutrient.csv": ("id", "name", "unit_name"),
    "food.csv": ("fdc_id", "data_type", "description"),
    "branded_food.csv": ("fdc_id", "brand_owner", "brand_name", "gtin_upc",
                         "serving_size", "serving_size_unit", "modified_date",
                         "available_date", "discontinued_date"),
    "food_nutrient.csv": ("fdc_id", "nutrient_id", "amount"),
}


class BuildError(Exception):
    """The input is not what this builder was written against. Stop, loudly."""


# --- Reading a barcode --------------------------------------------------------

def check_digit_ok(digits: str) -> bool:
    """GS1: weights 3, 1, 3, ... from the digit left of the check digit.
    The same for every GTIN length, and unchanged by leading zeros."""
    body, check = digits[:-1], int(digits[-1])
    total = sum(int(d) * (3 if i % 2 == 0 else 1) for i, d in enumerate(reversed(body)))
    return (10 - total % 10) % 10 == check


def expand_upce(code: str) -> str | None:
    """UPC-E to UPC-A, as LIFT iPhone's `Barcode.expandUPCE`. Report only."""
    if len(code) != 8 or code[0] not in "01":
        return None
    ns, m, check = code[0], code[1:7], code[7]
    last = m[5]
    if last in "012":
        body = m[0] + m[1] + last + "0000" + m[2] + m[3] + m[4]
    elif last == "3":
        body = m[0] + m[1] + m[2] + "00000" + m[3] + m[4]
    elif last == "4":
        body = m[0] + m[1] + m[2] + m[3] + "00000" + m[4]
    else:
        body = m[0] + m[1] + m[2] + m[3] + m[4] + "0000" + last
    return ns + body + check


def read_code(raw: str | None) -> tuple[str | None, str | None]:
    """(normalised digits, None) or (None, why not).

    Why not is one of: "none", "malformed", "length", "zeros", "check".
    Spaces and dashes are ignored; any other character -- a letter, a sign,
    a digit outside ASCII 0-9 -- fails the code, as it fails a scan.
    """
    if raw is None or not raw.strip():
        return None, "none"
    digits = []
    for ch in raw:
        if ch.isspace() or ch == "-":
            continue
        if ch not in "0123456789":
            return None, "malformed"
        digits.append(ch)
    code = "".join(digits)
    if not 8 <= len(code) <= 14:
        return None, "length"
    if code.strip("0") == "":
        return None, "zeros"
    if not check_digit_ok(code):
        return None, "check"
    return code.lstrip("0"), None


# --- Reading USDA's values ----------------------------------------------------

def tenths(text: str | None) -> int | None:
    """A non-negative decimal as whole tenths, half up; anything else unknown."""
    if text is None or not text.strip():
        return None
    try:
        value = Decimal(text.strip())
    except InvalidOperation:
        return None
    if not value.is_finite() or value < 0:
        return None
    return int((value * 10).quantize(Decimal(1), rounding=ROUND_HALF_UP))


def iso_date(text: str | None) -> str:
    """YYYY-MM-DD, from that or from M/D/YYYY; empty (oldest) otherwise."""
    if not text:
        return ""
    text = text.strip()
    m = re.fullmatch(r"(\d{4})-(\d{2})-(\d{2})", text)
    if m:
        return text
    m = re.fullmatch(r"(\d{1,2})/(\d{1,2})/(\d{4})", text)
    if m:
        return f"{m.group(3)}-{int(m.group(1)):02d}-{int(m.group(2)):02d}"
    return ""


def tidy(text: str | None) -> str | None:
    """Whitespace collapsed and trimmed; empty is None. Case is USDA's."""
    if text is None:
        return None
    text = " ".join(text.split())
    return text or None


# --- Opening the input --------------------------------------------------------

class Source:
    """The USDA zip, read in place, or a directory of its CSVs."""

    def __init__(self, path: Path):
        self.path = path
        self.zip = zipfile.ZipFile(path) if path.is_file() else None
        if self.zip is None and not path.is_dir():
            raise BuildError(f"{path}: no such zip or directory")

    def rows(self, name: str):
        if self.zip is not None:
            members = [n for n in self.zip.namelist() if n.rsplit("/", 1)[-1] == name]
            if len(members) != 1:
                raise BuildError(f"{self.path.name}: expected one {name}, found {len(members)}")
            raw = self.zip.open(members[0])
        else:
            file = self.path / name
            if not file.is_file():
                raise BuildError(f"{self.path}: no {name}")
            raw = file.open("rb")
        with io.TextIOWrapper(raw, encoding="utf-8-sig", newline="") as text:
            reader = csv.DictReader(text)
            missing = [c for c in NEEDED[name] if c not in (reader.fieldnames or [])]
            if missing:
                raise BuildError(f"{name} has no {', '.join(missing)} column")
            yield from reader

    def digest(self) -> dict:
        """What was read: the zip's sha256, or each CSV's."""
        def sha(f) -> str:
            h = hashlib.sha256()
            for block in iter(lambda: f.read(1 << 20), b""):
                h.update(block)
            return h.hexdigest()
        if self.zip is not None:
            with self.path.open("rb") as f:
                return {"name": self.path.name, "sha256": sha(f)}
        files = {}
        for name in sorted(NEEDED):
            with (self.path / name).open("rb") as f:
                files[name] = sha(f)
        return {"name": self.path.name, "files": files}


def released_from(path: Path) -> str | None:
    m = re.search(r"(\d{4}-\d{2}-\d{2})", path.name)
    return m.group(1) if m else None


# --- The build ----------------------------------------------------------------

def check_nutrients(source: Source) -> None:
    seen = {}
    for row in source.rows("nutrient.csv"):
        try:
            seen[int(float(row["id"]))] = (row["name"].strip(), row["unit_name"].strip().upper())
        except ValueError:
            continue
    for col, (nid, name, unit) in NUTRIENTS.items():
        if seen.get(nid) != (name, unit):
            raise BuildError(
                f"nutrient {nid} should be {name!r} in {unit} ({col}); "
                f"nutrient.csv says {seen.get(nid)!r}. USDA has renumbered: "
                "fix NUTRIENTS before building")


def stage(source: Source, work: sqlite3.Connection, counts: dict) -> None:
    work.executescript("""
        CREATE TABLE food (fdc INTEGER PRIMARY KEY, name TEXT);
        CREATE TABLE rec (fdc INTEGER PRIMARY KEY, code INTEGER NOT NULL, name TEXT,
                          brand TEXT, avail TEXT, modified TEXT, disc INTEGER,
                          serving INTEGER, ml INTEGER);
        CREATE TABLE nut (fdc INTEGER, col TEXT, val INTEGER);
    """)
    work.executemany(
        "INSERT OR REPLACE INTO food VALUES (?, ?)",
        ((int(r["fdc_id"]), tidy(r["description"])) for r in source.rows("food.csv")
         if r["data_type"].strip() == "branded_food" and r["fdc_id"].strip().isdigit()))

    def records():
        for r in source.rows("branded_food.csv"):
            if not r["fdc_id"].strip().isdigit():
                continue
            counts["records"] += 1
            code, problem = read_code(r["gtin_upc"])
            if problem == "none":
                counts["noCode"] += 1
                continue
            if problem:
                counts["badCode"] += 1
                if problem == "zeros":
                    counts["allZeros"] += 1
                raw = "".join(ch for ch in r["gtin_upc"] if ch in "0123456789")
                if problem == "check" and len(raw) == 8:
                    full = expand_upce(raw)
                    if full and check_digit_ok(full):
                        counts["upceOnly"] += 1
                continue
            raw = "".join(ch for ch in r["gtin_upc"] if ch in "0123456789")
            if 9 <= len(raw) <= 11:
                counts["shortCodes"] += 1
            if len(raw) == 8:
                full = expand_upce(raw)
                if full and check_digit_ok(full):
                    counts["eanAndUpce"] += 1
            unit = (r["serving_size_unit"] or "").strip().lower()
            ml = 1 if unit in MILLILITRES else 0
            serving = tenths(r["serving_size"]) if unit in GRAMS or ml else None
            if unit and unit not in GRAMS and not ml:
                counts["otherServingUnit"] += 1
            yield (int(r["fdc_id"]), int(code), tidy(r["brand_name"]) or tidy(r["brand_owner"]),
                   iso_date(r["available_date"]), iso_date(r["modified_date"]),
                   1 if (r["discontinued_date"] or "").strip() else 0,
                   serving or None, ml)

    work.executemany(
        "INSERT OR REPLACE INTO rec (fdc, code, brand, avail, modified, disc, serving, ml) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)", records())
    work.execute("UPDATE rec SET name = (SELECT name FROM food WHERE food.fdc = rec.fdc)")

    def amounts():
        for r in source.rows("food_nutrient.csv"):
            try:
                col = BY_ID.get(int(float(r["nutrient_id"])))
            except ValueError:
                continue
            if col is not None and r["fdc_id"].strip().isdigit():
                yield int(r["fdc_id"]), col, tenths(r["amount"])

    work.executemany("INSERT INTO nut VALUES (?, ?, ?)", amounts())
    work.execute("CREATE INDEX nut_fdc ON nut (fdc)")


def choose(work: sqlite3.Connection, counts: dict) -> list[tuple]:
    """One winner per code, by the rules in the module docstring."""
    pivot = ", ".join(f"MAX(CASE WHEN n.col = '{c}' THEN n.val END)" for c in COLUMNS)
    rows = work.execute(f"""
        SELECT r.code, r.fdc, r.name, r.brand, r.disc, r.serving, r.ml, {pivot}
        FROM rec r LEFT JOIN nut n ON n.fdc = r.fdc
        GROUP BY r.fdc
        ORDER BY r.code, r.avail DESC, r.modified DESC, r.fdc DESC
    """)
    winners = []
    group: list[tuple] = []

    def settle(group):
        counts["codes"] += 1
        newest = group[0]
        if newest[4]:
            counts["discontinued"] += 1
            return
        unnamed = False
        for rec in group:
            values = dict(zip(COLUMNS, rec[7:]))
            if rec[4] or any(values[c] is None for c in CORE):
                continue
            if rec[2] is None:  # complete, but nothing to call it on a screen
                unnamed = True
                continue
            winners.append((rec[0], rec[2], rec[3], *[values[c] for c in COLUMNS], rec[5], rec[6]))
            counts["superseded"] += len(group) - 1
            return
        counts["noName" if unnamed else "missingMacro"] += 1

    for row in rows:
        if group and row[0] != group[0][0]:
            settle(group)
            group = []
        group.append(row)
    if group:
        settle(group)
    return winners


def rows_digest(winners: list[tuple]) -> str:
    """sha256 over the rows as text, brands by name: independent of SQLite's
    page layout and of brand ids, so any build of the same data reproduces it."""
    h = hashlib.sha256()
    for row in winners:
        h.update(("\t".join("" if v is None else str(v) for v in row) + "\n").encode("utf-8"))
    return h.hexdigest()


def write_db(path: Path, winners: list[tuple], meta: dict) -> int:
    brands = sorted({w[2] for w in winners if w[2] is not None})
    brand_id = {name: i for i, name in enumerate(brands, start=1)}
    staging = path.with_suffix(".staging")
    if staging.exists():
        staging.unlink()
    db = sqlite3.connect(staging)
    db.execute("PRAGMA page_size = 4096")
    db.execute("PRAGMA journal_mode = OFF")
    db.execute("PRAGMA synchronous = OFF")
    db.executescript(SCHEMA)
    db.executemany("INSERT INTO meta VALUES (?, ?)", sorted(meta.items()))
    db.executemany("INSERT INTO brands VALUES (?, ?)", ((i, n) for n, i in brand_id.items()))
    db.executemany(
        f"INSERT INTO products VALUES ({', '.join('?' * 13)})",
        ((w[0], w[1], brand_id.get(w[2]), *w[3:]) for w in winners))
    db.executemany(
        "INSERT INTO search (rowid, text) VALUES (?, ?)",
        ((w[0], w[1] if w[2] is None else f"{w[1]} {w[2]}") for w in winners))
    db.execute("INSERT INTO search (search) VALUES ('optimize')")
    db.execute(f"PRAGMA application_id = {APPLICATION_ID}")
    db.execute(f"PRAGMA user_version = {FORMAT}")
    db.commit()
    db.execute("VACUUM INTO ?", (str(path),))
    db.close()
    staging.unlink()
    return len(brands)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def build(source_path: Path, out: Path, released: str | None = None, build_number: int = 1,
          work_dir: Path | None = None) -> dict:
    released = released or released_from(source_path)
    if not released or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", released):
        raise BuildError("no release date: name the USDA zip as USDA does, or pass --released YYYY-MM-DD")
    if build_number < 1:
        raise BuildError("--build counts from 1")
    tag = f"branded-foods-{released[:7]}.{build_number}"
    stem = tag

    source = Source(source_path)
    check_nutrients(source)
    counts = dict.fromkeys(
        ("records", "noCode", "badCode", "allZeros", "upceOnly", "eanAndUpce", "shortCodes",
         "otherServingUnit", "codes", "discontinued", "missingMacro", "noName", "superseded"), 0)

    with tempfile.TemporaryDirectory(dir=work_dir) as tmp:
        work = sqlite3.connect(Path(tmp) / "staging.db")
        work.execute("PRAGMA journal_mode = OFF")
        work.execute("PRAGMA synchronous = OFF")
        stage(source, work, counts)
        winners = choose(work, counts)
        work.close()
    if not winners:
        raise BuildError("no products survived: this is not a branded-food download")

    out.mkdir(parents=True, exist_ok=True)
    db_path = out / f"{stem}.db"
    gz_path = out / f"{stem}.db.gz"
    for p in (db_path, gz_path):
        if p.exists():
            p.unlink()
    meta = {
        "format": str(FORMAT),
        "source": SOURCE,
        "license": LICENSE,
        "released": released,
        "release": tag,
        "products": str(len(winners)),
    }
    brands = write_db(db_path, winners, meta)

    with db_path.open("rb") as src, gz_path.open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, compresslevel=9, mtime=0) as gz:
            shutil.copyfileobj(src, gz, 1 << 20)

    manifest = {
        "format": FORMAT,
        "source": SOURCE,
        "license": LICENSE,
        "released": released,
        "release": tag,
        "url": f"https://github.com/{REPO}/releases/download/{tag}/{gz_path.name}",
        "gz": {"file": gz_path.name, "bytes": gz_path.stat().st_size, "sha256": sha256_file(gz_path)},
        "db": {"file": db_path.name, "bytes": db_path.stat().st_size, "sha256": sha256_file(db_path)},
        "rowsSha256": rows_digest(winners),
        "products": len(winners),
        "brands": brands,
        "counts": counts,
        "input": source.digest(),
        "builtWith": {"python": sys.version.split()[0], "sqlite": sqlite3.sqlite_version},
    }
    (out / "branded-foods.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest


def main(argv: list[str] | None = None) -> int:
    csv.field_size_limit(2 ** 31 - 1)  # ingredient lists run past csv's 128 KiB default
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("source", type=Path, help="the USDA zip, or a directory of its CSVs")
    parser.add_argument("--released", help="USDA's release date, YYYY-MM-DD (default: from the zip's name)")
    parser.add_argument("--build", type=int, default=1,
                        help="rebuild number for the same USDA release (default 1); never reuse one")
    parser.add_argument("--out", type=Path, default=Path(".build/branded-foods"))
    parser.add_argument("--work", type=Path, help="where the staging database goes (default: system temp)")
    args = parser.parse_args(argv)
    try:
        m = build(args.source, args.out, args.released, args.build, args.work)
    except BuildError as e:
        print(f"build_branded_foods: {e}", file=sys.stderr)
        return 2
    c = m["counts"]
    print(f"{m['release']}: {m['products']:,} products, {m['brands']:,} brands, from {c['records']:,} records")
    print(f"  dropped codes: {c['discontinued']:,} discontinued, {c['missingMacro']:,} missing a core macro, "
          f"{c['noName']:,} with no name")
    print(f"  dropped records: {c['noCode']:,} with no code, {c['badCode']:,} with a code no scan could give "
          f"({c['allZeros']:,} all zeros, {c['upceOnly']:,} valid only as UPC-E), "
          f"{c['superseded']:,} superseded by a newer record")
    print(f"  kept, worth a look: {c['shortCodes']:,} codes of 9-11 digits, "
          f"{c['eanAndUpce']:,} 8-digit codes valid as both EAN-8 and UPC-E, "
          f"{c['otherServingUnit']:,} servings in neither g nor ml")
    print(f"  {m['db']['file']}: {m['db']['bytes']:,} bytes; {m['gz']['file']}: {m['gz']['bytes']:,} bytes")
    print(f"  wrote {args.out / 'branded-foods.json'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
