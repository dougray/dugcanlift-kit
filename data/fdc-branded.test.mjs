// Tests for reading the snacks out of USDA FoodData Central's Branded Foods
// bulk file: the zip reader, the CSV reader, and the snack check built on them.
// No network and no real USDA download: data/fixtures/fdc-branded/ holds four
// CSVs written by hand in USDA's own column layout (the names in USDA's
// "Download Field Descriptions"), and two zips of them made by two independent
// tools, Python's zipfile (deflate, the CSVs in a folder as a release has them)
// and Info-ZIP's zip (ZIP64 records forced, one member stored).
//
// Every expected per-serving figure below was worked by hand from the
// fixture's per-100 g amounts: amount x serving / 100, to one decimal, then
// FDA label rounding.
//
//   node --test data/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { listZip, zipEntryChunks } from "./read-zip.mjs";
import {
  csvRows, readBrandedFoods, checkSnacks, compareSnack, gtinKey, brandedRelease, fdcDate,
  BRANDED_COLUMNS, renderReport, renderSummary, exitCode,
} from "./check-road-food-lib.mjs";

const FIX = join(dirname(fileURLToPath(import.meta.url)), "fixtures", "fdc-branded");
const PY_ZIP = join(FIX, "FoodData_Central_branded_food_csv_2026-10-29.zip");
const INFO_ZIP = join(FIX, "infozip-zip64.zip");
const CSVS = Object.keys(BRANDED_COLUMNS);

const fromDir = (name) => [readFileSync(join(FIX, name))];
const fromZip = async (path) => {
  const entries = await listZip(path);
  return (name) => zipEntryChunks(path, entries.find((e) => e.name.split("/").pop() === name));
};
const collect = async (chunks) => { const out = []; for await (const c of chunks) out.push(c); return Buffer.concat(out); };
const rows = async (chunks) => { const out = []; for await (const r of csvRows(chunks)) out.push(r); return out; };

// The bundle's side: the figures each snack is recorded with.
const snack = (over) => ({ category: "x", brand: "x", serving: "1", checkedOn: "2026-09-21", ...over });
const JERKY = snack({ id: "snack-match", name: "Trail Jerky", fdcId: 3001, barcode: "012345678905",
  kcal: 80, proteinG: 11, fatG: 1, carbsG: 6, fiberG: 0, saturatedFatG: 0, sugarG: 6, sodiumMg: 460 });
const BAR = snack({ id: "snack-moved", name: "Moved Bar", fdcId: 3002, barcode: "098765432109",
  kcal: 210, proteinG: 21, fatG: 7, carbsG: 24, fiberG: 10, saturatedFatG: 3, sugarG: 1, sodiumMg: 200 });
const CHEESE = snack({ id: "snack-discontinued", name: "Cheese Stick", fdcId: 3003, barcode: "070000000027",
  kcal: 60, proteinG: 7, fatG: 3, carbsG: 1, fiberG: 0, saturatedFatG: 2, sugarG: 0, sodiumMg: 200 });
const ALMONDS = snack({ id: "snack-newer", name: "Almonds", fdcId: 3004, barcode: "041570054161",
  kcal: 170, proteinG: 6, fatG: 15, carbsG: 6, fiberG: 3, saturatedFatG: 1, sugarG: 1, sodiumMg: 150 });
const GONE = snack({ id: "snack-gone", name: "Granola Bar", fdcId: 3999, barcode: "850000000014", kcal: 180 });
const GONE_NO_TRACE = snack({ id: "snack-gone-no-trace", name: "Vanished Bar", fdcId: 3998, barcode: "011111111111", kcal: 200 });
const SNACKS = [JERKY, BAR, CHEESE, ALMONDS, GONE, GONE_NO_TRACE];

// ------------------------------------------------------------- the zip reader

test("both fixture zips hold exactly the fixture CSVs, byte for byte", async () => {
  for (const path of [PY_ZIP, INFO_ZIP]) {
    const open = await fromZip(path);
    for (const name of CSVS) assert.deepEqual(await collect(open(name)), readFileSync(join(FIX, name)), `${name} in ${path}`);
  }
});

test("the zip reader lists members, ZIP64 records and a stored member included", async () => {
  const info = await listZip(INFO_ZIP);
  assert.deepEqual(info.map((e) => e.name), ["branded_food.csv", "food.csv", "food_nutrient.csv", "nutrient.csv"]);
  assert.deepEqual(info.map((e) => e.method), [8, 8, 8, 0]);
  const py = await listZip(PY_ZIP);
  assert.equal(py.length, 5);
  assert.ok(py.every((e) => e.name.startsWith("FoodData_Central_branded_food_csv_2026-10-29/")));
});

