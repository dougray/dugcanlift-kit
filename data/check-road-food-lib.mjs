// Pure parts of the Road Food refresh check: reading numbers out of each kind
// of source, comparing them with the bundle, and writing the report. Nothing
// here touches the network or the disk, so all of it is unit-tested with
// fixtures (check-road-food.test.mjs). The fetching lives in
// check-road-food.mjs.
//
// Nothing here, or anywhere in the check, writes road-food.json. A number that
// moved is reported for a human to re-read at the source.

export const FIELDS = ["kcal", "proteinG", "fatG", "carbsG", "fiberG", "saturatedFatG", "sugarG", "sodiumMg"];

const LABEL = {
  kcal: "kcal", proteinG: "protein g", fatG: "fat g", carbsG: "carbs g", fiberG: "fiber g",
  saturatedFatG: "sat fat g", sugarG: "sugar g", sodiumMg: "sodium mg",
};

// ---------------------------------------------------------------- comparing

const same = (a, b) => (a === undefined && b === undefined)
  || (typeof a === "number" && typeof b === "number" && Math.abs(a - b) < 1e-9);

// Compares one bundled item with what the source says now. `found` holds only
// the fields the source carries; `fields` limits the comparison to what this
// source can speak for. Both directions count: a figure the source now
// publishes that the bundle leaves blank is a change a human should see, and
// so is one the source no longer gives.
export function compareItem(item, found, fields = FIELDS) {
  const diffs = [];
  for (const f of fields) {
    const old = item[f];
    const now = found[f];
    if (!same(old, now)) diffs.push({ field: f, old, now });
  }
  return diffs;
}

// "Hold the mayo to save 50 kcal" -> 50. Only the saving is machine-checkable.
export function modificationSaving(text) {
  const m = /save\s+(\d+(?:\.\d+)?)\s*kcal/i.exec(text ?? "");
  return m ? Number(m[1]) : undefined;
}

// --------------------------------------------------------------- PDF tables

// Normalises a row label so the locator can be written as the text reads:
// trademark marks, the ∆ "new item" marker and asterisks go, quotes and
// dashes fold, whitespace collapses, case is ignored.
export function normaliseLabel(s) {
  return s
    .replace(/[™®©∆*￼]/g, "")
    .replace(/[“”″]/g, '"').replace(/[‘’′]/g, "'")
    .replace(/[–—]/g, "-")
    .replace(/\s+/g, " ")
    .trim()
    .toLowerCase();
}

const VALUE = /^(<?\d+(\.\d+)?%?|n\/a|-)$/i;

// The table's cells at the end of a row: numbers, "<1", "N/A", "-".
function trailingValues(text) {
  const tokens = text.trim().split(/\s+/).filter(Boolean);
  const out = [];
  for (let i = tokens.length - 1; i >= 0 && VALUE.test(tokens[i]); i--) out.unshift(tokens[i]);
  return out;
}

function toNumber(token) {
  return /^\d+(\.\d+)?$/.test(token) ? Number(token) : undefined;
}

// Finds a row in a PDF's extracted text and reads its figures.
//
// locator: { row, after?, nth? }
//   row   - the row's label as printed, including any portion text the table
//           puts before the numbers ("TENDERS - BLACKENED 3 Pieces").
//   after - a line that must come first (a section heading), for labels a
//           table repeats ("Subway Club®" is a sandwich, a wrap and a bowl).
//   nth   - which match after that, 1-based (default 1).
// columns: the table's numeric columns in order; "_" for one not in the
//   bundle. Rows are read from the right, so a serving column holding words
//   or numbers before them does not shift anything.
//
// A label may wrap onto following lines, and a row's numbers may start on
// the next line (Panera does both). A label only matches when what follows it
// is a cell, not more words, so "6\" Grilled Chicken" never matches
// "6\" Grilled Chicken & Fresh Avocado".
//
// Returns { values } or { error }.
export function findPdfRow(text, locator, columns) {
  const lines = text.split(/\r?\n|\f/);
  const want = normaliseLabel(locator.row);
  let start = 0;
  if (locator.after) {
    const a = normaliseLabel(locator.after);
    const i = lines.findIndex((l) => normaliseLabel(l) === a);
    if (i < 0) return { error: `section heading "${locator.after}" not found` };
    start = i + 1;
  }
  let seen = 0;
  const nth = locator.nth ?? 1;
  for (let i = start; i < lines.length; i++) {
    if (!normaliseLabel(lines[i]).startsWith(want.slice(0, Math.min(want.length, 8)))) continue;
    // Join up to four lines to let a wrapped label match.
    let joined = "";
    for (let j = i; j < Math.min(lines.length, i + 4); j++) {
      joined = (joined ? joined + " " : "") + lines[j];
      const norm = normaliseLabel(joined);
      if (norm.length < want.length) continue;
      if (!norm.startsWith(want)) break;
      const rest = norm.slice(want.length).trim();
      if (rest && !/^[<\d.\-]|^n\/a/i.test(rest)) break;
      seen++;
      if (seen < nth) break;
      // Matched. Read cells from what follows, pulling in continuation lines
      // until the row has enough of them.
      let tail = rest;
      let k = j + 1;
      while (trailingValues(tail).length < columns.length && k < Math.min(lines.length, j + 4)) {
        tail = tail + " " + normaliseLabel(lines[k]);
        k++;
      }
      const cells = trailingValues(tail);
      if (cells.length < columns.length) {
        return { error: `row "${locator.row}" found but it has ${cells.length} cells, expected ${columns.length}` };
      }
      const row = cells.slice(cells.length - columns.length);
      const values = {};
      columns.forEach((c, idx) => {
        if (c === "_") return;
        const n = toNumber(row[idx]);
        if (n !== undefined) values[c] = n;
      });
      return { values, cells: row };
    }
  }
  return { error: `row "${locator.row}" not found${locator.after ? ` after "${locator.after}"` : ""}` };
}

