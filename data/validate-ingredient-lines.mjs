#!/usr/bin/env node
// Checks data/ingredient-lines.json -- the case table every ingredient parser
// is tested against -- for shape, and against the checksum the other three
// repos pin their copies to.
// Usage: node data/validate-ingredient-lines.mjs [path] [--write-checksum]
//   (exit 1 on any error; --write-checksum re-writes ingredient-lines.sha256
//   from a clean run, which is the only way that file is ever written)
//
// This checks the table, not a parser: there is no parser in this repo's node
// code, and the expected answers are written by hand from the rules in
// data/README.md. Each repo's own test suite runs its parser over the cases.
import { createHash } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { basename, dirname, join } from "node:path";

const args = process.argv.slice(2);
const writeChecksum = args.includes("--write-checksum");
const CURATED = join(dirname(fileURLToPath(import.meta.url)), "ingredient-lines.json");
const path = args.find((a) => !a.startsWith("--")) ?? CURATED;
// Read as bytes: the checksum is over the file the other repos copy.
const bytes = readFileSync(path);
const data = JSON.parse(bytes.toString("utf8"));
const errors = [];
const err = (where, msg) => errors.push(`${where}: ${msg}`);

const COUNT_UNIT = "\u0000count";
// The units a parser can store: the abbreviations, which is also what a
// spelled-out unit is stored as, and the count sentinel.
const UNITS = new Set(["g", "kg", "mg", "ml", "l", "tsp", "tbsp", "cup", "cups", "oz", "lb", "lbs",
  "clove", "cloves", "slice", "slices", "scoop", "scoops", "can", "cans", "pinch", "handful", COUNT_UNIT]);
const PARSED_KEYS = new Set(["line", "qty", "unit", "item", "grams", "note"]);
const UNPARSED_KEYS = new Set(["line", "unparsed", "note"]);

if (data.countUnit !== COUNT_UNIT) err("countUnit", "must be NUL followed by \"count\"");
if (!Array.isArray(data.cases) || !data.cases.length) err("cases", "must be a non-empty array");
const seen = new Set();
(data.cases ?? []).forEach((c, i) => {
  const where = `cases[${i}] ${JSON.stringify(c?.line)}`;
  if (typeof c?.line !== "string") return err(where, "line must be a string");
  if (seen.has(c.line)) err(where, "duplicate line");
  seen.add(c.line);
  if ("note" in c && (typeof c.note !== "string" || !c.note.trim())) err(where, "note must be text");
  if (c.unparsed !== undefined) {
    if (c.unparsed !== true) err(where, "unparsed must be true or absent");
    for (const k of Object.keys(c)) if (!UNPARSED_KEYS.has(k)) err(where, `an unparsed case has no "${k}"`);
    return;
  }
  for (const k of Object.keys(c)) if (!PARSED_KEYS.has(k)) err(where, `unknown key "${k}"`);
  if (typeof c.qty !== "number" || !Number.isFinite(c.qty) || c.qty < 0) err(where, "qty must be a finite number, not negative");
  if (!UNITS.has(c.unit)) err(where, `unit ${JSON.stringify(c.unit)} is not one a parser stores`);
  if (typeof c.item !== "string" || !c.item || c.item !== c.item.replace(/^ +| +$/g, "")) {
    err(where, "item must be non-empty text with no leading or trailing space");
  }
  // grams is the quantity for g and nothing else, spelled out or not.
  const grams = c.unit === "g" ? c.qty : null;
  if (c.grams !== grams) err(where, `grams must be ${grams}`);
});

const checksumPath = path.replace(/\.json$/, ".sha256");
const actualSum = createHash("sha256").update(bytes).digest("hex");
const expectedSum = existsSync(checksumPath) ? readFileSync(checksumPath, "utf8").trim() : null;
if (!writeChecksum) {
  if (expectedSum === null) {
    if (path === CURATED) err("checksum", `no ${basename(checksumPath)} beside the file (write one with --write-checksum)`);
  } else if (!/^[0-9a-f]{64}$/.test(expectedSum)) {
    err("checksum", `${basename(checksumPath)} is not a sha256 (write it with --write-checksum, never by hand)`);
  } else if (expectedSum !== actualSum) {
    err("checksum", `${basename(checksumPath)} is stale: it pins ${expectedSum.slice(0, 12)}..., the file hashes to ${actualSum.slice(0, 12)}...`
      + " (re-run with --write-checksum, then copy both files to the other repos)");
  }
}

const parsed = (data.cases ?? []).filter((c) => !c.unparsed).length;
console.log(`${data.cases?.length ?? 0} lines, ${parsed} parsed, ${(data.cases?.length ?? 0) - parsed} unparsed`);
for (const e of errors) console.log(`ERROR    ${e}`);
// Written last, and only from an otherwise clean run, as road-food.sha256 is.
if (writeChecksum) {
  if (errors.length) console.log(`REFUSED to write ${basename(checksumPath)}: fix the ${errors.length} error(s) first`);
  else if (expectedSum === actualSum) console.log(`${basename(checksumPath)} already matches ${actualSum.slice(0, 12)}...`);
  else {
    writeFileSync(checksumPath, actualSum + "\n");
    console.log(`wrote ${basename(checksumPath)}: ${actualSum}`);
    console.log("copy ingredient-lines.json and ingredient-lines.sha256 together into the other three repos");
  }
}
console.log(errors.length ? `FAILED: ${errors.length} error(s)` : "OK");
process.exit(errors.length ? 1 : 0);
