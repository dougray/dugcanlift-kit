# Road Food data

| File | What it is |
|---|---|
| `road-food.json` | The bundled chains, items, snacks and rules the apps read. Edited by hand only. |
| `road-food.sha256` | The sha256 of `road-food.json`'s bytes. Written by the validator, never by hand. |
| `road-food-SOURCES.md` | Where every number came from, when, how it was read, and every doubt. |
| `validate-road-food.mjs` | Shape and honesty checks on the JSON. |
| `check-road-food.mjs` | The refresh check: have the chains' published numbers moved? |
| `check-road-food-lib.mjs` | The check's reading, comparing and reporting, with no network (tested). |
| `read-zip.mjs` | Streams one member out of a zip with Node's standard library, for USDA's Branded Foods file (tested). |
| `fixtures/fdc-branded/` | Hand-written CSVs in USDA's Branded Foods layout, and two zips of them, for the snack tests. |
| `road-food-locators.json` | Where each bundled item sits in its source: a PDF row, a grid row, a sales item id, a product number. |
| `road-food-CHECK.md` | The last check's report. Overwritten each run. |

## Published on

Each chain carries two dates, and they answer different questions.

| Field | Means | Shape |
|---|---|---|
| `checkedOn` | the day a person read the chain's chart | `YYYY-MM-DD`, always present |
| `publishedOn` | the date **the document states about itself** | `YYYY-MM-DD` or `YYYY-MM`, optional |

The apps' "these numbers are old" warning keys off `publishedOn` when a chain
has one and `checkedOn` when it does not, still at six calendar months. A
chain with no `publishedOn` therefore reads exactly as it did before this
field existed.

`publishedOn` is only ever as precise as the document is. Burger King's chart
prints "NOVEMBER 2022", so it is `2022-11`; Whataburger's prints "as of
March 29, 2021", so it is `2021-03-29`. A month-only date is read as the first
of that month everywhere it is compared, which can only make a document look
older, never fresher.

**It is what the document says in the text a reader can see**, because a reader
can open `source` and find it. Not the PDF's metadata: Popeyes' August 2026
guide is titled "Nutrition FEBRUARY 2023" in its file properties, and
Whataburger's file was created on 2021-02-02 but states 2021-03-29. Not the
server's `Last-Modified`, which is when the file was uploaded. Not the upload
path in the URL.

**A document that states no date has no key.** Never a guess, never the day it
was fetched. Eight of the nineteen chains are in this position and it is not a
gap to fill: Wendy's, Starbucks and Chick-fil-A publish live pages that say
nothing about themselves, the PDFs of QuikTrip, Love's and Pilot Flying J print
no date, Sonic's says only "SUMMER 2026" — a season is not a month, and `2026`
alone would be inventing the rest — and Jack in the Box's says "effective as of
November 2026", a month after it was read, which no `publishedOn` may be. `road-food-SOURCES.md` records what each document does say.

## Allergens

`allergenSource` (chain), `allergensCovered` (chain, optional) and `allergens`
(item, optional) record what the chain's own allergen chart says an item
**contains**. No key means not stated; `[]` means listed and none of what the
chart covers; an absent `allergensCovered` means the chart never says what it
covers, so an app must not clear an item of anything. Old app builds ignore all
three keys. The rules and the per-chain sources are in `road-food-SOURCES.md`
"Allergens".

## Validate

```sh
node data/validate-road-food.mjs
```

## The copies, and the checksum that holds them together

`road-food.json` is curated here and copied byte for byte into five app repos:

| Repo | Path |
|---|---|
| `dugcanlift-site` | `lift/road-food.json` |
| `dugcanlift-coach` | `coach/road-food.json` |
| `dugcanlift-lift` | `app/src/main/assets/road-food.json` |
| `lift-ios` | `Resources/road-food.json` |
| `coach-ios` | `Resources/road-food.json` |

