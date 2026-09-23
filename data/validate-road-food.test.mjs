// Unit tests for validate-road-food.mjs. The validator is a script, so each
// case writes a whole small bundle to a temp file and runs it, which is also
// how a curator uses it.
//
//   node --test data/
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const DIR = mkdtempSync(join(tmpdir(), "road-food-validate-"));
let n = 0;

// A bundle that passes, so each case below changes exactly one thing.
const bundle = (chain = {}) => ({
  version: 1,
  chains: [{
    id: "achain", name: "A Chain", kind: "burgers", checkedOn: "2026-09-20",
    source: "https://example.com/nutrition.pdf",
    items: [{ id: "achain-burger", name: "Burger", serving: "1 sandwich", kcal: 300, proteinG: 20, fatG: 10, carbsG: 30 }],
    ...chain,
  }],
  snacks: [{
    id: "snack-jerky", category: "Beef jerky and meat sticks", brand: "Brand", name: "Jerky",
    serving: "1 oz", fdcId: 1, source: "https://fdc.nal.usda.gov/food-details/1/nutrients",
    checkedOn: "2026-09-19", kcal: 80, proteinG: 12, fatG: 1, carbsG: 6,
  }],
  rules: ["Grilled over fried", { text: "Read the label", kinds: ["snacks"] }],
});

function run(data) {
  const path = join(DIR, `b${n++}.json`);
  writeFileSync(path, JSON.stringify(data));
  const r = spawnSync(process.execPath, [join(HERE, "validate-road-food.mjs"), path], { encoding: "utf8" });
  return { code: r.status, out: (r.stdout ?? "") + (r.stderr ?? "") };
}

test("the fixture bundle passes, so every failure below is the one thing changed", () => {
  assert.equal(run(bundle()).code, 0);
});

test("publishedOn is optional: a chain whose document states no date is fine", () => {
  const r = run(bundle());
  assert.equal(r.code, 0);
  assert.doesNotMatch(r.out, /publishedOn/);
});

test("publishedOn takes a whole day or a month, and nothing else", () => {
  for (const good of ["2021-03-29", "2022-11", "2026-01"]) {
    assert.equal(run(bundle({ publishedOn: good })).code, 0, `${good} should pass`);
  }
  for (const bad of ["2022", "Nov 2022", "2022-13", "2022-00", "2021-02-30", "", null, 2022, "2022-11-", "22-11"]) {
    const r = run(bundle({ publishedOn: bad }));
    assert.equal(r.code, 1, `${JSON.stringify(bad)} should fail`);
    assert.match(r.out, /is not YYYY-MM-DD or YYYY-MM \(omit the key when the document states no date\)/);
  }
});

test("a document cannot have been published after the day someone read it", () => {
  // Read on 2026-09-20; a document dated after that is a typo, not a fact.
  const r = run(bundle({ publishedOn: "2026-10-01" }));
  assert.equal(r.code, 1);
  assert.match(r.out, /publishedOn 2026-10-01 is after checkedOn 2026-09-20/);
  // A month-only date is read as the first of that month, so September passes
  // and October does not.
  assert.equal(run(bundle({ publishedOn: "2026-09" })).code, 0);
  assert.equal(run(bundle({ publishedOn: "2026-10" })).code, 1);
});

test("a misspelled publishedOn is an unknown key, not a silently dropped date", () => {
  const r = run(bundle({ publishedDate: "2022-11" }));
  assert.equal(r.code, 1);
  assert.match(r.out, /unknown key "publishedDate"/);
});

test("the shipped bundle passes", () => {
  const r = spawnSync(process.execPath, [join(HERE, "validate-road-food.mjs")], { encoding: "utf8" });
  assert.equal(r.status, 0, r.stdout);
});

// MARK: - The checksum the app repos pin

