#!/usr/bin/env node
// Road Food refresh check. For every chain in road-food.json, fetch the source
// SOURCES.md says its numbers were read from, read the bundled items back out
// of it where the source is machine-readable, and report what moved. It also
// checks every snack against FoodData Central and re-runs the validator.
//
//   node data/check-road-food.mjs            full run, writes data/road-food-CHECK.md
//   node data/check-road-food.mjs --offline  re-read cached documents only, no network
//
// It NEVER edits road-food.json. "A wrong number in someone's day is worse than
// an old one they can see is old": a human re-reads the source and edits the
// file, with a new checkedOn.
//
// Exit 0 when nothing needs attention, 1 when a source changed or couldn't be
// reached, 2 when only the validator failed. "Can't compare automatically"
// does not fail the run; it is in the report for the quarterly read.
//
// Politeness: one request per document, sequential, a pause between requests,
// a User-Agent naming this tool, no retries, and a failure (403, timeout,
// anything) is reported rather than worked around. Conditional requests
// (If-None-Match / If-Modified-Since) reuse the cached copy when the server
// says nothing changed. Raw documents are kept in data/.road-food-cache/,
// which is gitignored: they are the chains' own files.
//
// Env: FDC_API_KEY (default DEMO_KEY, which allows about 10 requests an hour;
// a run makes 4).