// ----------------------------------------------------------- Chick-fil-A page

const CFA_FIELDS = {
  "Calories": "kcal", "Fat (g)": "fatG", "Sat. Fat (g)": "saturatedFatG", "Sodium (mg)": "sodiumMg",
  "Carbohydrates (g)": "carbsG", "Fiber (g)": "fiberG", "Sugar (g)": "sugarG", "Protein (g)": "proteinG",
};

// The nutrition table is embedded in the page as WordPress Interactivity API
// state: tableData.nutrition is a list of { menu, items }, each item
// { title, fields, sub_items }, each field { label, value }.
export function parseChickFilA(html) {
  const m = /<script[^>]*id="wp-script-module-data-@wordpress\/interactivity"[^>]*>([\s\S]*?)<\/script>/.exec(html);
  if (!m) return { error: "the page no longer embeds its nutrition table as JSON" };
  let state;
  try { state = JSON.parse(m[1]); } catch { return { error: "the embedded nutrition JSON does not parse" }; }
  const sections = state?.state?.["nutrition-allergens-table-store"]?.tableData?.nutrition;
  if (!Array.isArray(sections)) return { error: "the embedded JSON has no nutrition table" };
  const rows = [];
  for (const sec of sections) {
    const visit = (it) => {
      const values = {};
      for (const f of it.fields ?? []) {
        const key = CFA_FIELDS[f.label];
        if (key && typeof f.value === "number") values[key] = f.value;
      }
      rows.push({ section: sec.menu, title: it.title, values });
      for (const s of it.sub_items ?? []) visit(s);
    };
    for (const it of sec.items ?? []) visit(it);
  }
  return { rows };
}

export function findChickFilARow(rows, locator) {
  const want = normaliseLabel(locator.row);
  const hits = rows.filter((r) => normaliseLabel(r.title) === want
    && (!locator.section || normaliseLabel(r.section) === normaliseLabel(locator.section)));
  if (!hits.length) return { error: `row "${locator.row}" not found${locator.section ? ` in "${locator.section}"` : ""}` };
  return { values: hits[0].values };
}

// ------------------------------------------------------ Nutritionix menu grid

// Taco Bell and Sheetz publish their full food nutrition only through the
// Nutritionix calculator their own nutrition page embeds. That widget's menu
// grid is server-rendered HTML: a `<tr class="subCategory">` per section
// heading, then one row per item whose first cell holds
// `<a class="nmItem" title="...">` and whose remaining `<td class="col">`
// cells are the table's columns, left to right, exactly as `columns` lists
// them.
//
// The widget stamps fresh element ids into every response, so the page's
// bytes say nothing about whether the figures moved; only the numbers and the
// "Last Updated" date it prints are worth comparing.
const stripTags = (s) => String(s).replace(/<[^>]*>/g, " ");
const unescapeHtml = (s) => String(s)
  .replace(/&nbsp;/gi, " ").replace(/&amp;/gi, "&").replace(/&lt;/gi, "<")
  .replace(/&gt;/gi, ">").replace(/&quot;/gi, '"').replace(/&#0?39;|&apos;/gi, "'")
  .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)));
const text = (s) => unescapeHtml(stripTags(s)).replace(/\s+/g, " ").trim();

// A grid cell holds a number, a thousands-separated number, or a censored one
// ("< 1"). Only a real number is a figure; "< 1" is neither a number nor a
// blank, which is why no bundled item carries a field the grid censors.
function gridNumber(cell) {
  const t = cell.replace(/,/g, "").trim();
  return /^\d+(\.\d+)?$/.test(t) ? Number(t) : undefined;
}

export function parseNutritionixGrid(html) {
  const rows = [];
  let section;
  for (const tr of String(html).split(/<tr\b/i).slice(1)) {
    const head = /class="subCategory"[\s\S]*?<h3>([\s\S]*?)<\/h3>/i.exec(tr);
    if (head) { section = text(head[1]); continue; }
    const name = /<a[^>]*class="nmItem"[^>]*title="([^"]*)"/i.exec(tr);
    if (!name) continue;
    const cells = [...tr.matchAll(/<td[^>]*class="col"[^>]*>([\s\S]*?)<\/td>/gi)].map((m) => text(m[1]));
    rows.push({ section, title: unescapeHtml(name[1]).trim(), cells });
  }
  return rows.length ? { rows } : { error: "the page no longer renders a Nutritionix menu grid" };
}