// Writes a bundle and, unless `sum` is null, a road-food.sha256 beside it, so
// a case can hand the validator a matching, a stale or a hand-typed checksum.
// The file must be named road-food.json for the sibling to be found.
function runWithChecksum(data, sum, ...flags) {
  const dir = mkdtempSync(join(tmpdir(), "road-food-sum-"));
  const path = join(dir, "road-food.json");
  const text = JSON.stringify(data);
  writeFileSync(path, text);
  if (sum !== null) {
    writeFileSync(join(dir, "road-food.sha256"),
      (sum === "match" ? createHash("sha256").update(text).digest("hex") : sum) + "\n");
  }
  const r = spawnSync(process.execPath, [join(HERE, "validate-road-food.mjs"), path, ...flags], { encoding: "utf8" });
  const written = existsSync(join(dir, "road-food.sha256"))
    ? readFileSync(join(dir, "road-food.sha256"), "utf8").trim() : null;
  return { code: r.status, out: (r.stdout ?? "") + (r.stderr ?? ""), written };
}

test("a checksum that matches the bytes passes, and one that does not is an error", () => {
  assert.equal(runWithChecksum(bundle(), "match").code, 0);
  const stale = runWithChecksum(bundle(), "0".repeat(64));
  assert.equal(stale.code, 1);
  assert.match(stale.out, /road-food\.sha256 is stale/);
});

test("a checksum is over the bytes, so any edit at all moves it", () => {
  // The drift this exists to catch is not a malformed file -- a stale copy is
  // perfectly valid JSON in the spec's shape. It is only ever different bytes.
  const edited = bundle();
  edited.chains[0].items[0].kcal = 301;
  const dir = mkdtempSync(join(tmpdir(), "road-food-sum-"));
  const path = join(dir, "road-food.json");
  writeFileSync(path, JSON.stringify(bundle()));
  const r0 = spawnSync(process.execPath, [join(HERE, "validate-road-food.mjs"), path, "--write-checksum"], { encoding: "utf8" });
  assert.equal(r0.status, 0, r0.stdout);
  writeFileSync(path, JSON.stringify(edited));
  const r1 = spawnSync(process.execPath, [join(HERE, "validate-road-food.mjs"), path], { encoding: "utf8" });
  assert.equal(r1.status, 1, "one changed calorie must not pass the checksum");
  assert.match(r1.stdout, /stale/);
});

test("a hand-typed checksum is refused rather than trusted", () => {
  const r = runWithChecksum(bundle(), "not a hash");
  assert.equal(r.code, 1);
  assert.match(r.out, /is not a sha256 \(write it with --write-checksum, never by hand\)/);
});

test("a bundle with no checksum beside it is not an error, so a draft still validates", () => {
  // Only the curated file must carry one; `run` above relies on this for every
  // other case in this file.
  assert.equal(runWithChecksum(bundle(), null).code, 0);
});

test("--write-checksum writes the hash, and the file then validates", () => {
  const w = runWithChecksum(bundle(), null, "--write-checksum");
  assert.equal(w.code, 0);
  assert.equal(w.written, createHash("sha256").update(JSON.stringify(bundle())).digest("hex"));
  assert.match(w.out, /wrote road-food\.sha256/);
  assert.equal(runWithChecksum(bundle(), "match").code, 0);
});

test("--write-checksum refuses a bundle that fails its own checks", () => {
  // Freezing a hash over a broken bundle would copy the breakage into five
  // app repos, each of which would then agree with it.
  const r = runWithChecksum(bundle({ source: "http://example.com" }), null, "--write-checksum");
  assert.equal(r.code, 1);
  assert.equal(r.written, null, "nothing may be written from a failing run");
  assert.match(r.out, /REFUSED to write road-food\.sha256/);
});

test("the shipped checksum is the one the apps pin, and it is current", () => {
  // The guard itself: if this fails, data/road-food.sha256 was not re-written
  // after road-food.json changed, and every app repo is pinning the old bytes.
  const sum = readFileSync(join(HERE, "road-food.sha256"), "utf8").trim();
  assert.match(sum, /^[0-9a-f]{64}$/, "one bare sha256 and nothing else");
  assert.equal(sum, createHash("sha256").update(readFileSync(join(HERE, "road-food.json"))).digest("hex"));
});
