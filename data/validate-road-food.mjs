#!/usr/bin/env node
// Checks data/road-food.json against the Road Food spec's shape, and against
// the checksum the five app repos pin their copies to.
// Usage: node data/validate-road-food.mjs [path] [--write-checksum]
//   (exit 1 on any error; --write-checksum re-writes road-food.sha256 from a
//   clean run, which is the only way that file is ever written)
//
// Errors are shape and honesty failures: a missing required field, a
// non-number, a null or string standing in for a number, a duplicate id, a
// chain without source/checkedOn, an unknown key (usually a typo that would
// silently drop a value). Warnings are for a human: a published figure that
// does not add up (energy vs. macros), or a zero worth a second look.
import { createHash } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { basename, dirname, join } from "node:path";

// Flags are picked out by name, so --write-checksum may come on either side of
// the optional path.
const args = process.argv.slice(2);
const writeChecksum = args.includes("--write-checksum");
const CURATED = join(dirname(fileURLToPath(import.meta.url)), "road-food.json");
const path = args.find((a) => !a.startsWith("--")) ?? CURATED;
// Read as bytes, not as text. The checksum the apps pin is over the file they
// bundle; a string decoded and re-encoded is not guaranteed to be those bytes.
const bytes = readFileSync(path);
const data = JSON.parse(bytes.toString("utf8"));
const errors = [];
const warnings = [];
const err = (where, msg) => errors.push(`${where}: ${msg}`);
const warn = (where, msg) => warnings.push(`${where}: ${msg}`);

const NUMERIC = ["kcal", "proteinG", "fatG", "carbsG", "fiberG", "saturatedFatG", "sugarG", "sodiumMg"];
const REQUIRED_NUMERIC = ["kcal", "proteinG", "fatG", "carbsG"];
const ITEM_KEYS = new Set(["id", "name", "serving", ...NUMERIC, "modification"]);
const CHAIN_KEYS = new Set(["id", "name", "kind", "publishedOn", "checkedOn", "source", "items"]);
const KIND = /^[a-z]+(-[a-z]+)*$/;
// The Gas station screen shows only rules whose kinds include "snacks", so no
// chain may claim that kind or snack rules would reach its screen too.
const SNACKS_KIND = "snacks";
const SNACK_KEYS = new Set(["id", "category", "brand", "name", "serving", "barcode", "fdcId",
  "source", "checkedOn", ...NUMERIC]);
// Display labels every app shows as-is: no platform humanises a slug its own way.
const CATEGORIES = new Set(["Beef jerky and meat sticks", "Protein bars", "Greek yogurt",
  "String cheese", "Hard-boiled eggs", "Tuna and chicken pouches", "Nuts", "Protein shakes", "Fruit"]);
const ids = new Set();

const isDate = (s) => typeof s === "string" && /^\d{4}-\d{2}-\d{2}$/.test(s)
  && !Number.isNaN(Date.parse(s + "T00:00:00Z"))
  && new Date(s + "T00:00:00Z").toISOString().startsWith(s);
// `publishedOn` is the date the source document states about itself, so it is
// as precise as the document is and no more: a full day, or a month when the
// document names only a month. A document that states no date at all has no
// key. See "Published on" in README.md.
const isDocDate = (s) => isDate(s) || (typeof s === "string" && /^\d{4}-\d{2}$/.test(s)
  && Number(s.slice(5)) >= 1 && Number(s.slice(5)) <= 12);
// A month-only date is read as the first of that month everywhere, which can
// only ever make a document look older, never fresher.
const docDateDay = (s) => (s.length === 7 ? s + "-01" : s);
const isURL = (s) => { try { return new URL(s).protocol === "https:"; } catch { return false; } };
const nonEmpty = (s) => typeof s === "string" && s.trim().length > 0 && s === s.trim();

function checkId(where, id, prefix) {
  if (!nonEmpty(id) || !/^[a-z0-9]+(-[a-z0-9]+)*$/.test(id)) return err(where, `bad id ${JSON.stringify(id)}`);
  if (prefix && !id.startsWith(prefix + "-")) err(where, `id should start with "${prefix}-"`);
  if (ids.has(id)) err(where, `duplicate id "${id}"`);
  ids.add(id);
}

function checkKeys(where, obj, allowed) {
  for (const k of Object.keys(obj)) if (!allowed.has(k)) err(where, `unknown key "${k}"`);
}