test("a damaged member is refused, never read short", async () => {
  const [e] = await listZip(PY_ZIP);
  await assert.rejects(collect(zipEntryChunks(PY_ZIP, { ...e, crc32: (e.crc32 + 1) >>> 0 })), /CRC-32 does not match/);
  await assert.rejects(collect(zipEntryChunks(PY_ZIP, { ...e, method: 9 })), /compression method 9/);
  await assert.rejects(listZip(join(FIX, "food.csv")), /not a zip file/);
});

// ------------------------------------------------------------- the CSV reader

test("CSV: quoted commas, doubled quotes, a newline inside a field, CRLF, a BOM", async () => {
  const text = '﻿"a","b","c"\r\n"1","x, ""y""","line one\nline two"\r\n\r\n2,plain,\n"3","",""';
  assert.deepEqual(await rows([text]), [
    ["a", "b", "c"], ["1", 'x, "y"', "line one\nline two"], ["2", "plain", ""], ["3", "", ""]]);
});

test("CSV: a chunk boundary anywhere, even inside a UTF-8 character, changes nothing", async () => {
  const bytes = Buffer.concat([readFileSync(join(FIX, "branded_food.csv")), Buffer.from('"9","Crème Brûlée, ""Ü"""\n')]);
  const whole = await rows([bytes]);
  for (const size of [1, 2, 3, 7, 64]) {
    const pieces = [];
    for (let i = 0; i < bytes.length; i += size) pieces.push(bytes.subarray(i, i + size));
    assert.deepEqual(await rows(pieces), whole, `chunks of ${size}`);
  }
  assert.deepEqual(whole.at(-1), ["9", 'Crème Brûlée, "Ü"']);
  assert.equal(whole[1][5], 'BEEF, WATER, SUGAR, "NATURAL" FLAVORS,\nSALT (FOR FLAVOR)');
});

test("a CSV missing a column the check reads is refused by name", async () => {
  const open = (name) => (name === "food.csv" ? ['"fdc_id","data_type","description"\n"3001","branded_food","X"\n'] : fromDir(name));
  await assert.rejects(readBrandedFoods(open, SNACKS), /food\.csv has no publication_date column/);
});

// ------------------------------------------------------------- the records

test("records come out in the shapes deriveSnack and newerFdcRecords read", async () => {
  const { records, byBarcode } = await readBrandedFoods(fromDir, SNACKS);
  assert.deepEqual([...records.keys()].sort(), [3001, 3002, 3003, 3004]);
  const jerky = records.get(3001);
  assert.equal(jerky.full.servingSize, 28);
  assert.equal(jerky.full.servingSizeUnit, "g");
  assert.equal(jerky.full.publicationDate, "2025-03-01");
  assert.equal(jerky.full.description, 'TRAIL JERKY, "ORIGINAL" BEEF');
  // nutrient_id 1008 is reported as its nutrient_nbr, 208, the number the API used.
  assert.ok(jerky.abridged.foodNutrients.some((n) => n.number === "208" && n.amount === 286));
  // 1063 "Sugars, Total" is 269.3, not 269.
  assert.ok(jerky.abridged.foodNutrients.some((n) => n.number === "269.3"));
  // An empty amount is unknown, not zero.
  assert.ok(!records.get(3002).abridged.foodNutrients.some((n) => n.number === "269.3"));
  // Almonds: three records share one GTIN in three spellings; newest first.
  assert.deepEqual(records.get(3004).full.foodUpdateLog.map((r) => r.fdcId), [3005, 3004, 3006]);
  assert.deepEqual(byBarcode.get("850000000014").map((r) => r.fdcId), [3007]);
  assert.equal(byBarcode.has(gtinKey("036000291452")), false); // nobody asked for the soda
});

test("the zip and the plain CSVs give the same records", async () => {
  const plain = await readBrandedFoods(fromDir, SNACKS);
  for (const path of [PY_ZIP, INFO_ZIP]) assert.deepEqual(await readBrandedFoods(await fromZip(path), SNACKS), plain);
});

test("GTIN keys ignore leading zeros, spaces and dashes", () => {
  assert.equal(gtinKey("0041570054161"), "41570054161");
  assert.equal(gtinKey("00041570054161"), gtinKey("41570054161"));
  assert.equal(gtinKey("0-41570-05416 1"), "41570054161");
  assert.equal(gtinKey("0000"), undefined);
  assert.equal(gtinKey("ABC123"), undefined);
  assert.equal(fdcDate("2026-08-20"), "2026-08-20");
});

// ------------------------------------------------------------- the snack check

const bulk = async () => ({ ...(await readBrandedFoods(fromDir, SNACKS)), file: "FoodData_Central_branded_food_csv_2026-10-29.zip", release: "2026-10-29" });
const item = (r, id) => r.items.find((i) => i.id === id);

