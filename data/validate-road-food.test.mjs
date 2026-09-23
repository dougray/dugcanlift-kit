// Unit tests for validate-road-food.mjs. The validator is a script, so each
// case writes a whole small bundle to a temp file and runs it, which is also
// how a curator uses it.
//
//   node --test data/
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
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