// Numbers: present ones must be finite and non-negative; blank is an absent
// key, never null, "", or a zero standing in for "not given".
function checkNutrition(where, o) {
  for (const k of NUMERIC) {
    if (!(k in o)) {
      if (REQUIRED_NUMERIC.includes(k)) err(where, `missing ${k}`);
      continue;
    }
    const v = o[k];
    if (typeof v !== "number" || !Number.isFinite(v)) err(where, `${k} is ${JSON.stringify(v)}, not a number (omit the key when not given)`);
    else if (v < 0) err(where, `${k} is negative`);
  }
  const n = (k) => (typeof o[k] === "number" ? o[k] : undefined);
  const kcal = n("kcal"), p = n("proteinG"), f = n("fatG"), c = n("carbsG");
  if (kcal === undefined || p === undefined || f === undefined || c === undefined) return;

  // Zeros that cannot be real: energy with no macros, or macros with no energy.
  if (kcal === 0 && p + f + c > 1) err(where, `kcal is 0 but macros are ${p}/${f}/${c} g`);
  if (kcal > 20 && p === 0 && f === 0 && c === 0) err(where, `${kcal} kcal but every macro is 0`);
  // Sub-nutrients cannot exceed their parent.
  if (n("saturatedFatG") > f + 0.5) err(where, `saturatedFatG ${n("saturatedFatG")} > fatG ${f}`);
  if (n("sugarG") > c + 1) err(where, `sugarG ${n("sugarG")} > carbsG ${c}`);
  if (n("fiberG") > c + 1) err(where, `fiberG ${n("fiberG")} > carbsG ${c}`);
  // Atwater check. Labels round each figure, and fibre and sugar alcohols carry
  // less than 4 kcal/g, so this is a prompt to re-read the source, not a verdict.
  const est = 4 * p + 4 * c + 9 * f;
  const diff = Math.abs(est - kcal);
  if (diff > Math.max(30, 0.2 * kcal)) warn(where, `kcal ${kcal} vs 4P+4C+9F = ${Math.round(est)} (re-check the source)`);
  if (kcal > 0 && p === 0) warn(where, "proteinG is 0 - confirm the source says 0, not blank");
}

if (data.version !== 1) err("root", "version must be 1");
for (const k of Object.keys(data)) if (!["version", "chains", "snacks", "rules"].includes(k)) err("root", `unknown key "${k}"`);
if (!Array.isArray(data.chains) || data.chains.length === 0) err("root", "chains must be a non-empty array");
if (!Array.isArray(data.snacks) || data.snacks.length === 0) err("root", "snacks must be a non-empty array");
if (!Array.isArray(data.rules) || data.rules.length === 0) err("root", "rules must be a non-empty array");

for (const [i, ch] of (data.chains ?? []).entries()) {
  const w = `chain[${i}] ${ch.id ?? "?"}`;
  checkKeys(w, ch, CHAIN_KEYS);
  checkId(w, ch.id);
  if (!nonEmpty(ch.name)) err(w, "missing name");
  if ("kind" in ch) {
    if (typeof ch.kind !== "string" || !KIND.test(ch.kind)) err(w, `kind ${JSON.stringify(ch.kind)} is not a lowercase word or kebab-case`);
    else if (ch.kind === SNACKS_KIND) err(w, `kind "${SNACKS_KIND}" is reserved for the Gas station snack screen`);
  } else warn(w, "no kind, so only plain-string rules will show on it");
  if (!isDate(ch.checkedOn)) err(w, `checkedOn ${JSON.stringify(ch.checkedOn)} is not YYYY-MM-DD`);
  if ("publishedOn" in ch) {
    if (!isDocDate(ch.publishedOn)) err(w, `publishedOn ${JSON.stringify(ch.publishedOn)} is not YYYY-MM-DD or YYYY-MM (omit the key when the document states no date)`);
    // A document cannot have been published after the day someone read it.
    else if (isDate(ch.checkedOn) && docDateDay(ch.publishedOn) > ch.checkedOn) err(w, `publishedOn ${ch.publishedOn} is after checkedOn ${ch.checkedOn}`);
  }
  if (!isURL(ch.source)) err(w, `source ${JSON.stringify(ch.source)} is not an https URL`);
  if (!Array.isArray(ch.items) || ch.items.length === 0) { err(w, "no items"); continue; }
  if (ch.items.length < 5 || ch.items.length > 10) warn(w, `${ch.items.length} items (spec: 5-10)`);
  for (const it of ch.items) {
    const wi = `${w} / ${it.id ?? "?"}`;
    checkKeys(wi, it, ITEM_KEYS);
    checkId(wi, it.id, ch.id);
    if (!nonEmpty(it.name)) err(wi, "missing name");
    if (!nonEmpty(it.serving)) err(wi, "missing serving");
    if ("modification" in it && !nonEmpty(it.modification)) err(wi, "empty modification (omit the key instead)");
    checkNutrition(wi, it);
  }
}