// locator: { row, section? }. The grid repeats an item in every section it
// belongs to; identical repeats are the same row, and repeats that disagree
// are a real ambiguity a `section` has to settle rather than a first-match.
export function findNutritionixRow(rows, locator, columns) {
  const want = normaliseLabel(locator.row);
  const hits = rows.filter((r) => normaliseLabel(r.title) === want
    && (!locator.section || normaliseLabel(r.section ?? "") === normaliseLabel(locator.section)));
  if (!hits.length) {
    return { error: `row "${locator.row}" not found${locator.section ? ` in "${locator.section}"` : ""}` };
  }
  if (new Set(hits.map((h) => h.cells.join("|"))).size > 1) {
    return { error: `row "${locator.row}" appears ${hits.length} times with different figures; name a "section"` };
  }
  const cells = hits[0].cells;
  if (cells.length !== columns.length) {
    return { error: `row "${locator.row}" has ${cells.length} cells, expected ${columns.length}` };
  }
  const values = {};
  columns.forEach((c, i) => {
    if (c === "_") return;
    const n = gridNumber(cells[i]);
    if (n !== undefined) values[c] = n;
  });
  return { values, cells };
}

// Does the chain's own nutrition page still embed this widget? That embed is
// the whole reason the widget's figures count as the chain's own published
// ones, so it is checked, not assumed.
export function embedsWidget(html, embed) {
  return String(html).includes(embed);
}

// ----------------------------------------------------------------- Starbucks

// /apiproxy/v1/ordering/{product}/{form}: products[0].sizes[], each with a
// nutrition panel whose additionalFacts carry the macros and whose subfacts
// carry saturated fat, fibre and sugar.
export function parseStarbucks(json, sizeName) {
  const p = json?.products?.[0];
  if (!p || !Array.isArray(p.sizes)) return { error: "no product in the response" };
  const size = sizeName ? p.sizes.find((s) => s.name === sizeName) : p.sizes[0];
  if (!size) return { error: `size "${sizeName}" is not offered (sizes: ${p.sizes.map((s) => s.name).join(", ")})` };
  const n = size.nutrition;
  if (!n) return { error: "the size has no nutrition panel" };
  const values = {};
  const kcal = n.calories?.displayValue;
  if (typeof kcal === "number") values.kcal = kcal;
  const map = { totalFat: "fatG", sodium: "sodiumMg", totalCarbs: "carbsG", protein: "proteinG",
    saturatedFat: "saturatedFatG", dietaryFiber: "fiberG", sugars: "sugarG" };
  for (const f of n.additionalFacts ?? []) {
    if (map[f.id] && typeof f.value === "number") values[map[f.id]] = f.value;
    for (const s of f.subfacts ?? []) if (map[s.id] && typeof s.value === "number") values[map[s.id]] = s.value;
  }
  return { values, name: p.name };
}

// ------------------------------------------------------------------- Wendy's

// The menu feed (menu/getSiteMenu, national menu) names each sales item's
// product id and default components. The order site's nutrition panel asks
// NutritionServices/rest/nutritionalData for exactly that build, which is how
// the bundled figures were read; the feed's own per-item panel has no carbs.
export function wendysRequest(menu, salesItemId, { without } = {}) {
  const lists = menu?.menuLists;
  if (!lists?.salesItems) return { error: "the menu feed has no sales items" };
  const item = lists.salesItems.find((s) => s.salesItemId === salesItemId);
  if (!item) return { error: `sales item ${salesItemId} is not on the national menu` };
  const mods = new Map((lists.modifiers ?? []).map((m) => [m.modifierId, m]));
  const components = [];
  let removed = false;
  for (const o of item.defaultOptions ?? []) {
    const m = mods.get(o.modifierId);
    if (!m) return { error: `sales item ${salesItemId} names modifier ${o.modifierId}, which the feed lacks` };
    if (without && normaliseLabel(m.name) === normaliseLabel(without)) { removed = true; continue; }
    components.push({ id: m.componentId, quantity: o.defaultQuantity || 1, ...(o.modifierAction ? { action: o.modifierAction } : {}) });
  }
  if (without && !removed) return { error: `"${without}" is not a default component of sales item ${salesItemId}` };
  return { data: { siteNum: 0, products: [{ id: item.productId, components }] }, name: item.displayName ?? item.name };
}

export function parseWendysNutrition(json) {
  if (json?.serviceStatus !== "SUCCESS" || !json.data) {
    return { error: `the nutrition service said ${json?.serviceStatus ?? "nothing"}${json?.serviceMessages ? `: ${json.serviceMessages.join(" ")}` : ""}` };
  }
  const d = json.data;
  const map = { calories: "kcal", protein: "proteinG", totalFat: "fatG", carbohydrates: "carbsG",
    dietaryFiber: "fiberG", saturated: "saturatedFatG", sugars: "sugarG", sodium: "sodiumMg" };
  const values = {};
  for (const [k, f] of Object.entries(map)) if (typeof d[k] === "number") values[f] = d[k];
  return { values };
}

// ------------------------------------------------------ FoodData Central

// FDA label rounding (21 CFR 101.9), the rule every snack figure was made
// with: per-100 g value x serving, to one decimal, then rounded as a label
// would print it. Under 1 g of a gram nutrient is "less than 1 g", which the
// bundle leaves blank.
const near = (v, step) => Math.round(v / step) * step;
export const labelRound = {
  kcal: (v) => (v < 5 ? 0 : v <= 50 ? near(v, 5) : near(v, 10)),
  fat: (v) => (v < 0.5 ? 0 : v < 5 ? near(v, 0.5) : near(v, 1)),
  gram: (v) => (v < 0.5 ? 0 : v < 1 ? undefined : near(v, 1)),
  sodium: (v) => (v < 5 ? 0 : v <= 140 ? near(v, 5) : near(v, 10)),
};
const FDC_NUTRIENTS = {
  "208": ["kcal", labelRound.kcal], "203": ["proteinG", labelRound.gram], "204": ["fatG", labelRound.fat],
  "205": ["carbsG", labelRound.gram], "291": ["fiberG", labelRound.gram], "606": ["saturatedFatG", labelRound.fat],
  "269": ["sugarG", labelRound.gram], "307": ["sodiumMg", labelRound.sodium],
};

