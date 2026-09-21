// Unit tests for the Road Food refresh check's reading, comparing and
// reporting. No network: every fixture below is a small hand-written stand-in
// shaped like the real source (the chains' own files are not committed).
//
//   node --test data/
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  compareItem, modificationSaving, normaliseLabel, findPdfRow, parseChickFilA, findChickFilARow,
  parseStarbucks, wendysRequest, parseWendysNutrition, deriveSnack, labelRound, fdcDate,
  newerFdcRecords, isStale, modifiedAfter, chainVerdict, exitCode, renderReport, renderSummary,
} from "./check-road-food-lib.mjs";

const item = (over = {}) => ({ id: "x-item", name: "Item", serving: "1", kcal: 300, proteinG: 20, fatG: 10, carbsG: 30,
  fiberG: 2, saturatedFatG: 3.5, sugarG: 5, sodiumMg: 800, ...over });

// ------------------------------------------------------------- comparing

test("identical figures give no differences", () => {
  assert.deepEqual(compareItem(item(), { kcal: 300, proteinG: 20, fatG: 10, carbsG: 30, fiberG: 2, saturatedFatG: 3.5, sugarG: 5, sodiumMg: 800 }), []);
});

test("every moved number is reported old -> new", () => {
  const d = compareItem(item(), { kcal: 310, proteinG: 20, fatG: 10, carbsG: 30, fiberG: 2, saturatedFatG: 4, sugarG: 5, sodiumMg: 800 });
  assert.deepEqual(d, [{ field: "kcal", old: 300, now: 310 }, { field: "saturatedFatG", old: 3.5, now: 4 }]);
});

test("a figure the bundle leaves blank but the source now gives is a difference", () => {
  const d = compareItem(item({ fiberG: undefined }), { kcal: 300, proteinG: 20, fatG: 10, carbsG: 30, fiberG: 1, saturatedFatG: 3.5, sugarG: 5, sodiumMg: 800 });
  assert.deepEqual(d, [{ field: "fiberG", old: undefined, now: 1 }]);
});

test("a figure the source stops giving is a difference, never a silent pass", () => {
  const d = compareItem(item(), { kcal: 300, proteinG: 20, fatG: 10, carbsG: 30, fiberG: 2, saturatedFatG: 3.5, sodiumMg: 800 });
  assert.deepEqual(d, [{ field: "sugarG", old: 5, now: undefined }]);
});

test("zero is a value, not a blank", () => {
  assert.deepEqual(compareItem({ sugarG: 0 }, {}, ["sugarG"]), [{ field: "sugarG", old: 0, now: undefined }]);
  assert.deepEqual(compareItem({ sugarG: 0 }, { sugarG: 0 }, ["sugarG"]), []);
});

test("only the fields the source speaks for are compared", () => {
  assert.deepEqual(compareItem(item(), { kcal: 300 }, ["kcal"]), []);
});

test("modification saving is read from the text", () => {
  assert.equal(modificationSaving("Hold the mayo to save 50 kcal"), 50);
  assert.equal(modificationSaving("Ask for it plain"), undefined);
});

// ------------------------------------------------------------- PDF rows

const SONIC = `SANDWICHES
∆ JR DOUBLE CHEESEBURGER 390 23 8 0 45 870 25 2 6 21
ORIGINAL SONIC SMASHER™ (DOUBLE) 600 37 14 1 100 1530 30 1 8 35
ORIGINAL SONIC SMASHER™ (TRIPLE) 780 51 20 1.5 150 2070 31 1 9 48
CRISPY TENDERS (3 PC.) 260 12 1 0 60 730 16 2 0 21`;
const SONIC_COLS = ["kcal", "fatG", "saturatedFatG", "_", "_", "sodiumMg", "carbsG", "fiberG", "sugarG", "proteinG"];

test("a PDF row is read by label, ignoring marks and case", () => {
  const r = findPdfRow(SONIC, { row: "Original SONIC Smasher (Double)" }, SONIC_COLS);
  assert.deepEqual(r.values, { kcal: 600, fatG: 37, saturatedFatG: 14, sodiumMg: 1530, carbsG: 30, fiberG: 1, sugarG: 8, proteinG: 35 });
  assert.equal(findPdfRow(SONIC, { row: "JR DOUBLE CHEESEBURGER" }, SONIC_COLS).values.kcal, 390);
});