(`dugcanlift-site/coach/road-food.json` is a sixth copy, but `deploy.sh` in
`dugcanlift-coach` writes it from that repo's copy; nobody edits it.)

Item ids are the contract a coach's road picks travel on, so a copy that has
quietly fallen behind is a real failure, not an untidiness — and one that
every app-side shape check passes, because a three-chains-behind file is
perfectly valid. All six copies match today — they were compared when this was
written — and the point is that nothing would say if they stopped.

So `road-food.sha256` travels with the file. Each app repo commits it beside
its copy and asserts, in the test suite its CI already runs, that the bytes it
actually bundles hash to it. The hash is one bare line of 64 hex characters
and nothing else, so node, Kotlin and Swift each read it back without a parser
and no path inside it can go stale.

### Changing the data

```sh
node data/validate-road-food.mjs --write-checksum
```

The validator refuses a `road-food.sha256` that no longer matches, so this is
a step you cannot skip and a hash nobody types by hand. It also refuses to
*write* one over a bundle that fails its own checks: a frozen hash over a
broken file would be copied into five repos that then all agree with it.

Then copy **both files together** into each repo above, and open a PR there.
Copying the JSON without the checksum fails that repo's tests, which is the
point.

## Refresh check

```sh
node data/check-road-food.mjs                    # fetches every chain's source, writes data/road-food-CHECK.md
node data/check-road-food.mjs --fdc-branded ~/Downloads/fdc/FoodData_Central_branded_food_csv_2026-10-29.zip
                                                 # the same, and the snacks too
node --test data/*.test.mjs                      # unit tests, no network
```

**No source needs an API key, and none may** (SOURCES.md, ground rules): a
key, even a free or "demo" one, is an outside dependency that can be cut off.

For each chain the check fetches the source SOURCES.md records, once, with a
User-Agent naming the tool and a pause between requests. It never retries, and
it never works around a refusal: a 403 is reported as "couldn't reach".
Where the source can be read by machine (PDF text, the JSON embedded in
Chick-fil-A's page, Wendy's and Starbucks' ordering APIs, the menu grid of the
calculator Taco Bell's and Sheetz's own pages embed, FoodData Central's bulk file) it
reads each bundled item back out and compares every number. For a chain whose
figures come from an embedded calculator it also re-reads the chain's own page
and confirms the embed is still there, because that embed is the whole reason
the widget's figures count as the chain's own. Where it can't
(QuikTrip's PDF, whose text interleaves rows), it reports whether the document
changed since `checkedOn`, and says "re-read by hand" when it did or when it
can't tell. It also gives each chain's `publishedOn`, how many months old that
document is, and whether the document still states that date at all — a
document that has stopped saying it has been republished, which is reported and
fails the run, because `publishedOn` is then wrong. It never reads a *new* date
out of a document: a wrong date read by machine is worse than a missing one a
person goes and looks up. It lists every chain or snack whose `checkedOn` is
more than six months old, and re-runs the validator.

**It never edits `road-food.json`.** A wrong number in someone's day is worse
than an old one they can see is old. When the check says a number moved, a
person re-reads the source, edits the file, updates `checkedOn`, and notes
anything odd in SOURCES.md.

Exit code: 1 if any source changed, couldn't be reached, or no longer states
its recorded `publishedOn`; 2 if only the validator failed; otherwise 0. "Can't compare automatically" does not fail,
so the check can run in CI without failing on QuikTrip every time.

Fetched documents are kept in `data/.road-food-cache/` (gitignored: they are
the chains' own files). The next run sends `If-None-Match` /
`If-Modified-Since` from there, and `--offline` re-checks the cached copies
without touching the network.

PDF text comes from PDFKit via `swift` on macOS, which is what the bundle was
curated with and what the row locators were written against. Elsewhere it falls
back to `pdftotext`, whose line breaks may differ: a "row not found" there is
worth a look on a Mac before believing it.

### Snacks: USDA's Branded Foods file

The snacks are checked against USDA FoodData Central's **Branded Foods bulk
download**, `FoodData_Central_branded_food_csv_<date>.zip`: public domain
(CC0), no account and no key. The check is given it as a local path, with
`--fdc-branded <zip>` or the `FDC_BRANDED_ZIP` environment variable. **It never
downloads the file itself**: it is about 430 MB zipped and 3 GB unzipped, and
fetching it is the one manual download of the quarterly refresh. With no file
given, the snacks are reported "can't compare automatically", with that reason,
and the run does not fail.

The zip is read in place and never unpacked: `read-zip.mjs` streams each CSV
out of it through Node's own `zlib`, with no dependency and no `unzip`, and
checks each member's CRC-32 as it goes. Four CSVs are read, by column name:
`nutrient.csv` (`id`, `nutrient_nbr`), `branded_food.csv` (`fdc_id`,
`gtin_upc`, `serving_size`, `serving_size_unit`, `discontinued_date`),
`food.csv` (`fdc_id`, `description`, `publication_date`) and
`food_nutrient.csv` (`fdc_id`, `nutrient_id`, `amount`, per 100 g). Those are
the names in USDA's "Download Field Descriptions", which ships inside each zip.
Every row is read, so a run takes a while longer with the file than without it.

For each snack the check finds its `fdcId`, re-derives the figures exactly as
before (per-100 g amount × serving, to one decimal, then FDA label rounding),
reports a `discontinued_date`, and looks for a **newer record of the same
product**: another record with the same GTIN (leading zeros ignored) and a later
`publication_date`, which is how USDA's field descriptions say an update shows
in the file. An `fdcId` the file no longer holds is reported as changed, with
any records the file does hold for the snack's barcode.

What the bulk file cannot do that the API did:

- **It is six months fresh, not one.** USDA publishes the Branded Foods download
  twice a year (April and October), and the API was updated monthly. A label
  resubmitted since the last release is not seen until the next one. Use the
  newest release; the report says so when the file is older than a snack's
  `checkedOn`.
- **"Newer record" means "same GTIN, later date".** The API's update log was
  FDC's own list of a product's history. The bulk file has no such list, so a
  resubmission under a different barcode is not linked to the old record.

### When a chain or item is added

Add its locator to `road-food-locators.json`, or the check reports the item
as "not compared". Run the check once: every number should match, because the
item was just read from the same source.

## Quarterly refresh

Once a quarter (January, April, July, October), and before any release that
ships the data:

1. **Download USDA's Branded Foods CSV zip**, the one manual download: on
   <https://fdc.nal.usda.gov/download-datasets/>, under "Branded", take the
   newest CSV release (`FoodData_Central_branded_food_csv_<date>.zip`, about
   430 MB). Put it in an empty directory of its own, outside the repo, and
   don't unzip it.
2. `node data/check-road-food.mjs --fdc-branded <that zip>`, then read
   `data/road-food-CHECK.md`.
3. **Changed:** open the source, confirm each old → new figure by eye, and
   update the item and the chain's `checkedOn`. An item that is gone from the
   source comes out of the file, or is replaced with one read the same way.
4. **Couldn't reach:** try the source in a browser. If the chain moved its
   document, find the new one on the chain's own site, update `source` and the
   locator, and record it in SOURCES.md. Don't bypass a block.
5. **Can't compare automatically:** re-read the document by hand when the
   report says it changed or can't tell. For QuikTrip, also confirm a
   quiktrip.com product page still links the recorded PDF: a new one would sit
   at a new address.
6. **Over six months:** re-read and re-date, even if nothing moved; the apps
   say so in words. Note that re-dating fixes `checkedOn` only: a chain whose
   *document* is old stays old however often it is read, and the warning is
   meant to keep saying so.
7. **Document date moved:** the check reports a chain whose document no longer
   states the date `publishedOn` records, which means the chain republished.
   Re-read the document and its date by hand, and update both fields.
8. `node data/validate-road-food.mjs --write-checksum`, then copy
   `road-food.json` and `road-food.sha256` into each app repo together and
   ship the change with the apps like any other.

# Recipe catalogue

| File | What it is |
|---|---|
| `recipes.json` | The 622-recipe starter catalogue, exported from `Sources/LiftReference/Resources/recipes.db`. Never edited by hand. |
| `recipes.sha256` | The sha256 of `recipes.json`'s bytes. Written by the exporter, never by hand. |

The iPhone apps read `recipes.db` through `LiftReference`. LIFT Android, Coach
Android, LIFT web and Coach web cannot, so they bundle `recipes.json` and pin
`recipes.sha256`, copied over together as `road-food.json` is. Rebuild the
database with `Tools/build_recipes.py`, then run
`Tools/export_recipes_json.py`. CI runs it with `--check`.

Each recipe carries its own `license` and `attribution` (501 CC BY-SA 4.0, 121
public domain), and every build shows them wherever it shows the recipe. A null
`servings` means the source states no yield: those rows carry whole-dish
totals, and the reader supplies the serving count on import.

# Ingredient lines

| File | What it is |
|---|---|
| `ingredient-lines.json` | Lines and what every ingredient parser reads from them. Edited by hand only. |
| `ingredient-lines.sha256` | The sha256 of `ingredient-lines.json`'s bytes. Written by the validator, never by hand. |
| `validate-ingredient-lines.mjs` | Shape checks on the table, and the checksum. |

The ingredient parser exists four times: `Sources/LiftCore/IngredientParser.swift`
here (LIFT iPhone, Coach iPhone), `IngredientParser.kt` in
`dugcanlift-kit-android` (LIFT Android, Coach Android), `coach/parser.js` in
`dugcanlift-coach` and LIFT web's `lift/app.js` in `dugcanlift-site`. A recipe
written on one reaches the others, so all four must read the same line the same
way, and every one of their test suites runs its parser over this table.

**The answers are written by hand from the rules below**, never generated from
a parser: a table one parser wrote proves only that it agrees with itself. A
parsed case gives `qty`, `unit`, `item` and `grams`; an unparsed case says
`"unparsed": true` and nothing else, because the parser keeps only `rawText`.
Compare `qty` to within 1e-9. `note` says why a case is there.

## The rules

When in doubt the line is not read: a confident wrong quantity on someone's
shopping list is worse than a line they can read and check.

1. **Whitespace.** Every character in JavaScript's `\s` (U+0009–U+000D, U+0020,
   U+00A0, U+1680, U+2000–U+200A, U+2028, U+2029, U+202F, U+205F, U+3000,
   U+FEFF) becomes a plain space first. `rawText` is the line as given.
2. **A quantity**, after any leading spaces, is one of:
   - a decimal: ASCII digits with at most one point and at least one digit —
     `2`, `1.5`, `1.`, `.5`;
   - a fraction of whole numbers, `1/2`, its denominator not zero. U+2044
     FRACTION SLASH reads as `/`: `1⁄2`;
   - a mixed number: a whole number, one or more spaces, a fraction — `1 1/2`;
   - a vulgar fraction, alone or after a whole number with or without spaces —
     `½`, `1½`, `1 ½`. The eighteen: ¼ ½ ¾ ⅐ ⅑ ⅒ ⅓ ⅔ ⅕ ⅖ ⅗ ⅘ ⅙ ⅚ ⅛ ⅜ ⅝ ⅞.
     Not ⅟ or ↉.

   No line without one is read. Every number in it must be finite, so a
   400-digit line is not read rather than read as infinity.
3. **The quantity must end where the number ends.** The line is not read when
   the next character after any spaces is
   - a number character (Unicode category N: a digit, a vulgar fraction, a
     superscript, another script's digit) — `1 2 eggs`, `1½ ½`, `2² cups`;
   - a slash — `1/2/3`, `1.5/2`, `1/cup`, `1 /2`;
   - one of `.` `,` `-` `‐` `‑` `‒` `–` `—` `−` followed, after any spaces, by a
     number character — `1,5 kg`, `1,000 g`, `1-2 cups`, `1 - 2 cups`,
     `1-1/2 cups`, `1. 2 cups`.

   Each of those is a number the parser cannot read, and stopping short of it
   would be the confident wrong quantity. A dash before a letter is fine:
   `1/2-inch piece ginger` is ½ of "-inch piece ginger". So a decimal is never
   a fraction's numerator or denominator, or a mixed number's whole part, and a
   vulgar fraction follows only a whole number.
4. **The unit** is the next word, lowercased, with a trailing run of `.` `,`
   `:` `;` removed: `tbsp.`, `tbsp:`, `cup;`, `tbsp.:`. Nothing is removed from
   the front, and nothing else from the end: `(tbsp)`, `tbsp)`, `tbsp-` and
   `-ounce` are not units. It is looked up among the abbreviations, then the
   spelled-out words, and stored as the abbreviation.
5. **The item** is the rest after the unit (or after the quantity, when the
   word is not a unit, with the unit the count sentinel), spaces trimmed. A
   line whose item is empty is not read: `2 cups`, `3 tsp.`, `2 cups:`.
6. `grams` is the quantity when the unit is `g` and null otherwise.

Pinned on purpose: `1 to 2 cups rice` is 1 of "to 2 cups rice" — a range in
words is not detected — and `1 pound cake mix` is a pound of cake mix.

## Changing a rule

Change the rule here, then the cases, by hand. Then:

```sh
node data/validate-ingredient-lines.mjs --write-checksum
```

and change the four parsers and copy **both files together** into the other
three repos, each with its parser change:

| Repo | Path |
|---|---|
| `dugcanlift-kit-android` | `liftcore/src/test/resources/fixtures/ingredient-lines.json` |
| `dugcanlift-coach` | `coach/fixtures/ingredient-lines.json` |
| `dugcanlift-site` | `lift/fixtures/ingredient-lines.json` |

(`dugcanlift-site/coach/fixtures/` is a fourth copy, written by `deploy.sh` in
`dugcanlift-coach`; nobody edits it.) Each repo's test asserts its copy hashes
to the `.sha256` beside it, so a copy taken without the checksum fails there.