// `abridged` supplies per-100 values by nutrient number; `full` supplies the
// serving size, the discontinued date and the update log (every record FDC
// holds for the same product, newest first). These are the shapes FDC's API
// returned; `readBrandedFoods` builds the same two from USDA's bulk CSVs, so
// the derivation itself did not change when the API was dropped.
export function deriveSnack(abridged, full) {
  const serving = full?.servingSize;
  if (typeof serving !== "number" || serving <= 0) return { error: "the FDC record has no serving size" };
  const values = {};
  for (const n of abridged?.foodNutrients ?? []) {
    const spec = FDC_NUTRIENTS[n.number];
    if (!spec || typeof n.amount !== "number") continue;
    const perServing = Math.round((n.amount * serving) / 100 * 10) / 10;
    const v = spec[1](perServing);
    if (v !== undefined) values[spec[0]] = v;
  }
  return { values };
}

// FDC's API wrote dates M/D/YYYY; its bulk CSVs write YYYY-MM-DD.
export function fdcDate(s) {
  const iso = /^(\d{4})-(\d{2})-(\d{2})/.exec(s ?? "");
  if (iso) return `${iso[1]}-${iso[2]}-${iso[3]}`;
  const m = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(s ?? "");
  return m ? `${m[3]}-${m[1].padStart(2, "0")}-${m[2].padStart(2, "0")}` : undefined;
}

// A newer record for the same product means the manufacturer resubmitted its
// label. The bundle is pinned to one fdcId, so this is how a snack "changes".
export function newerFdcRecords(full) {
  const mine = fdcDate(full?.publicationDate);
  return (full?.foodUpdateLog ?? [])
    .filter((r) => r.fdcId !== full.fdcId && mine && fdcDate(r.publicationDate) > mine)
    .map((r) => ({ fdcId: r.fdcId, published: fdcDate(r.publicationDate), description: r.description }));
}

// ------------------------------------------ FoodData Central bulk CSVs

// USDA's Branded Foods download (FoodData_Central_branded_food_csv_<date>.zip,
// public domain, no key) is a set of CSVs. The check reads four, by column
// name, so a column USDA adds or reorders changes nothing. The names are the
// ones USDA's "Download Field Descriptions" gives:
//
//   nutrient.csv       id, nutrient_nbr: food_nutrient's nutrient_id is
//                      nutrient.id, and the API's "number" was nutrient_nbr
//   branded_food.csv   fdc_id, gtin_upc, serving_size, serving_size_unit,
//                      discontinued_date
//   food.csv           fdc_id, description, publication_date
//   food_nutrient.csv  fdc_id, nutrient_id, amount (per 100 g or 100 ml)
export const BRANDED_COLUMNS = {
  "nutrient.csv": ["id", "nutrient_nbr"],
  "branded_food.csv": ["fdc_id", "gtin_upc", "serving_size", "serving_size_unit", "discontinued_date"],
  "food.csv": ["fdc_id", "description", "publication_date"],
  "food_nutrient.csv": ["fdc_id", "nutrient_id", "amount"],
};

// One CSV record, starting at `i`. Returns [fields, next], or null when the
// text ends before the record does and more may follow. RFC 4180: a quoted
// field may hold commas, newlines and "" for a quote.
function csvRecord(s, i, final) {
  const fields = [];
  const n = s.length;
  for (;;) {
    let value = "";
    if (i < n && s.charCodeAt(i) === 34) {
      let j = i + 1;
      for (;;) {
        const q = s.indexOf('"', j);
        if (q < 0 || (q + 1 >= n && !final)) return null;
        if (s.charCodeAt(q + 1) === 34) { value += s.slice(j, q + 1); j = q + 2; continue; }
        value += s.slice(j, q);
        i = q + 1;
        break;
      }
    }
    // Unquoted text, or anything stray after a closing quote, runs to the
    // next delimiter.
    let j = i;
    while (j < n) {
      const c = s.charCodeAt(j);
      if (c === 44 || c === 10 || c === 13) break;
      j++;
    }
    if (j >= n && !final) return null;
    value += s.slice(i, j);
    fields.push(value);
    i = j;
    if (i >= n) return [fields, i];
    const c = s.charCodeAt(i);
    if (c === 44) { i++; continue; }
    if (c === 13) {
      if (i + 1 >= n && !final) return null;
      return [fields, s.charCodeAt(i + 1) === 10 ? i + 2 : i + 1];
    }
    return [fields, i + 1];
  }
}