import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { createHash } from "node:crypto";
import { execFileSync, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import {
  FIELDS, compareItem, modificationSaving, findPdfRow, parseChickFilA, findChickFilARow,
  parseStarbucks, wendysRequest, parseWendysNutrition, deriveSnack, newerFdcRecords, fdcDate,
  parseNutritionixGrid, findNutritionixRow, embedsWidget,
  isStale, modifiedAfter, chainVerdict, exitCode, renderReport, renderSummary, statesPublished,
} from "./check-road-food-lib.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const CACHE = join(HERE, ".road-food-cache");
const USER_AGENT = "dugcanlift-road-food-check/1.0 (+https://github.com/dougray/dugcanlift-kit; quarterly nutrition refresh check)";
const TIMEOUT_MS = 45_000;
// Sheetz's own nutrition page is a 9 MB single-page app that takes over a
// minute to send; the embed check reads one string out of it and no more.
const SLOW_PAGE_TIMEOUT_MS = 180_000;
const PAUSE_MS = 1_000;
const OFFLINE = process.argv.includes("--offline");

const bundle = JSON.parse(readFileSync(join(HERE, "road-food.json"), "utf8"));
const locators = JSON.parse(readFileSync(join(HERE, "road-food-locators.json"), "utf8"));
mkdirSync(CACHE, { recursive: true });

// ------------------------------------------------------------------ fetching

const cacheKey = (url, body) => createHash("sha256").update(url + (body ?? "")).digest("hex").slice(0, 24);
const metaPath = (k) => join(CACHE, `${k}.meta.json`);
const bodyPath = (k) => join(CACHE, `${k}.body`);
let lastRequest = 0;

// Fetches one document. Returns { body: Buffer, status, fromCache, meta,
// previous } or { error }. `previous` is the last run's metadata, for the
// "same as last run" signal.
async function get(url, { method = "GET", body, headers = {}, timeoutMs = TIMEOUT_MS } = {}) {
  const k = cacheKey(url, body);
  const previous = existsSync(metaPath(k)) ? JSON.parse(readFileSync(metaPath(k), "utf8")) : undefined;
  const cached = previous && existsSync(bodyPath(k)) ? readFileSync(bodyPath(k)) : undefined;
  if (OFFLINE) {
    return cached ? { body: cached, status: "cached", fromCache: true, meta: previous, previous }
      : { error: "offline and nothing cached" };
  }
  const wait = lastRequest + PAUSE_MS - Date.now();
  if (wait > 0) await new Promise((r) => setTimeout(r, wait));
  lastRequest = Date.now();
  const h = { "User-Agent": USER_AGENT, "Accept": "*/*", ...headers };
  if (cached && method === "GET") {
    if (previous.etag) h["If-None-Match"] = previous.etag;
    if (previous.lastModified) h["If-Modified-Since"] = previous.lastModified;
  }
  let res;
  const whyFailed = (e) => (e.name === "TimeoutError" || e.name === "AbortError"
    ? `no answer in ${timeoutMs / 1000} s`
    : (e.cause?.code ?? e.message));
  try {
    res = await fetch(url, { method, body, headers: h, redirect: "follow", signal: AbortSignal.timeout(timeoutMs) });
  } catch (e) {
    return { error: `${new URL(url).host}: ${whyFailed(e)}` };
  }
  if (res.status === 304 && cached) {
    const meta = { ...previous, fetchedAt: new Date().toISOString(), status: 304 };
    writeFileSync(metaPath(k), JSON.stringify(meta, null, 2));
    return { body: cached, status: 304, fromCache: true, meta, previous };
  }
  if (!res.ok) {
    const blocked = [401, 403, 429].includes(res.status) ? " (refused; not retried or worked around)" : "";
    return { error: `${new URL(url).host}: HTTP ${res.status}${blocked}` };
  }
  // The timeout covers the body too, and a big slow page can abort here long
  // after the headers arrived. A source that could not be read is reported
  // like any other, never thrown out of the run.
  let buf;
  try {
    buf = Buffer.from(await res.arrayBuffer());
  } catch (e) {
    return { error: `${new URL(url).host}: ${whyFailed(e)} while reading the body` };
  }
  const meta = {
    url: url.replace(/api_key=[^&]+/, "api_key=…"), fetchedAt: new Date().toISOString(), status: res.status,
    etag: res.headers.get("etag") ?? undefined,
    lastModified: res.headers.get("last-modified") ?? undefined,
    contentType: res.headers.get("content-type") ?? undefined,
    sha256: createHash("sha256").update(buf).digest("hex"),
    bytes: buf.length,
  };
  writeFileSync(bodyPath(k), buf);
  writeFileSync(metaPath(k), JSON.stringify(meta, null, 2));
  return { body: buf, status: res.status, fromCache: false, meta, previous };
}

// Change signals a human can read, cheapest first. None of these is a
// verdict on the numbers; they say whether the document itself moved.
function signals(doc, checkedOn, { hashMeaningful = true } = {}) {
  const s = [];
  const m = doc.meta ?? {};
  if (doc.status === 304) s.push(`Server says not modified since the last run (${doc.previous.fetchedAt.slice(0, 10)}).`);
  if (m.lastModified) {
    const after = modifiedAfter(m.lastModified, checkedOn);
    s.push(`Last-Modified ${new Date(m.lastModified).toISOString().slice(0, 10)}: ${after ? "**after** checkedOn" : "before checkedOn"}.`);
  }
  if (hashMeaningful && doc.previous?.sha256 && doc.status !== 304) {
    s.push(doc.previous.sha256 === m.sha256
      ? `Content identical to the last run (${doc.previous.fetchedAt.slice(0, 10)}).`
      : `Content differs from the last run (${doc.previous.fetchedAt.slice(0, 10)}).`);
  }
  return s;
}

// Does the document still state the date the bundle records for it? Only ever
// asked of text that was actually read this run; a chain whose document states
// no date has no `publishedOn` and nothing to check.
function notePublished(r, chain, text) {
  if (!chain.publishedOn) return;
  const still = statesPublished(text, chain.publishedOn);
  if (still === undefined) return;
  r.publishedStated = still;
  r.signals.push(still
    ? `The document still states its own date as ${chain.publishedOn}.`
    : `**The document no longer states ${chain.publishedOn}**: it has been republished, so re-read it and its \`publishedOn\` by hand.`);
}

// ------------------------------------------------------------ PDF text

// PDFKit (macOS) is what the bundle was curated with, and the row locators
// were written against its text. pdftotext is the fallback elsewhere; its line
// breaks can differ, so a row it cannot find is worth a second look before
// believing it.
let pdfExtractor;
function pdfToText(buf) {
  const k = createHash("sha256").update(buf).digest("hex").slice(0, 24);
  const pdf = join(CACHE, `${k}.pdf`);
  writeFileSync(pdf, buf);
  if (!pdfExtractor) {
    if (process.platform === "darwin" && spawnSync("swift", ["--version"]).status === 0) pdfExtractor = "PDFKit";
    else if (spawnSync("pdftotext", ["-v"]).status === 0) pdfExtractor = "pdftotext";
    else pdfExtractor = "none";
  }
  if (pdfExtractor === "PDFKit") {
    const script = join(CACHE, "pdftext.swift");
    writeFileSync(script, `import Foundation
import PDFKit
guard let doc = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1])) else { exit(2) }
for i in 0..<doc.pageCount { print(doc.page(at: i)?.string ?? ""); print("\\u{0C}") }
`);
    return execFileSync("swift", [script, pdf], { encoding: "utf8", maxBuffer: 64 << 20 });
  }
  if (pdfExtractor === "pdftotext") return execFileSync("pdftotext", ["-enc", "UTF-8", pdf, "-"], { encoding: "utf8", maxBuffer: 64 << 20 });
  return undefined;
}

// ------------------------------------------------------------ per method

function itemsWith(chain, loc, read) {
  return chain.items.map((item) => {
    const l = loc.items?.[item.id];
    const base = { id: item.id, name: item.name };
    if (!l) return { ...base, error: "no locator in road-food-locators.json" };
    const r = read(l, item);
    if (r.error) return { ...base, missing: r.error, compared: false };
    const diffs = compareItem(item, r.values, l.fields ?? loc.fields ?? FIELDS);
    return { ...base, compared: true, diffs, notes: r.notes };
  });
}

async function checkPdf(chain, loc, r) {
  const doc = await get(chain.source);
  if (doc.error) { r.unreachable.push(doc.error); return; }
  r.signals.push(...signals(doc, chain.checkedOn));
  const text = pdfToText(doc.body);
  if (text === undefined) {
    r.manual = true;
    r.manualWhy = "no PDF text extractor here (needs macOS with Swift, or pdftotext)";
    r.docChanged = modifiedAfter(doc.meta?.lastModified, chain.checkedOn);
    r.items = chain.items.map((i) => ({ id: i.id, name: i.name, error: "PDF not read" }));
    return;
  }
  notePublished(r, chain, text);
  r.items = itemsWith(chain, loc, (l) => findPdfRow(text, l, loc.columns));
}

async function checkManual(chain, loc, r) {
  const doc = await get(chain.source);
  if (doc.error) { r.unreachable.push(doc.error); return; }
  r.signals.push(...signals(doc, chain.checkedOn));
  r.manual = true;
  r.manualWhy = loc.why;
  // Only the server's own date can clear a manual source; anything else,
  // including "same bytes as the last run", is not evidence the bundle
  // matches, because nothing compared the bundle with that run either.
  r.docChanged = modifiedAfter(doc.meta?.lastModified, chain.checkedOn);
  r.items = chain.items.map((i) => ({ id: i.id, name: i.name }));
}

async function checkChickFilA(chain, loc, r) {
  const doc = await get(chain.source);
  if (doc.error) { r.unreachable.push(doc.error); return; }
  const parsed = parseChickFilA(doc.body.toString("utf8"));
  if (parsed.error) {
    r.manual = true;
    r.manualWhy = `${parsed.error}; re-read by hand`;
    r.items = chain.items.map((i) => ({ id: i.id, name: i.name, error: "page not parsed" }));
    return;
  }
  r.signals.push("The page is rebuilt on every request, so its bytes say nothing; only the numbers are compared.");
  notePublished(r, chain, doc.body.toString("utf8"));
  r.items = itemsWith(chain, loc, (l) => findChickFilARow(parsed.rows, l));
}

// Taco Bell and Sheetz publish their food nutrition only through the
// Nutritionix calculator their own nutrition page embeds. The chain's page is
// the `source`, so the embed itself is checked first: without it the widget is
// no longer the chain's own published figures and the entry has to be re-read.
async function checkNutritionixGrid(chain, loc, r) {
  const page = await get(chain.source, { timeoutMs: SLOW_PAGE_TIMEOUT_MS });
  if (page.error) r.signals.push(`Could not re-read ${new URL(chain.source).host} to confirm the embed: ${page.error}`);
  else if (embedsWidget(page.body.toString("utf8"), loc.embed)) {
    r.signals.push(`${new URL(chain.source).host} still embeds ${loc.embed}.`);
  } else {
    r.signals.push(`**${new URL(chain.source).host} no longer embeds ${loc.embed}**: the widget may no longer be what the chain publishes, so re-read the source by hand.`);
  }
  const doc = await get(loc.gridUrl);
  if (doc.error) { r.unreachable.push(doc.error); return; }
  const html = doc.body.toString("utf8");
  r.signals.push(...signals(doc, chain.checkedOn, { hashMeaningful: false }));
  r.signals.push("The widget stamps fresh element ids into every response, so its bytes say nothing; only the numbers and the date it prints are compared.");
  const parsed = parseNutritionixGrid(html);
  if (parsed.error) {
    r.manual = true;
    r.manualWhy = `${parsed.error}; re-read by hand`;
    r.items = chain.items.map((i) => ({ id: i.id, name: i.name, error: "grid not parsed" }));
    return;
  }
  notePublished(r, chain, html);
  r.items = itemsWith(chain, loc, (l) => findNutritionixRow(parsed.rows, l, loc.columns));
}

async function checkStarbucks(chain, loc, r) {
  const items = [];
  for (const item of chain.items) {
    const l = loc.items?.[item.id];
    if (!l) { items.push({ id: item.id, name: item.name, error: "no locator in road-food-locators.json" }); continue; }
    const url = `https://www.starbucks.com/apiproxy/v1/ordering/${l.product}/${l.form}`;
    const doc = await get(url, { headers: { Accept: "application/json" } });
    if (doc.error) { r.unreachable.push(`${item.name}: ${doc.error}`); items.push({ id: item.id, name: item.name, error: "unreachable" }); continue; }
    let json;
    try { json = JSON.parse(doc.body.toString("utf8")); } catch { items.push({ id: item.id, name: item.name, missing: "the response is not JSON" }); continue; }
    const p = parseStarbucks(json, l.size);
    if (p.error) { items.push({ id: item.id, name: item.name, missing: p.error }); continue; }
    items.push({ id: item.id, name: item.name, compared: true, diffs: compareItem(item, p.values, loc.fields ?? FIELDS) });
  }
  r.signals.push("One ordering-API response per item, each read field by field.");
  r.items = items;
}

async function checkWendys(chain, loc, r) {
  // The order site sends lang, cntry, sourceCode and its own version on every
  // call; the menu service refuses a request without them (HTTP 422).
  const menuDoc = await get(`${loc.menuUrl}&${loc.commonParams}`, { headers: { Accept: "application/json" } });
  if (menuDoc.error) { r.unreachable.push(`menu feed: ${menuDoc.error}`); return; }
  let menu;
  try { menu = JSON.parse(menuDoc.body.toString("utf8")); } catch { r.unreachable.push("menu feed: not JSON"); return; }
  const ask = async (data) => {
    const url = `${chain.source}?${loc.commonParams}&data=${encodeURIComponent(JSON.stringify(data))}`;
    const doc = await get(url, { headers: { Accept: "application/json" } });
    if (doc.error) return { unreachable: doc.error };
    try { return parseWendysNutrition(JSON.parse(doc.body.toString("utf8"))); } catch { return { error: "the nutrition response is not JSON" }; }
  };
  const items = [];
  for (const item of chain.items) {
    const l = loc.items?.[item.id];
    const base = { id: item.id, name: item.name };
    if (!l) { items.push({ ...base, error: "no locator in road-food-locators.json" }); continue; }
    const req = wendysRequest(menu, l.salesItemId);
    if (req.error) { items.push({ ...base, missing: req.error }); continue; }
    const got = await ask(req.data);
    if (got.unreachable) { r.unreachable.push(`${item.name}: ${got.unreachable}`); items.push({ ...base, error: "unreachable" }); continue; }
    if (got.error) { items.push({ ...base, missing: got.error }); continue; }
    const diffs = compareItem(item, got.values, loc.fields ?? FIELDS);
    const notes = [];
    // "Hold the X to save N kcal": ask the calculator for the build without X.
    if (item.modification && l.modificationRemoves) {
      const saving = modificationSaving(item.modification);
      const without = wendysRequest(menu, l.salesItemId, { without: l.modificationRemoves });
      if (without.error) diffs.push({ field: "modification", label: "modification", old: item.modification, now: `can't check: ${without.error}` });
      else {
        const w = await ask(without.data);
        if (w.unreachable) r.unreachable.push(`${item.name} (modification): ${w.unreachable}`);
        else if (w.error) notes.push(`modification not checked: ${w.error}`);
        else {
          const now = got.values.kcal - w.values.kcal;
          if (saving !== now) diffs.push({ field: "modification", label: `kcal saved without ${l.modificationRemoves}`, old: saving, now });
          else notes.push(`"${item.modification}" still holds (${got.values.kcal} → ${w.values.kcal} kcal).`);
        }
      }
    }
    items.push({ ...base, compared: true, diffs, notes });
  }
  const gen = menu?.menuLists?.cacheExpirationDate;
  r.signals.push(`Menu feed ${menuDoc.status === 304 ? "not modified since the last run" : "fetched"}${gen ? `; the feed's cache expires ${new Date(gen).toISOString()}` : ""}.`);
  r.items = items;
}

const METHODS = { pdf: checkPdf, manual: checkManual, chickfila: checkChickFilA, starbucks: checkStarbucks,
  wendys: checkWendys, nutritionix: checkNutritionixGrid };

async function checkChain(chain) {
  const r = { id: chain.id, name: chain.name, checkedOn: chain.checkedOn, publishedOn: chain.publishedOn,
    source: chain.source, items: [], signals: [], unreachable: [] };
  const loc = locators.chains[chain.id];
  if (!loc || !METHODS[loc.method]) {
    r.manual = true;
    r.manualWhy = "no locator for this chain in road-food-locators.json";
    r.items = chain.items.map((i) => ({ id: i.id, name: i.name, error: "no locator" }));
  } else {
    await METHODS[loc.method](chain, loc, r);
    if (loc.note) r.signals.push(loc.note);
  }
  // A source that failed before any item was read still lists its items, so
  // the report shows what went unchecked.
  if (!r.items.length) r.items = chain.items.map((i) => ({ id: i.id, name: i.name, error: "source not reached" }));
  r.verdict = chainVerdict(r);
  return r;
}

// FoodData Central, by fdcId, 20 per request (the API's batch limit). The
// abridged format carries nutrient numbers; the full one carries serving size
// and the update log.
async function checkSnacks(snacks) {
  const key = process.env.FDC_API_KEY || "DEMO_KEY";
  const r = { id: "snacks", name: "Snacks (FoodData Central)", checkedOn: snacks.map((s) => s.checkedOn).sort()[0],
    items: [], signals: [], unreachable: [] };
  const byId = new Map();
  for (let i = 0; i < snacks.length; i += 20) {
    const ids = snacks.slice(i, i + 20).map((s) => s.fdcId);
    for (const format of ["abridged", "full"]) {
      // The key is a query parameter, so it never reaches the cache key or the report.
      const url = "https://api.nal.usda.gov/fdc/v1/foods";
      const doc = await get(`${url}?api_key=${key}`, {
        method: "POST", body: JSON.stringify({ fdcIds: ids, format }), headers: { "Content-Type": "application/json" },
      });
      if (doc.error) { r.unreachable.push(doc.error.replace(key, "…")); continue; }
      let list;
      try { list = JSON.parse(doc.body.toString("utf8")); } catch { r.unreachable.push("FDC: response is not JSON"); continue; }
      for (const f of list) byId.set(`${format}:${f.fdcId}`, f);
    }
  }
  if (r.unreachable.length) r.items = snacks.map((s) => ({ id: s.id, name: s.name, error: "FDC not reached" }));
  else {
    r.signals.push("Each product is re-derived from its FDC record (per-100 g figure x serving, then FDA label rounding), and its update log is checked for a newer record of the same product.");
    r.items = snacks.map((s) => {
      const base = { id: s.id, name: s.name };
      const ab = byId.get(`abridged:${s.fdcId}`), full = byId.get(`full:${s.fdcId}`);
      if (!ab || !full) return { ...base, missing: `FDC no longer returns record ${s.fdcId}` };
      const d = deriveSnack(ab, full);
      if (d.error) return { ...base, missing: d.error };
      const diffs = compareItem(s, d.values);
      const newer = newerFdcRecords(full);
      for (const n of newer) diffs.push({ field: "fdcId", label: "newer FDC record for this product", old: `${s.fdcId} (${fdcDate(full.publicationDate)})`, now: `${n.fdcId} (${n.published})` });
      if (full.discontinuedDate) diffs.push({ field: "discontinued", label: "discontinued", old: "no", now: full.discontinuedDate });
      return { ...base, compared: true, diffs };
    });
  }
  r.verdict = chainVerdict(r);
  return r;
}

// ------------------------------------------------------------------ run

const today = new Date().toISOString().slice(0, 10);
const results = [];
for (const chain of bundle.chains) {
  process.stderr.write(`checking ${chain.name}…\n`);
  results.push(await checkChain(chain));
}
process.stderr.write("checking snacks…\n");
results.push(await checkSnacks(bundle.snacks));

const stale = [
  ...bundle.chains.filter((c) => isStale(c.checkedOn, today)).map((c) => ({ name: c.name, checkedOn: c.checkedOn })),
  ...bundle.snacks.filter((s) => isStale(s.checkedOn, today)).map((s) => ({ name: s.name, checkedOn: s.checkedOn })),
];

const v = spawnSync(process.execPath, [join(HERE, "validate-road-food.mjs")], { encoding: "utf8" });
const validator = { code: v.status ?? 1, output: (v.stdout ?? "") + (v.stderr ?? "") };

const report = renderReport({
  results, stale, validator,
  ranAt: new Date().toISOString().replace(/\.\d+Z$/, "Z") + (OFFLINE ? " (offline, cached documents)" : ""),
  bundle: { chains: bundle.chains.length, items: bundle.chains.reduce((a, c) => a + c.items.length, 0), snacks: bundle.snacks.length },
  pdfExtractor,
});
writeFileSync(join(HERE, "road-food-CHECK.md"), report);
console.log(renderSummary(results, stale, validator));
console.log("\nReport: data/road-food-CHECK.md");
process.exit(exitCode(results, validator));