test("a snack that matches has no differences", async () => {
  const r = checkSnacks(SNACKS, await bulk());
  assert.deepEqual(item(r, "snack-match"), { id: "snack-match", name: "Trail Jerky", compared: true, diffs: [], notes: [] });
});

test("a snack whose figure moved is reported field by field", async () => {
  const r = checkSnacks(SNACKS, await bulk());
  assert.deepEqual(item(r, "snack-moved").diffs, [{ field: "proteinG", old: 21, now: 20 }]);
});

test("a discontinued snack is reported with USDA's date", async () => {
  const r = checkSnacks(SNACKS, await bulk());
  assert.deepEqual(item(r, "snack-discontinued").diffs, [{ field: "discontinued", label: "discontinued", old: "no", now: "2026-06-01" }]);
});

test("a newer record with the same GTIN is reported; an older one is not", async () => {
  const r = checkSnacks(SNACKS, await bulk());
  assert.deepEqual(item(r, "snack-newer").diffs, [{ field: "fdcId", label: "newer FDC record for this product", old: "3004 (2023-10-01)", now: "3005 (2026-08-20)" }]);
});

test("an fdcId missing from the file is reported, with whatever the file holds for its barcode", async () => {
  const r = checkSnacks(SNACKS, await bulk());
  assert.equal(item(r, "snack-gone").missing,
    "record 3999 is not in the Branded Foods file; the file holds 1 record(s) with its barcode 850000000014: 3007 (2026-05-01)");
  assert.equal(item(r, "snack-gone-no-trace").missing, "record 3998 is not in the Branded Foods file");
  assert.equal(r.verdict, "changed");
  assert.equal(exitCode([r], { code: 0 }), 1);
  assert.match(r.signals[0], /FoodData_Central_branded_food_csv_2026-10-29\.zip \(release 2026-10-29\); no API, no key/);
});

test("every snack matching is 'unchanged'", async () => {
  const r = checkSnacks([JERKY], await bulk());
  assert.equal(r.verdict, "unchanged");
  assert.equal(exitCode([r], { code: 0 }), 0);
});

test("a release older than the snacks' checkedOn says so", async () => {
  const r = checkSnacks([JERKY], { ...(await bulk()), release: "2026-04-30" });
  assert.match(r.signals.join("\n"), /This release \(2026-04-30\) is older than the newest snack checkedOn \(2026-09-21\)/);
  assert.equal(brandedRelease("/x/FoodData_Central_branded_food_csv_2026-04-30.zip"), "2026-04-30");
  assert.equal(brandedRelease("branded.zip"), undefined);
});

test("no file given: snacks are 'not compared', with the reason, and the run does not fail", () => {
  const r = checkSnacks(SNACKS, undefined);
  assert.equal(r.verdict, "manual");
  assert.equal(r.items.filter((i) => i.compared).length, 0);
  assert.equal(exitCode([r], { code: 0 }), 0);
  const md = renderReport({ results: [r], stale: [], validator: { code: 0, output: "OK" }, ranAt: "2026-11-04T00:00:00Z",
    bundle: { chains: 0, items: 0, snacks: SNACKS.length } });
  assert.match(md, /\| Snacks \(FoodData Central\) \| can't compare automatically \| 2026-09-21 \| 0 of 6 \| Not compared: no USDA Branded Foods file given \|/);
  assert.match(md, /Not read automatically: no USDA Branded Foods CSV zip was given \(`--fdc-branded <zip>` or `FDC_BRANDED_ZIP`\)/);
  assert.match(md, /Trail Jerky \(`snack-match`\): not compared \(no Branded Foods file given\)/);
  assert.match(renderSummary([r], [], { code: 0 }), /can't compare automatically\s+Snacks \(FoodData Central\) - Not compared: no USDA Branded Foods file given/);
});

test("a file given that cannot be read fails the run", () => {
  const r = checkSnacks(SNACKS, { error: "no such file", file: "nope.zip" });
  assert.equal(r.verdict, "unreachable");
  assert.equal(r.unreachable[0], "couldn't read nope.zip: no such file");
  assert.equal(exitCode([r], { code: 0 }), 1);
});

test("compareSnack keeps deriveSnack's refusal of a record with no serving size", () => {
  const rec = { abridged: { foodNutrients: [{ number: "208", amount: 100 }] }, full: { fdcId: 1, publicationDate: "2026-01-01", foodUpdateLog: [] } };
  assert.deepEqual(compareSnack(JERKY, rec), { id: "snack-match", name: "Trail Jerky", missing: "the FDC record has no serving size" });
});