// Every record of a CSV, from an iterable (or async iterable) of Buffer or
// string chunks, as arrays of strings. A blank line is skipped, and a byte
// order mark is dropped. A chunk boundary can fall anywhere, including inside
// a UTF-8 character or a quoted field.
export async function* csvRows(chunks) {
  const decoder = new TextDecoder("utf-8");
  let buf = "";
  let first = true;
  const drain = (final) => {
    const out = [];
    let i = 0;
    while (i < buf.length) {
      const r = csvRecord(buf, i, final);
      if (!r) break;
      i = r[1];
      if (r[0].length === 1 && r[0][0] === "") continue;
      out.push(r[0]);
    }
    buf = buf.slice(i);
    return out;
  };
  for await (const chunk of chunks) {
    buf += typeof chunk === "string" ? chunk : decoder.decode(chunk, { stream: true });
    if (first && buf.length) {
      if (buf.charCodeAt(0) === 0xfeff) buf = buf.slice(1);
      first = false;
    }
    yield* drain(false);
  }
  buf += decoder.decode();
  if (first && buf.charCodeAt(0) === 0xfeff) buf = buf.slice(1);
  yield* drain(true);
}

// Calls `fn` with an object of the `needed` columns for every row, after
// checking the header names every one of them. `keep(value)` filters on the
// first needed column before an object is built, which keeps reading
// food_nutrient.csv's millions of rows for 22 products cheap.
async function eachRow(name, chunks, needed, fn, keep) {
  let idx;
  for await (const row of csvRows(chunks)) {
    if (!idx) {
      idx = needed.map((c) => row.indexOf(c));
      const missing = needed.filter((_, k) => idx[k] < 0);
      if (missing.length) throw new Error(`${name} has no ${missing.join(", ")} column (its header: ${row.join(", ")})`);
      continue;
    }
    if (keep && !keep(row[idx[0]] ?? "")) continue;
    const o = {};
    needed.forEach((c, k) => { o[c] = row[idx[k]] ?? ""; });
    fn(o);
  }
  if (!idx) throw new Error(`${name} is empty`);
}

// A barcode as one key: digits only, leading zeros dropped, so FDC's UPC-A,
// EAN-13 and GTIN-14 spellings of one product match ("normalise when
// matching", SOURCES.md "Snacks").
export function gtinKey(code) {
  const d = String(code ?? "").replace(/[\s-]/g, "");
  if (!/^\d+$/.test(d)) return undefined;
  return d.replace(/^0+/, "") || undefined;
}

// "208", "208.0" and " 208" are one nutrient number; "269.3" is another.
const nutrientNumber = (s) => {
  const t = String(s ?? "").trim();
  return /^\d+(\.\d+)?$/.test(t) ? String(Number(t)) : t;
};
const csvNumber = (s) => {
  const t = String(s ?? "").trim();
  if (!t) return undefined;
  const n = Number(t);
  return Number.isFinite(n) ? n : undefined;
};

// Reads the records the check needs out of the bulk CSVs.
//
// `open(fileName)` gives that CSV's chunks (from the zip, or a fixture), and
// may be called more than once for a file. `snacks` are the bundle's entries:
// their `fdcId`s, and their `barcode`s for finding other records of the same
// product.
//
// Returns { records, byBarcode }. `records` maps each fdcId the file holds to
// { abridged, full }, the shapes `deriveSnack` and `newerFdcRecords` read.
// `full.foodUpdateLog` is every record in the file with the same product's
// GTIN, newest first: USDA's field descriptions say "Duplicate codes signify
// an update to the product, use the publication_date found in the food table
// to distinguish when each update was published". `byBarcode` maps each
// bundled barcode's key to the records the file holds for it, which is what a
// snack whose own record is gone is reported with.
export async function readBrandedFoods(open, snacks) {
  const nbr = new Map();
  await eachRow("nutrient.csv", open("nutrient.csv"), BRANDED_COLUMNS["nutrient.csv"],
    (r) => nbr.set(r.id.trim(), nutrientNumber(r.nutrient_nbr)));

  const targets = new Set(snacks.map((s) => String(s.fdcId)));
  const keys = new Set(snacks.map((s) => gtinKey(s.barcode)).filter(Boolean));
  const branded = new Map();
  const readBranded = (wantKeys) => eachRow("branded_food.csv", open("branded_food.csv"),
    BRANDED_COLUMNS["branded_food.csv"], (r) => {
      const id = r.fdc_id.trim();
      if (targets.has(id) || wantKeys.has(gtinKey(r.gtin_upc))) branded.set(id, r);
    });
  await readBranded(keys);
  // A record whose own GTIN is not the barcode the bundle records needs a
  // second pass to find its product's other records. None is expected.
  const extra = new Set([...targets].map((id) => gtinKey(branded.get(id)?.gtin_upc)).filter((k) => k && !keys.has(k)));
  if (extra.size) {
    await readBranded(extra);
    for (const k of extra) keys.add(k);
  }

  const food = new Map();
  await eachRow("food.csv", open("food.csv"), BRANDED_COLUMNS["food.csv"],
    (r) => food.set(r.fdc_id.trim(), r), (id) => branded.has(id.trim()));

  const nutrients = new Map();
  await eachRow("food_nutrient.csv", open("food_nutrient.csv"), BRANDED_COLUMNS["food_nutrient.csv"], (r) => {
    const number = nbr.get(r.nutrient_id.trim());
    const amount = csvNumber(r.amount);
    if (number === undefined || amount === undefined) return;
    const id = r.fdc_id.trim();
    if (!nutrients.has(id)) nutrients.set(id, []);
    nutrients.get(id).push({ number, amount });
  }, (id) => targets.has(id.trim()));

  const entry = (id) => {
    const b = branded.get(id), f = food.get(id);
    return { fdcId: Number(id), description: f?.description, publicationDate: f?.publication_date.trim() || undefined,
      gtinUpc: b.gtin_upc, discontinuedDate: b.discontinued_date.trim() || undefined };
  };
  const newestFirst = (a, b) => (fdcDate(b.publicationDate) ?? "").localeCompare(fdcDate(a.publicationDate) ?? "")
    || b.fdcId - a.fdcId;
  const byBarcode = new Map();
  for (const id of branded.keys()) {
    const k = gtinKey(branded.get(id).gtin_upc);
    if (!k || !keys.has(k)) continue;
    if (!byBarcode.has(k)) byBarcode.set(k, []);
    byBarcode.get(k).push(entry(id));
  }
  for (const list of byBarcode.values()) list.sort(newestFirst);

  const records = new Map();
  for (const id of targets) {
    const b = branded.get(id);
    if (!b) continue;
    records.set(Number(id), {
      abridged: { fdcId: Number(id), foodNutrients: nutrients.get(id) ?? [] },
      full: { ...entry(id), servingSize: csvNumber(b.serving_size), servingSizeUnit: b.serving_size_unit.trim() || undefined,
        foodUpdateLog: byBarcode.get(gtinKey(b.gtin_upc)) ?? [] },
    });
  }
  return { records, byBarcode };
}

