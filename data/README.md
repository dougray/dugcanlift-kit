# Road Food data

| File | What it is |
|---|---|
| `road-food.json` | The bundled chains, items, snacks and rules the apps read. Edited by hand only. |
| `road-food-SOURCES.md` | Where every number came from, when, how it was read, and every doubt. |
| `validate-road-food.mjs` | Shape and honesty checks on the JSON. |
| `check-road-food.mjs` | The refresh check: have the chains' published numbers moved? |
| `check-road-food-lib.mjs` | The check's reading, comparing and reporting, with no network (tested). |
| `road-food-locators.json` | Where each bundled item sits in its source: a PDF row, a sales item id, a product number. |
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
was fetched. Five of the eleven chains are in this position and it is not a
gap to fill: Wendy's, Starbucks and Chick-fil-A publish live pages that say
nothing about themselves, QuikTrip's PDF prints no date, and Sonic's says only
"SUMMER 2026" — a season is not a month, and `2026` alone would be inventing
the rest. `road-food-SOURCES.md` records what each document does say.

## Validate

```sh
node data/validate-road-food.mjs
```

## Refresh check

```sh
node data/check-road-food.mjs     # fetches every source, writes data/road-food-CHECK.md
node --test data/                 # unit tests, no network
```

For each chain the check fetches the source SOURCES.md records, once, with a
User-Agent naming the tool and a pause between requests. It never retries, and
it never works around a refusal: a 403 is reported as "couldn't reach".
Where the source can be read by machine (PDF text, the JSON embedded in
Chick-fil-A's page, Wendy's and Starbucks' ordering APIs, FoodData Central) it
reads each bundled item back out and compares every number. Where it can't
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

FoodData Central uses `FDC_API_KEY` if set, otherwise `DEMO_KEY`, which allows
only a few requests an hour. A run makes four.

### When a chain or item is added

Add its locator to `road-food-locators.json`, or the check reports the item
as "not compared". Run the check once: every number should match, because the
item was just read from the same source.

## Quarterly refresh

Once a quarter (January, April, July, October), and before any release that
ships the data:

1. `node data/check-road-food.mjs`, then read `data/road-food-CHECK.md`.
2. **Changed:** open the source, confirm each old → new figure by eye, and
   update the item and the chain's `checkedOn`. An item that is gone from the
   source comes out of the file, or is replaced with one read the same way.
3. **Couldn't reach:** try the source in a browser. If the chain moved its
   document, find the new one on the chain's own site, update `source` and the
   locator, and record it in SOURCES.md. Don't bypass a block.
4. **Can't compare automatically:** re-read the document by hand when the
   report says it changed or can't tell. For QuikTrip, also confirm a
   quiktrip.com product page still links the recorded PDF: a new one would sit
   at a new address.
5. **Over six months:** re-read and re-date, even if nothing moved; the apps
   say so in words. Note that re-dating fixes `checkedOn` only: a chain whose
   *document* is old stays old however often it is read, and the warning is
   meant to keep saying so.
6. **Document date moved:** the check reports a chain whose document no longer
   states the date `publishedOn` records, which means the chain republished.
   Re-read the document and its date by hand, and update both fields.
7. `node data/validate-road-food.mjs`, then ship the change with the apps like
   any other.