for (const [i, s] of (data.snacks ?? []).entries()) {
  const w = `snack[${i}] ${s.id ?? "?"}`;
  checkKeys(w, s, SNACK_KEYS);
  checkId(w, s.id);
  if (!CATEGORIES.has(s.category)) err(w, `unknown category ${JSON.stringify(s.category)}`);
  for (const k of ["brand", "name", "serving"]) if (!nonEmpty(s[k])) err(w, `missing ${k}`);
  if (!Number.isInteger(s.fdcId) || s.fdcId <= 0) err(w, "fdcId must be a positive integer");
  if ("barcode" in s && !(typeof s.barcode === "string" && /^\d{8,14}$/.test(s.barcode))) err(w, `barcode ${JSON.stringify(s.barcode)} is not 8-14 digits`);
  if (!isURL(s.source) || !new URL(s.source).hostname.endsWith("fdc.nal.usda.gov")) err(w, "source must be an https FoodData Central URL");
  else if (Number.isInteger(s.fdcId) && !s.source.includes(String(s.fdcId))) err(w, "source URL does not name the fdcId");
  if (!isDate(s.checkedOn)) err(w, "checkedOn is not YYYY-MM-DD");
  checkNutrition(w, s);
}
for (const c of CATEGORIES) {
  const count = (data.snacks ?? []).filter((s) => s.category === c).length;
  if (count === 0) warn("snacks", `no products in category "${c}"`);
  else if (count > 4) warn("snacks", `${count} products in "${c}" (brief: 2-4)`);
}

// A rule is a plain string (every chain, never the snack screen) or
// { text, kinds } (only chains whose kind is listed, plus the snack screen
// when "snacks" is listed). An empty kinds array would make an object apply
// everywhere, snack screen included, so it is an error, not a shorthand.
const chainKinds = new Set((data.chains ?? []).map((c) => c.kind).filter(Boolean));
let snackRules = 0;
for (const [i, r] of (data.rules ?? []).entries()) {
  const w = `rules[${i}]`;
  if (typeof r === "string") { if (!nonEmpty(r)) err(w, "must be a non-empty string"); continue; }
  if (!r || typeof r !== "object" || Array.isArray(r)) { err(w, "must be a string or { text, kinds }"); continue; }
  checkKeys(w, r, new Set(["text", "kinds"]));
  if (!nonEmpty(r.text)) err(w, "missing text");
  if (!Array.isArray(r.kinds) || r.kinds.length === 0) { err(w, "kinds must be a non-empty array (use a plain string for an every-chain rule)"); continue; }
  for (const k of r.kinds) {
    if (typeof k !== "string" || !KIND.test(k)) err(w, `kind ${JSON.stringify(k)} is not a lowercase word or kebab-case`);
    else if (k !== SNACKS_KIND && !chainKinds.has(k)) warn(w, `kind "${k}" matches no chain, so this rule never shows`);
  }
  if (r.kinds.includes(SNACKS_KIND)) snackRules++;
}
if (!snackRules) warn("rules", `no rule has kind "${SNACKS_KIND}", so the Gas station screen shows none`);

// The checksum the five app repos pin their copy against. `road-food.sha256`
// holds one line -- the sha256 of road-food.json's bytes and nothing else --
// so node, Kotlin and Swift can each read it back without a parser, and no
// path inside it can go stale when a repo keeps the file somewhere else.
//
// A stale checksum is an error because the whole point is that it moves with
// the file: a curator who edits the data and forgets --write-checksum would
// otherwise hand the apps a hash pinning the bundle before the edit.
//
// Only the curated file must carry one. Validating anything else -- a bundle
// someone is drafting, or an app repo's copy -- checks a checksum that sits
// beside it and stays quiet when none does.
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
      + " (re-run with --write-checksum, then copy both files to the apps)");
  }
}

const items = (data.chains ?? []).reduce((a, c) => a + (c.items?.length ?? 0), 0);
console.log(`${data.chains?.length ?? 0} chains, ${items} items, ${data.snacks?.length ?? 0} snacks, ${data.rules?.length ?? 0} rules`);
for (const w of warnings) console.log(`warning  ${w}`);
for (const e of errors) console.log(`ERROR    ${e}`);
// Written last, and only from an otherwise clean run: a checksum taken over a
// bundle that fails its own shape checks would freeze that failure into five
// app repos the moment someone copied both files across.
if (writeChecksum) {
  if (errors.length) console.log(`REFUSED to write ${basename(checksumPath)}: fix the ${errors.length} error(s) first`);
  else if (expectedSum === actualSum) console.log(`${basename(checksumPath)} already matches ${actualSum.slice(0, 12)}...`);
  else {
    writeFileSync(checksumPath, actualSum + "\n");
    console.log(`wrote ${basename(checksumPath)}: ${actualSum}`);
    console.log("copy road-food.json and road-food.sha256 together into each app repo");
  }
}
console.log(errors.length ? `FAILED: ${errors.length} error(s)` : `OK (${warnings.length} warning(s))`);
process.exit(errors.length ? 1 : 0);