// The release date in USDA's own file name, FoodData_Central_branded_food_csv_<date>.zip.
export function brandedRelease(fileName) {
  return /branded_food_csv_(\d{4}-\d{2}-\d{2})/.exec(fileName ?? "")?.[1];
}

// One snack against its record in the bulk file.
export function compareSnack(snack, record, byBarcode = new Map()) {
  const base = { id: snack.id, name: snack.name };
  if (!record) {
    const others = byBarcode.get(gtinKey(snack.barcode)) ?? [];
    const also = others.length
      ? `; the file holds ${others.length} record(s) with its barcode ${snack.barcode}: ${others.map((o) =>
        `${o.fdcId} (${fdcDate(o.publicationDate) ?? "no date"}${o.discontinuedDate ? `, discontinued ${o.discontinuedDate}` : ""})`).join(", ")}`
      : "";
    return { ...base, missing: `record ${snack.fdcId} is not in the Branded Foods file${also}` };
  }
  const d = deriveSnack(record.abridged, record.full);
  if (d.error) return { ...base, missing: d.error };
  const full = record.full;
  const diffs = compareItem(snack, d.values);
  for (const n of newerFdcRecords(full)) {
    diffs.push({ field: "fdcId", label: "newer FDC record for this product", old: `${snack.fdcId} (${fdcDate(full.publicationDate)})`, now: `${n.fdcId} (${n.published})` });
  }
  if (full.discontinuedDate) diffs.push({ field: "discontinued", label: "discontinued", old: "no", now: full.discontinuedDate });
  const notes = [];
  if (!fdcDate(full.publicationDate)) notes.push("food.csv gives this record no publication date, so newer records were not looked for");
  return { ...base, compared: true, diffs, notes };
}

// The snacks' result, in the same shape as a chain's.
//   bulk undefined   no file given: "can't compare automatically", which does not fail the run
//   bulk { error }   a file was given and could not be read: fails the run
//   bulk { records, byBarcode, file?, release? }
export function checkSnacks(snacks, bulk) {
  const r = { id: "snacks", name: "Snacks (FoodData Central)", checkedOn: snacks.map((s) => s.checkedOn).sort()[0],
    items: [], signals: [], unreachable: [] };
  if (!bulk) {
    r.manual = true;
    r.manualWhy = "no USDA Branded Foods CSV zip was given (`--fdc-branded <zip>` or `FDC_BRANDED_ZIP`); data/README.md, \"Quarterly refresh\", says where to get it";
    r.manualNote = "Not compared: no USDA Branded Foods file given";
    r.items = snacks.map((s) => ({ id: s.id, name: s.name, error: "no Branded Foods file given" }));
  } else if (bulk.error) {
    r.unreachable.push(`couldn't read ${bulk.file ?? "the Branded Foods file"}: ${bulk.error}`);
    r.items = snacks.map((s) => ({ id: s.id, name: s.name, error: "Branded Foods file not read" }));
  } else {
    r.signals.push(`Read from USDA's Branded Foods bulk file${bulk.file ? ` ${bulk.file}` : ""}${bulk.release ? ` (release ${bulk.release})` : ""}; no API, no key.`);
    r.signals.push("Each product is re-derived from its FDC record (per-100 g figure x serving, then FDA label rounding), and the file is searched for a newer record with the same GTIN.");
    const newest = snacks.map((s) => s.checkedOn).sort().at(-1);
    if (bulk.release && newest && bulk.release < newest) {
      r.signals.push(`**This release (${bulk.release}) is older than the newest snack checkedOn (${newest})**: USDA refreshes the bulk file twice a year, so a difference may be the file's age rather than the product's. Use the newest release.`);
    }
    r.items = snacks.map((s) => compareSnack(s, bulk.records.get(Number(s.fdcId)), bulk.byBarcode));
  }
  r.verdict = chainVerdict(r);
  return r;
}