test("a label never matches a longer item that starts with it", () => {
  const text = `6" Grilled Chicken & Fresh Avocado 304 450 16
6" Grilled Chicken 247 510 24`;
  assert.deepEqual(findPdfRow(text, { row: '6" Grilled Chicken' }, ["_", "kcal", "fatG"]).values, { kcal: 510, fatG: 24 });
});

test("a missing row is an error naming it", () => {
  const r = findPdfRow(SONIC, { row: "CRISPY TENDERS (5 PC.)" }, SONIC_COLS);
  assert.match(r.error, /CRISPY TENDERS \(5 PC\.\)" not found/);
});

test("a row with too few cells is an error, not a shifted read", () => {
  const r = findPdfRow("WING 1 220 140", { row: "WING" }, SONIC_COLS);
  assert.match(r.error, /has 3 cells, expected 10/);
});

test("rows are read from the right, so a serving column never shifts them", () => {
  const text = `TENDERS - BLACKENED 3 Pieces 170 50 6 2 0 80 860 2 1 0 28
BREAST (EACH) 1 620 270 30 16 1.5 180 1780 17 2 1 52`;
  const cols = ["kcal", "_", "fatG", "saturatedFatG", "_", "_", "sodiumMg", "carbsG", "fiberG", "sugarG", "proteinG"];
  assert.equal(findPdfRow(text, { row: "TENDERS - BLACKENED 3 Pieces" }, cols).values.proteinG, 28);
  assert.equal(findPdfRow(text, { row: "BREAST (EACH)" }, cols).values.kcal, 620);
});

test("a repeated label is found under its section heading, and nth picks among repeats", () => {
  const text = `Clubs
Subway Club® 263 500
PROTEIN BOWLS
Clubs
All American Club® 405 690
Subway Club® 418 410
Subway Club® 999 999`;
  assert.equal(findPdfRow(text, { row: "Subway Club®" }, ["_", "kcal"]).values.kcal, 500);
  assert.equal(findPdfRow(text, { row: "Subway Club®", after: "PROTEIN BOWLS" }, ["_", "kcal"]).values.kcal, 410);
  assert.equal(findPdfRow(text, { row: "Subway Club®", after: "PROTEIN BOWLS", nth: 2 }, ["_", "kcal"]).values.kcal, 999);
  assert.match(findPdfRow(text, { row: "Subway Club®", after: "SALADS" }, ["_", "kcal"]).error, /heading "SALADS" not found/);
});

test("a wrapped label and a row continued on the next line are joined", () => {
  const text = `Green Goddess Cobb Salad with Chicken -
Half
1/2 Salad 290 150 17 3.5 0 140 990 15 4 8 20 N/A
Green Goddess Cobb Salad with Chicken -
Whole
1 Salad 580 310 34 7 0 280 1980 30 7 15 40 N/A`;
  const cols = ["kcal", "_", "fatG", "saturatedFatG", "_", "_", "sodiumMg", "carbsG", "fiberG", "sugarG", "proteinG", "_"];
  const r = findPdfRow(text, { row: "Green Goddess Cobb Salad with Chicken - Whole" }, cols);
  assert.deepEqual(r.values, { kcal: 580, fatG: 34, saturatedFatG: 7, sodiumMg: 1980, carbsG: 30, fiberG: 7, sugarG: 15, proteinG: 40 });
});

test("a cell printed as <1 or N/A is left blank, not read as a number", () => {
  const r = findPdfRow("EGG BITE 1 70 <1 N/A", { row: "EGG BITE" }, ["_", "kcal", "sugarG", "fiberG"]);
  assert.deepEqual(r.values, { kcal: 70 });
});

test("label normalisation folds quotes, dashes and marks", () => {
  assert.equal(normaliseLabel("6” Turkey & Ranch Delite®"), '6" turkey & ranch delite');
  assert.equal(normaliseLabel("Country Archer™ – Jerky"), "country archer - jerky");
});

// ------------------------------------------------------------- Chick-fil-A

const cfaPage = (state) => `<html><body><table></table>
<script type="application/json" id="wp-script-module-data-@wordpress/interactivity">${JSON.stringify(state)}</script></body></html>`;
const field = (label, value) => ({ "sr-text": `${value} ${label}`, label, value });
const CFA = cfaPage({ state: { "nutrition-allergens-table-store": { tableData: { nutrition: [
  { menu: "Entrées", items: [{ title: "Grilled Nuggets", fields: [field("Calories", 130)], sub_items: [
    { title: "8 ct Grilled Nuggets", fields: [field("Serving Size", "95g"), field("Calories", 130), field("Fat (g)", 3), field("Sat. Fat (g)", 0.5),
      field("Sodium (mg)", 440), field("Carbohydrates (g)", 1), field("Fiber (g)", 0), field("Sugar (g)", 1), field("Protein (g)", 25)] }] }] },
  { menu: "Catering Entrées", items: [{ title: "8 ct Grilled Nuggets", fields: [field("Calories", 999)], sub_items: [] }] },
] } } } });

test("Chick-fil-A rows come from the page's embedded table, sub-items included", () => {
  const { rows } = parseChickFilA(CFA);
  const r = findChickFilARow(rows, { row: "8 ct Grilled Nuggets", section: "Entrées" });
  assert.deepEqual(r.values, { kcal: 130, fatG: 3, saturatedFatG: 0.5, sodiumMg: 440, carbsG: 1, fiberG: 0, sugarG: 1, proteinG: 25 });
  assert.equal(findChickFilARow(rows, { row: "8 ct Grilled Nuggets", section: "Catering Entrées" }).values.kcal, 999);
});

test("a Chick-fil-A page without the embedded table says so rather than guessing", () => {
  assert.match(parseChickFilA("<html>new site</html>").error, /no longer embeds/);
  assert.match(findChickFilARow(parseChickFilA(CFA).rows, { row: "Waffle Fries" }).error, /not found/);
});

// ------------------------------------------------------------- Starbucks

const SBUX = { products: [{ name: "Iced Latte", sizes: [
  { name: "Tall", nutrition: { calories: { displayValue: 150 }, additionalFacts: [{ id: "protein", value: 22 }] } },
  { name: "Grande", nutrition: { calories: { displayValue: 200 }, additionalFacts: [
    { id: "totalFat", value: 4, subfacts: [{ id: "saturatedFat", value: 2.5 }, { id: "transFat", value: 0 }] },
    { id: "sodium", value: 125 },
    { id: "totalCarbs", value: 12, subfacts: [{ id: "dietaryFiber", value: 0 }, { id: "sugars", value: 9 }] },
    { id: "protein", value: 29 }, { id: "caffeine", value: 150 }] } }] }] };

test("Starbucks: the named size is read, subfacts included", () => {
  assert.deepEqual(parseStarbucks(SBUX, "Grande").values,
    { kcal: 200, fatG: 4, saturatedFatG: 2.5, sodiumMg: 125, carbsG: 12, fiberG: 0, sugarG: 9, proteinG: 29 });
  assert.equal(parseStarbucks(SBUX).values.kcal, 150);
  assert.match(parseStarbucks(SBUX, "Venti").error, /"Venti" is not offered/);
});

// ------------------------------------------------------------- Wendy's

const MENU = { menuLists: {
  salesItems: [{ salesItemId: 40000, productId: "1", displayName: "Dave's Single®", defaultOptions: [
    { modifierId: 1, defaultQuantity: 1, modifierAction: 0 }, { modifierId: 2, defaultQuantity: 1, modifierAction: 0 },
    { modifierId: 3, defaultQuantity: 2, modifierAction: 4 }] }],
  modifiers: [{ modifierId: 1, name: "Potato Bun", componentId: "3830" }, { modifierId: 2, name: "Mayo", componentId: "3836" },
    { modifierId: 3, name: "Pickle", componentId: "25" }],
} };

test("Wendy's: the nutrition request is the item's default build", () => {
  assert.deepEqual(wendysRequest(MENU, 40000).data, { siteNum: 0, products: [{ id: "1", components: [
    { id: "3830", quantity: 1 }, { id: "3836", quantity: 1 }, { id: "25", quantity: 2, action: 4 }] }] });
});

test("Wendy's: a modification is checked by dropping that component", () => {
  const comps = wendysRequest(MENU, 40000, { without: "mayo" }).data.products[0].components.map((c) => c.id);
  assert.deepEqual(comps, ["3830", "25"]);
  assert.match(wendysRequest(MENU, 40000, { without: "Bacon" }).error, /"Bacon" is not a default component/);
});

test("Wendy's: an item gone from the menu is an error naming it", () => {
  assert.match(wendysRequest(MENU, 42212).error, /42212 is not on the national menu/);
});

test("Wendy's: the service's figures map onto the bundle's fields", () => {
  const r = parseWendysNutrition({ serviceStatus: "SUCCESS", data: { calories: 420, protein: 28, totalFat: 16, carbohydrates: 41,
    dietaryFiber: 1, saturated: 5, sugars: 2, sodium: 1100, cholesterol: 70 } });
  assert.deepEqual(r.values, { kcal: 420, proteinG: 28, fatG: 16, carbsG: 41, fiberG: 1, saturatedFatG: 5, sugarG: 2, sodiumMg: 1100 });
  assert.match(parseWendysNutrition({ serviceStatus: "ERROR", serviceMessages: ["'data' is a required parameter."] }).error, /ERROR: 'data'/);
});

// ------------------------------------------------------------- FDC snacks

test("FDA label rounding matches 21 CFR 101.9", () => {
  assert.equal(labelRound.kcal(4.9), 0);
  assert.equal(labelRound.kcal(47), 45);
  assert.equal(labelRound.kcal(84), 80);
  assert.equal(labelRound.fat(0.4), 0);
  assert.equal(labelRound.fat(3.3), 3.5);
  assert.equal(labelRound.fat(7.6), 8);
  assert.equal(labelRound.gram(0.7), undefined); // "less than 1 g": blank
  assert.equal(labelRound.gram(10.5), 11);
  assert.equal(labelRound.sodium(3), 0);
  assert.equal(labelRound.sodium(62), 60);
  assert.equal(labelRound.sodium(459.9), 460);
});

test("a snack is re-derived from FDC's per-100 g figures and serving", () => {
  const abridged = { foodNutrients: [
    { number: "208", amount: 286 }, { number: "203", amount: 39.3 }, { number: "204", amount: 3.57 }, { number: "205", amount: 21.4 },
    { number: "291", amount: 0 }, { number: "606", amount: 0 }, { number: "269", amount: 21.4 }, { number: "307", amount: 1640 },
    { number: "601", amount: 89 }] };
  assert.deepEqual(deriveSnack(abridged, { servingSize: 28 }).values,
    { kcal: 80, proteinG: 11, fatG: 1, carbsG: 6, fiberG: 0, saturatedFatG: 0, sugarG: 6, sodiumMg: 460 });
  assert.match(deriveSnack(abridged, {}).error, /no serving size/);
});

test("a newer FDC record for the same product is found in the update log", () => {
  const full = { fdcId: 2, publicationDate: "11/16/2023", foodUpdateLog: [
    { fdcId: 3, publicationDate: "8/20/2026", description: "NEW LABEL" }, { fdcId: 2, publicationDate: "11/16/2023" },
    { fdcId: 1, publicationDate: "5/23/2022" }] };
  assert.deepEqual(newerFdcRecords(full), [{ fdcId: 3, published: "2026-08-20", description: "NEW LABEL" }]);
  assert.deepEqual(newerFdcRecords({ ...full, foodUpdateLog: full.foodUpdateLog.slice(1) }), []);
  assert.equal(fdcDate("7/9/2021"), "2021-07-09");
});

// ------------------------------------------------------------- dates

test("stale means more than six calendar months", () => {
  assert.equal(isStale("2026-03-21", "2026-09-21"), false);
  assert.equal(isStale("2026-03-20", "2026-09-21"), true);
  assert.equal(isStale("2026-09-20", "2026-09-21"), false);
});

test("Last-Modified is compared with checkedOn by date", () => {
  assert.equal(modifiedAfter("Tue, 16 Sep 2025 14:51:23 GMT", "2026-09-20"), false);
  assert.equal(modifiedAfter("Mon, 21 Sep 2026 01:00:00 GMT", "2026-09-20"), true);
  assert.equal(modifiedAfter(undefined, "2026-09-20"), undefined);
});

// ------------------------------------------------------------- verdicts & exit

const chain = (over) => ({ id: "c", name: "Chain", checkedOn: "2026-09-20", items: [], signals: [], unreachable: [], ...over });

test("verdicts: unreachable beats changed beats manual beats unchanged", () => {
  assert.equal(chainVerdict(chain({ unreachable: ["HTTP 403"], items: [{ diffs: [{}] }] })), "unreachable");
  assert.equal(chainVerdict(chain({ items: [{ diffs: [] }, { diffs: [{ field: "kcal" }] }] })), "changed");
  assert.equal(chainVerdict(chain({ items: [{ missing: "row not found" }] })), "changed");
  assert.equal(chainVerdict(chain({ items: [{ diffs: [] }] })), "unchanged");
  assert.equal(chainVerdict(chain({ items: [{ diffs: [] }, { error: "no locator" }] })), "manual");
});

test("a manual source is never reported unchanged, but the report says whether its document moved", () => {
  for (const docChanged of [false, true, undefined]) assert.equal(chainVerdict(chain({ manual: true, docChanged })), "manual");
  const md = (docChanged) => renderReport({ results: [{ ...chain({ name: "Gas", manual: true, manualWhy: "rows interleave", docChanged }), verdict: "manual" }],
    stale: [], validator: { code: 0, output: "" }, ranAt: "t", bundle: { chains: 1, items: 0, snacks: 0 } });
  assert.match(md(false), /not modified since it was checked \(server's Last-Modified\): nothing to re-read/);
  assert.match(md(true), /Document changed since it was checked: re-read by hand/);
  assert.match(md(undefined), /Can't tell whether the document changed: re-read by hand/);
});

test("exit code: 1 for changed or unreachable, 0 for manual, 2 for a validator failure alone", () => {
  const ok = { code: 0, output: "" };
  assert.equal(exitCode([{ verdict: "unchanged" }, { verdict: "manual" }], ok), 0);
  assert.equal(exitCode([{ verdict: "changed" }], ok), 1);
  assert.equal(exitCode([{ verdict: "unreachable" }], ok), 1);
  assert.equal(exitCode([{ verdict: "manual" }], { code: 1, output: "" }), 2);
});

// ------------------------------------------------------------- report

test("the report lists each verdict, every differing number, staleness and the validator", () => {
  const results = [
    { ...chain({ name: "Burgers", items: [{ id: "b-1", name: "Single", compared: true, diffs: [{ field: "kcal", old: 560, now: 570 }, { field: "fiberG", old: undefined, now: 2 }] }] }), verdict: "changed" },
    { ...chain({ name: "Coffee", unreachable: ["example.com: HTTP 403 (refused; not retried or worked around)"] }), verdict: "unreachable" },
    { ...chain({ name: "Gas", manual: true, manualWhy: "rows interleave", docChanged: true, items: [{ id: "g-1", name: "Wrap" }] }), verdict: "manual" },
    { ...chain({ name: "Chicken", items: [{ id: "c-1", name: "Tenders", compared: true, diffs: [] }] }), verdict: "unchanged" },
  ];
  const md = renderReport({ results, stale: [{ name: "Old Chain", checkedOn: "2025-01-01" }],
    validator: { code: 0, output: "OK (2 warning(s))" }, ranAt: "2026-09-21T00:00:00Z",
    bundle: { chains: 4, items: 3, snacks: 0 }, pdfExtractor: "PDFKit" });
  assert.match(md, /\*\*1 changed, 1 couldn't reach, 1 can't compare automatically, 1 unchanged\.\*\*/);
  assert.match(md, /\| Burgers \| CHANGED \| 2026-09-20 \| 1 of 1 \|/);
  assert.match(md, /- kcal: 560 → 570/);
  assert.match(md, /- fibre g: blank → 2/);
  assert.match(md, /Couldn't reach: example\.com: HTTP 403/);
  assert.match(md, /Document changed since it was checked: re-read by hand/);
  assert.match(md, /- Old Chain: checked 2025-01-01/);
  assert.match(md, /exited 0/);
  // Changed first, unchanged last, so the report reads in order of urgency.
  assert.ok(md.indexOf("### Burgers") < md.indexOf("### Coffee") && md.indexOf("### Gas") < md.indexOf("### Chicken"));

  const txt = renderSummary(results, [], { code: 0 });
  assert.match(txt, /CHANGED\s+Burgers\n\s+b-1: kcal 560 -> 570/);
  assert.match(txt, /COULDN'T REACH\s+Coffee - example\.com/);
});

test("with nothing stale, the report says so", () => {
  const md = renderReport({ results: [], stale: [], validator: { code: 0, output: "OK" }, ranAt: "t", bundle: { chains: 0, items: 0, snacks: 0 } });
  assert.match(md, /## Over six months since checked\n\nNone\./);
});