// ---------------------------------------------------------------- dates

// Six calendar months, not 182 days. 31 March plus six months is 30 September,
// clamped to the month's end, which is what all three apps do
// (`road-food.js`, `RoadFood.kt`, `RoadFoodRanking.swift`). Date.UTC on its own
// rolls that to 1 October, so this clamps it back rather than disagreeing with
// every screen that shows the answer.
export function isStale(day, today) {
  const [y, m, d] = docDateDay(day).split("-").map(Number);
  const limit = new Date(Date.UTC(y, m - 1 + 6, d));
  if (limit.getUTCDate() !== d) limit.setUTCDate(0);
  return new Date(today + "T00:00:00Z") > limit;
}

const MONTHS = ["january", "february", "march", "april", "may", "june",
  "july", "august", "september", "october", "november", "december"];

// Every way a document plausibly prints the date the bundle records for it.
// `publishedOn` is "YYYY-MM-DD" or "YYYY-MM"; a month-only date gets only the
// month-and-year renderings, because that is all the document said.
export function dateStatements(publishedOn) {
  const [y, m, d] = publishedOn.split("-");
  const full = MONTHS[Number(m) - 1];
  const abbr = full.slice(0, 3);
  const out = [`${y}-${m}`, `${full} ${y}`, `${abbr} ${y}`, `${abbr}-${y}`,
    `${Number(m)}/${y}`, `${m}/${y}`];
  if (d) {
    const dn = Number(d);
    out.push(publishedOn, `${full} ${dn}, ${y}`, `${abbr} ${dn}, ${y}`, `${full} ${dn} ${y}`,
      `${dn} ${full} ${y}`, `${dn} ${abbr} ${y}`,
      `${Number(m)}/${dn}/${y}`, `${Number(m)}/${d}/${y}`, `${m}/${dn}/${y}`, `${m}/${d}/${y}`,
      // Dunkin' writes "last updated on 09-21-2026", month first with dashes.
      `${m}-${d}-${y}`, `${Number(m)}-${dn}-${y}`);
  }
  return out;
}

// Does the document still say about itself what `publishedOn` records? True,
// false, or undefined when there is nothing to read. This only ever asks
// whether the recorded statement is still there: it never reads a new date out
// of the document, because a wrong date read by machine is worse than a
// missing one a person goes and looks up.
export function statesPublished(text, publishedOn) {
  if (!publishedOn || typeof text !== "string" || !text.trim()) return undefined;
  const hay = text.toLowerCase().replace(/\s+/g, " ");
  return dateStatements(publishedOn).some((c) => hay.includes(c.toLowerCase()));
}

// A month-only date is read as the first of that month, which can only ever
// make a document look older, never fresher. The apps do exactly the same.
export function docDateDay(publishedOn) {
  return publishedOn.length === 7 ? `${publishedOn}-01` : publishedOn;
}

// Whole calendar months between a document's own date and today, rounded down.
export function monthsOld(publishedOn, today) {
  const [y, m, d] = docDateDay(publishedOn).split("-").map(Number);
  const [ty, tm, td] = today.split("-").map(Number);
  let n = (ty - y) * 12 + (tm - m);
  if (td < d) n -= 1;
  return n;
}

// "Last-Modified" is the server's own claim; it can only ever say "not
// touched since", never "the numbers are the same".
export function modifiedAfter(lastModified, checkedOn) {
  if (!lastModified) return undefined;
  const t = Date.parse(lastModified);
  if (Number.isNaN(t)) return undefined;
  return new Date(t).toISOString().slice(0, 10) > checkedOn;
}

// ---------------------------------------------------------------- verdicts

// Folds item results and fetch facts into one verdict per chain.
//   unreachable - a source could not be fetched (why is kept)
//   changed     - a compared number differs, or a bundled row is gone
//   manual      - the source cannot be read automatically; `docChanged` says
//                 whether the document changed since checkedOn
//                 (true/false/undefined), which the report states in words.
//                 Even an undated-since document stays "manual": its numbers
//                 were not read, so it is never reported as unchanged.
//   unchanged   - every compared number matches
export function chainVerdict(r) {
  if (r.unreachable?.length) return "unreachable";
  if (r.items.some((i) => i.diffs?.length || i.missing)) return "changed";
  if (r.manual) return "manual";
  if (r.items.some((i) => i.error)) return "manual";
  return "unchanged";
}

export function exitCode(results, validator) {
  // A document that no longer states the date the bundle records has been
  // republished: `publishedOn` is now wrong, which is a number-grade error.
  if (results.some((r) => r.publishedStated === false)) return 1;
  if (results.some((r) => ["changed", "unreachable"].includes(r.verdict))) return 1;
  if (validator && validator.code !== 0) return 2;
  return 0;
}

// ---------------------------------------------------------------- report

function manualNote(r) {
  if (r.manualNote) return r.manualNote;
  if (r.docChanged === true) return "**Document changed since it was checked: re-read by hand**";
  if (r.docChanged === false) return "Document not modified since it was checked (server's Last-Modified): nothing to re-read";
  return "Can't tell whether the document changed: re-read by hand";
}

const fmt = (v) => (v === undefined ? "blank" : String(v));
const HEAD = {
  unchanged: "unchanged",
  changed: "CHANGED",
  unreachable: "COULDN'T REACH",
  manual: "can't compare automatically",
};

export function renderReport({ results, stale, validator, ranAt, bundle, pdfExtractor }) {
  const out = [];
  const count = (v) => results.filter((r) => r.verdict === v).length;
  out.push("# Road Food refresh check", "");
  out.push(`Run ${ranAt} against \`data/road-food.json\` (${bundle.chains} chains, ${bundle.items} items, ${bundle.snacks} snacks).`);
  out.push("Generated by `node data/check-road-food.mjs`; overwritten each run. This check never edits the bundle:");
  out.push("a figure that moved is re-read at the source and changed by hand, with a new `checkedOn`.", "");
  out.push(`**${count("changed")} changed, ${count("unreachable")} couldn't reach, ${count("manual")} can't compare automatically, ${count("unchanged")} unchanged.**`, "");

  out.push("| Source | Result | checkedOn | Items compared | Notes |", "|---|---|---|---|---|");
  for (const r of results) {
    const compared = r.items.filter((i) => i.compared).length;
    const note = r.verdict === "unreachable" ? r.unreachable[0]
      : r.verdict === "changed" ? `${r.items.filter((i) => i.diffs?.length || i.missing).length} item(s) differ`
        : r.verdict === "manual" ? manualNote(r)
          : "every number matches";
    out.push(`| ${r.name} | ${HEAD[r.verdict]} | ${r.checkedOn} | ${compared} of ${r.items.length} | ${note.replace(/\|/g, "\\|")} |`);
  }
  out.push("");

  out.push("## Document dates", "");
  out.push("What each chain's own document says about its own date (`publishedOn`), and whether");
  out.push("it still says it. A document that states no date has no `publishedOn`, and the apps");
  out.push("fall back to `checkedOn` for it.", "");
  out.push("| Source | publishedOn | Age | Still stated? |", "|---|---|---|---|");
  for (const r of results) {
    if (r.id === "snacks") continue;
    const m = r.publishedOn ? monthsOld(r.publishedOn, ranAt.slice(0, 10)) : undefined;
    const age = m === undefined ? "-" : `${m} month${m === 1 ? "" : "s"}`;
    const still = r.publishedOn === undefined ? "the document states no date"
      : r.publishedStated === undefined ? "not read this run"
        : r.publishedStated ? "yes" : "**NO - re-read it by hand**";
    out.push(`| ${r.name} | ${r.publishedOn ?? "-"} | ${age} | ${still} |`);
  }
  out.push("");

  out.push("## Over six months since checked", "");
  if (!stale.length) out.push("None.");
  else for (const s of stale) out.push(`- ${s.name}: checked ${s.checkedOn}`);
  out.push("");

  const order = ["changed", "unreachable", "manual", "unchanged"];
  out.push("## Detail", "");
  for (const v of order) {
    for (const r of results.filter((x) => x.verdict === v)) {
      out.push(`### ${r.name}: ${HEAD[r.verdict]}`, "");
      for (const u of r.unreachable ?? []) out.push(`- Couldn't reach: ${u}`);
      if (r.manual) out.push(`- Not read automatically: ${r.manualWhy}.`);
      if (r.manual && !r.unreachable?.length) out.push(`- ${manualNote(r)}.`);
      for (const s of r.signals ?? []) out.push(`- ${s}`);
      for (const i of r.items) {
        if (i.missing) out.push(`- **${i.name}** (\`${i.id}\`): ${i.missing}`);
        else if (i.diffs?.length) {
          out.push(`- **${i.name}** (\`${i.id}\`):`);
          for (const d of i.diffs) out.push(`  - ${d.label ?? LABEL[d.field] ?? d.field}: ${fmt(d.old)} → ${fmt(d.now)}`);
        } else if (i.error) out.push(`- ${i.name} (\`${i.id}\`): not compared (${i.error})`);
        for (const n of i.notes ?? []) out.push(`- ${i.name} (\`${i.id}\`): ${n}`);
      }
      out.push("");
    }
  }

  out.push("## Validator", "");
  out.push(`\`node data/validate-road-food.mjs\` exited ${validator.code}.`, "", "```", validator.output.trim(), "```", "");
  if (pdfExtractor) out.push(`PDF text was extracted with ${pdfExtractor}.`, "");
  return out.join("\n");
}

// Plain stdout summary: one line per source, then every difference.
export function renderSummary(results, stale, validator) {
  const lines = [];
  for (const r of results) {
    lines.push(`${HEAD[r.verdict].padEnd(28)} ${r.name}${r.verdict === "unreachable" ? ` - ${r.unreachable[0]}` : ""}${r.verdict === "manual" ? ` - ${manualNote(r).replace(/\*\*/g, "")}` : ""}`);
    for (const i of r.items) {
      if (i.missing) lines.push(`    ${i.id}: ${i.missing}`);
      for (const d of i.diffs ?? []) lines.push(`    ${i.id}: ${d.label ?? LABEL[d.field] ?? d.field} ${fmt(d.old)} -> ${fmt(d.now)}`);
    }
  }
  for (const r of results) {
    if (r.publishedStated === false) lines.push(`DOCUMENT DATE MOVED          ${r.name}: no longer states ${r.publishedOn}`);
  }
  for (const s of stale) lines.push(`STALE                        ${s.name}: checked ${s.checkedOn}`);
  lines.push(`validator                    exit ${validator.code}`);
  return lines.join("\n");
}
