// The shared web map module, map.js: a classic script that sets window.LiftMap.
// Loaded here the way LIFT web's tests load theirs, with a window shim, so
// every browser API it touches (localStorage, caches, fetch, maplibregl, the
// DOM) is a fake this file controls. Run: node --test map/web/map.test.mjs
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "map.js"), "utf8");
const ORIGIN = "https://www.dugcanlift.com";
const TILEJSON = "https://tiles.openfreemap.org/planet";
const GOOD = "https://tiles.openfreemap.org/planet/v1/{z}/{x}/{y}.pbf";

// MARK: - Fakes

function memoryStorage() {
  const m = new Map();
  const s = {
    reads: 0,
    getItem(k) { s.reads += 1; return m.has(k) ? m.get(k) : null; },
    setItem(k, v) { m.set(k, String(v)); },
    removeItem(k) { m.delete(k); },
  };
  return s;
}

/** Cache Storage as the spec has it: a key that is not http(s) is refused. */
function fakeCaches() {
  const stores = new Map();
  const open = async (name) => {
    if (!stores.has(name)) stores.set(name, new Map());
    const m = stores.get(name);
    const url = (r) => (typeof r === "string" ? r : r.url);
    return {
      async put(r, res) {
        const u = url(r);
        if (!/^https?:/.test(u)) throw new TypeError(`Request scheme '${u.split(":")[0]}' is unsupported`);
        m.set(u, await res.arrayBuffer());
      },
      async match(r) { const b = m.get(url(r)); return b ? new Response(b.slice(0)) : undefined; },
      async delete(r) { return m.delete(url(r)); },
      async keys() { return [...m.keys()].map((u) => ({ url: u })); },
    };
  };
  return { open, stores, urls: (name) => [...(stores.get(name)?.keys() ?? [])] };
}

/** Just enough DOM for mount: elements with children, style and attributes. */
function fakeDocument() {
  const make = (tag) => {
    const el = {
      tagName: tag.toUpperCase(), children: [], style: {}, attrs: {}, className: "", textContent: "",
      clientWidth: 320, clientHeight: 160,
      appendChild(c) { el.children.push(c); c.parentNode = el; return c; },
      replaceChildren(...cs) { el.children = [...cs]; },
      setAttribute(k, v) { el.attrs[k] = String(v); },
    };
    return el;
  };
  return { createElement: make, head: make("head"), querySelector: () => null };
}

/** A MapLibre stand-in that records what the module asks of it. */
function fakeMapLibre() {
  const gl = { maps: [], protocols: {}, workerUrl: null };
  gl.addProtocol = (name, fn) => { gl.protocols[name] = fn; };
  gl.setWorkerUrl = (u) => { gl.workerUrl = u; };
  gl.Map = class {
    constructor(options) {
      this.options = options;
      this.handlers = {};
      this.sources = {};
      this.layers = [];
      this.fits = [];
      this.removed = false;
      gl.maps.push(this);
    }
    on(ev, fn) { (this.handlers[ev] ??= []).push(fn); return this; }
    fire(ev) { for (const fn of this.handlers[ev] ?? []) fn({}); }
    getContainer() { return this.options.container; }
    getSource(id) { return this.sources[id]; }
    addSource(id, s) { this.sources[id] = { ...s, setData(d) { this.data = d; } }; }
    addLayer(l) { this.layers.push(l); }
    fitBounds(b, o) { this.fits.push([b, o]); }
    remove() { this.removed = true; }
  };
  return gl;
}

function load({ fetch, caches = fakeCaches(), storage = memoryStorage(), maplibregl } = {}) {
  const win = new EventTarget();
  Object.assign(win, {
    localStorage: storage, caches, fetch, maplibregl,
    location: { origin: ORIGIN, href: `${ORIGIN}/lift/` },
    document: fakeDocument(), Response, CustomEvent, URL, crypto: globalThis.crypto,
  });
  new Function("window", src).call(win, win);
  const M = win.LiftMap;
  M.configure({ cachePrefix: "lift-map-", storageKey: "lift.mapAreas", base: "/lift/map/" });
  return { M, win, caches, storage };
}

const tileJSON = (template) => new Response(JSON.stringify({ tiles: [template] }), { status: 200 });

/** A fetch that answers the TileJSON and every tile, and records each call. */
function fakeFetch(answer = () => new Response(new Uint8Array([1, 2, 3]), { status: 200 })) {
  const calls = [];
  const f = async (url, init) => {
    calls.push({ url, init });
    if (url === TILEJSON) return tileJSON(GOOD);
    return answer(url, init);
  };
  f.calls = calls;
  f.tileCalls = () => calls.filter((c) => c.url !== TILEJSON).map((c) => c.url);
  return f;
}

const tilePath = (t) => `https://tiles.openfreemap.org/planet/v1/${t.z}/${t.x}/${t.y}.pbf`;
const tick = () => new Promise((r) => setTimeout(r, 0));

// MARK: - Tile maths, the Swift numbers

test("Denver numbers", () => {
  const { M } = load();
  assert.equal(M.x(-104.9903, 14), 3413);
  assert.equal(M.y(39.7392, 14), 6218);
  assert.equal(M.x(-104.9903, 10), 213);
  assert.equal(M.y(39.7392, 10), 388);
  const world = { south: -85.0511, west: -180, north: 85.0511, east: 180 };
  for (let z = 0; z <= 4; z++) assert.equal(M.count(world, z), 1 << (2 * z));
  assert.equal(M.tiles(world, 3).length, 64);

  const b = M.bounds(39.7392, -104.9903, 50);
  assert.ok(Math.abs(b.north - 39.7392 - 50 / 111.32) < 1e-9);
  assert.ok(b.east + 104.9903 > b.north - 39.7392);
  assert.equal(M.count(b, 11), 64);
  assert.equal(M.count(b, 14), 2916);
  assert.equal(M.tiles(b, 14).length, 2916);

  const edge = M.bounds(84.9, 179.9, 400);
  assert.ok(edge.north <= 85.0511);
  assert.ok(edge.east <= 180);
});

test("plans: tiles deduplicated, sized by zoom", () => {
  const { M } = load();
  const key = (t) => `${t.z}/${t.x}/${t.y}`;
  const small = M.plan(39.7392, -104.9903, 10);
  const big = M.plan(39.7392, -104.9903, 50);
  assert.ok(M.estimateBytes(small) < M.estimateBytes(big));
  assert.equal(new Set(small.tiles.map(key)).size, small.tiles.length);
  assert.equal(new Set(big.tiles.map(key)).size, big.tiles.length);
  assert.equal(M.estimateBytes(big), big.tiles.reduce((t, x) => t + M.typicalBytes(x.z), 0));
  assert.equal(big.estimatedBytes, M.estimateBytes(big));
  assert.deepEqual(M.detailChoices, [10, 25, 50]);
  assert.equal(M.wideKm, 100);
  assert.equal(M.startingKm, 10);
});

test("a route plan grows the route by 2 km", () => {
  const { M } = load();
  const route = { south: 39.70, west: -105.00, north: 39.71, east: -104.99 };
  const plan = M.planForRoute(route);
  assert.ok(Math.abs(plan.detail.north - route.north - 2 / 111.32) < 1e-9);
  assert.ok(Math.abs(route.south - plan.detail.south - 2 / 111.32) < 1e-9);
  assert.ok(route.west - plan.detail.west > 2 / 111.32);
  assert.equal(plan.detailKm, 0);
  assert.equal(new Set(plan.tiles.map((t) => `${t.z}/${t.x}/${t.y}`)).size, plan.tiles.length);
  assert.ok(plan.tiles.some((t) => t.z === 14));
});

test("around and intersects", () => {
  const { M } = load();
  assert.equal(M.around([]), null);
  assert.deepEqual(M.around([[1, 2]]), { south: 1, west: 2, north: 1, east: 2 });
  const b = M.around([[1, 2, 150, 0, 5], { latitude: 3, longitude: -4 }]);
  assert.deepEqual(b, { south: 1, west: -4, north: 3, east: 2 });
  assert.equal(M.intersects(b, { south: 3, west: 2, north: 5, east: 6 }), true);
  assert.equal(M.intersects(b, { south: 4, west: 0, north: 5, east: 1 }), false);
});

test("a route is a map only when downloaded streets cover it", () => {
  const { M } = load();
  assert.equal(M.decide([[1, 2]], () => true), "line");
  assert.equal(M.decide([[1, 2], [1.01, 2.01]], () => true), "map");
  assert.equal(M.decide([[1, 2], [1.01, 2.01]], () => false), "line");
});

test("an area is replanned the way it was downloaded", () => {
  const { M } = load();
  const radius = M.plan(39.7392, -104.9903, 25);
  const again = M.replan({ detail: radius.detail, detailKm: 25 });
  assert.equal(again.detailKm, 25);
  assert.ok(Math.abs(again.latitude - 39.7392) < 1e-9);
  const route = M.planForRoute({ south: 39.70, west: -105.00, north: 39.71, east: -104.99 });
  const back = M.replan({ detail: route.detail, detailKm: 0 });
  for (const k of ["south", "west", "north", "east"]) assert.ok(Math.abs(back.detail[k] - route.detail[k]) < 1e-9, k);
});

// MARK: - Only local files reach the map

test("allowedMapUrl lets through local files only", () => {
  const { M } = load();
  assert.equal(M.allowedMapUrl("https://tiles.openfreemap.org/planet/v1/1/0/0.pbf"), false);
  assert.equal(M.allowedMapUrl("https://example.com/lift/map/style-light.json"), false);
  assert.equal(M.allowedMapUrl("//example.com/lift/map/style-light.json"), false);
  assert.equal(M.allowedMapUrl("/lift/map/../../evil.js"), false);
  assert.equal(M.allowedMapUrl("/coach/map/style-light.json"), false);
  assert.equal(M.allowedMapUrl("http://www.dugcanlift.com/lift/map/style-light.json"), false);
  assert.equal(M.allowedMapUrl("data:application/json,{}"), false);
  assert.equal(M.allowedMapUrl(""), false);
  assert.equal(M.allowedMapUrl("liftmap://tiles/1/0/0"), true);
  assert.equal(M.allowedMapUrl("/lift/map/fonts/x/0-255.pbf"), true);
  assert.equal(M.allowedMapUrl(`${ORIGIN}/lift/map/fonts/Noto%20Sans%20Regular/0-255.pbf`), true);
  assert.equal(M.allowedMapUrl(`${ORIGIN}/lift/map/style-dark.json`), true);
});

test("the web style names no server", () => {
  const { M } = load();
  for (const f of ["style-light.json", "style-dark.json"]) {
    const template = JSON.parse(readFileSync(join(here, "..", f), "utf8"));
    const s = M.webStyle(template);
    const text = JSON.stringify(s);
    assert.doesNotMatch(text, /https?:\/\/(?!www\.dugcanlift\.com\/lift\/map\/)/, f);
    assert.doesNotMatch(text, /\{\{/, f);
    const source = s.sources.openmaptiles;
    assert.equal("url" in source, false);
    assert.deepEqual(source.tiles, ["liftmap://tiles/{z}/{x}/{y}"]);
    assert.equal(source.minzoom, 0);
    assert.equal(source.maxzoom, 14);
    assert.equal(s.glyphs, `${ORIGIN}/lift/map/fonts/{fontstack}/{range}.pbf`);
    assert.equal(template.sources.openmaptiles.url, "{{TILES}}", "the template is not changed");
    for (const u of [s.glyphs.replace("{fontstack}", "Noto Sans Regular").replace("{range}", "0-255"), source.tiles[0]]) {
      assert.equal(M.allowedMapUrl(u), true, u);
    }
  }
});

// MARK: - The store: an index in localStorage, tiles in Cache Storage

test("a tile is keyed on this origin, in the app's own cache", async () => {
  const { M, caches } = load({ fetch: fakeFetch() });
  const plan = M.plan(39.7392, -104.9903, 10);
  const id = M.beginArea(plan, "A");
  await M.putTile(id, { z: 5, x: 6, y: 12 }, new Uint8Array([9]).buffer);
  assert.deepEqual(caches.urls("lift-map-tiles"), [`${ORIGIN}/__liftmap/tiles/5/6/12`]);
});

test("a tile for an area with no row is refused", async () => {
  const { M, caches } = load();
  await assert.rejects(M.putTile("no-such-area", { z: 3, x: 1, y: 2 }, new ArrayBuffer(1)), { code: "unknownArea" });
  assert.deepEqual(caches.urls("lift-map-tiles"), []);
});

test("deleting one area keeps tiles another still owns", async () => {
  const { M, caches } = load();
  const plan = M.plan(39.7392, -104.9903, 10);
  const a = M.beginArea(plan, "A");
  const b = M.beginArea(plan, "B");
  const tile = { z: 5, x: 6, y: 12 };
  await M.putTile(a, tile, new Uint8Array([9]).buffer);
  await M.putTile(b, tile, new Uint8Array([9]).buffer);
  M.finishArea(a);
  M.finishArea(b);
  await M.deleteArea(a);
  assert.equal(caches.urls("lift-map-tiles").length, 1);
  assert.deepEqual(M.areas().map((x) => x.name), ["B"]);
  await M.deleteArea(b);
  assert.equal(caches.urls("lift-map-tiles").length, 0);
  assert.deepEqual(M.areas(), []);
});

test("an unfinished area is listed separately, and deleting it leaves nothing", async () => {
  const { M, caches, storage } = load();
  const id = M.beginArea(M.plan(39.7392, -104.9903, 10), "Half");
  await M.putTile(id, { z: 3, x: 1, y: 2 }, new Uint8Array([1]).buffer);
  assert.deepEqual(M.areas(), []);
  assert.deepEqual(M.unfinishedAreas().map((a) => a.id), [id]);
  assert.equal(M.covers(M.plan(39.7392, -104.9903, 10).detail), false);
  await M.deleteArea(id);
  assert.equal(caches.urls("lift-map-tiles").length, 0);
  assert.deepEqual(JSON.parse(storage.getItem("lift.mapAreas")), []);
});

test("covers is any finished area touching the bounds", () => {
  const { M } = load();
  const p = M.plan(39.7392, -104.9903, 10);
  M.finishArea(M.beginArea(p, "Denver"));
  const d = p.detail;
  assert.equal(M.covers({ south: d.south + 0.01, west: d.west + 0.01, north: d.south + 0.02, east: d.west + 0.02 }), true);
  assert.equal(M.covers({ south: d.north - 0.01, west: d.east - 0.01, north: d.north + 1, east: d.east + 1 }), true);
  assert.equal(M.covers({ south: 10, west: 10, north: 11, east: 11 }), false);
  const london = M.plan(51.5, -0.12, 10);
  M.beginArea(london, "London");
  assert.equal(M.covers(london.detail), false);
});

test("finishing and deleting an area each say so once", async () => {
  const { M, win } = load();
  let heard = 0;
  win.addEventListener("liftmap:changed", () => { heard += 1; });
  const id = M.beginArea(M.plan(39.7392, -104.9903, 10), "A");
  assert.equal(heard, 0);
  M.finishArea(id);
  assert.equal(heard, 1);
  await M.deleteArea(id);
  assert.equal(heard, 2);
});

test("an index that is not ours reads as no areas", () => {
  const storage = memoryStorage();
  storage.setItem("lift.mapAreas", "{not json");
  const { M } = load({ storage });
  assert.deepEqual(M.areas(), []);
  storage.setItem("lift.mapAreas", JSON.stringify([{ id: 1 }, null, "x"]));
  assert.deepEqual(M.areas(), []);
});

// MARK: - The download, the one request

test("the template must be OpenFreeMap's", async () => {
  const calls = [];
  const fetch = async (url) => { calls.push(url); return tileJSON("https://evil.example/{z}/{x}/{y}.pbf"); };
  const { M } = load({ fetch });
  await assert.rejects(M.download(M.plan(39.7392, -104.9903, 10), "X", () => {}), { code: "refusedHost" });
  assert.deepEqual(calls, [TILEJSON], "no tile may be fetched");
});

test("an unfinished download is not an area", async () => {
  const plan0 = load().M.plan(39.7392, -104.9903, 10);
  const bad = tilePath(plan0.tiles[4]);
  const failing = fakeFetch((url) => new Response(url === bad ? null : new Uint8Array([1, 2, 3]), { status: url === bad ? 500 : 200 }));
  const { M, win, caches } = load({ fetch: failing });
  const plan = M.plan(39.7392, -104.9903, 10);
  const err = await M.download(plan, "X", () => {}).then(() => null, (e) => e);
  assert.equal(err.code, "http");
  assert.equal(err.status, 500);
  assert.deepEqual(M.areas(), []);

  // The failed run left exactly one unfinished area, which resume picks up.
  const unfinished = M.unfinishedAreas();
  assert.equal(unfinished.length, 1);
  assert.equal(err.areaId, unfinished[0].id);
  const stored = plan.tiles.filter((t) => M.hasTile(err.areaId, t));
  assert.ok(stored.length > 0 && stored.length < plan.tiles.length);

  const good = fakeFetch();
  win.fetch = good;
  const seen = [];
  const area = await M.resume(err.areaId, plan, (done, total) => seen.push([done, total]));
  assert.deepEqual(M.areas().map((a) => a.id), [area.id]);
  assert.deepEqual(M.unfinishedAreas(), []);
  const tilePaths = good.tileCalls();
  assert.equal(tilePaths.length, plan.tiles.length - stored.length);
  for (const t of stored) assert.ok(!tilePaths.includes(tilePath(t)));
  assert.deepEqual(seen[0], [stored.length, plan.tiles.length]);
  assert.deepEqual(seen.at(-1), [plan.tiles.length, plan.tiles.length]);
  assert.equal(area.bytes, plan.tiles.length * 3);
  assert.equal(caches.urls("lift-map-tiles").length, plan.tiles.length);
});

test("a missing tile is stored empty and the area finishes", async () => {
  const fetch = fakeFetch((url) => new Response(null, { status: url.endsWith("/0/0/0.pbf") ? 404 : 204 }));
  const { M } = load({ fetch });
  const plan = M.plan(39.7392, -104.9903, 10);
  const area = await M.download(plan, "X", () => {});
  assert.equal(M.hasTile(area.id, plan.tiles[0]), true);
  assert.equal(area.bytes, 0);
});

test("every request goes to one host, with no cookies and no referrer", async () => {
  const fetch = fakeFetch();
  const { M } = load({ fetch });
  await M.download(M.plan(39.7392, -104.9903, 10), "X", () => {});
  assert.ok(fetch.calls.length > 1);
  for (const { url, init } of fetch.calls) {
    assert.ok(url.startsWith("https://tiles.openfreemap.org/"), url);
    assert.equal(init.credentials, "omit");
    assert.equal(init.referrerPolicy, "no-referrer");
    assert.equal(init.redirect, "error");
    assert.equal(init.cache, "no-store");
    assert.equal(init.method, "GET");
  }
});

test("a template off the tile host, or not https, is refused", async () => {
  for (const template of ["http://tiles.openfreemap.org/{z}/{x}/{y}.pbf",
    "https://tiles.openfreemap.org:8443/{z}/{x}/{y}.pbf",
    "https://tiles.openfreemap.org.evil.example/{z}/{x}/{y}.pbf",
    "https://tiles.openfreemap.org/planet/v1/{z}/{x}.pbf"]) {
    const fetch = async () => tileJSON(template);
    const { M } = load({ fetch });
    const e = await M.download(M.plan(39.7392, -104.9903, 10), "X", () => {}).then(() => null, (x) => x);
    assert.ok(e && (e.code === "refusedHost" || e.code === "badTemplate"), template);
  }
});

test("a cancelled download stops, then removes its area, before it settles", async () => {
  // Each tile waits until the test lets it go, so the cancel lands mid-flight.
  const waiting = [];
  const fetch = fakeFetch(() => new Promise((resolve) => waiting.push(() => resolve(new Response(new Uint8Array([4]), { status: 200 })))));
  const { M, caches } = load({ fetch });
  const plan = M.plan(39.7392, -104.9903, 10);
  const controller = new AbortController();
  let settled = false;
  const run = M.download(plan, "X", () => {}, { signal: controller.signal }).then(() => null, (e) => e)
    .finally(() => { settled = true; });
  while (waiting.length < 4) await tick();
  assert.equal(M.unfinishedAreas().length, 1);
  controller.abort();
  await tick();
  assert.equal(settled, false, "it waits for the tiles in flight");
  // The tiles in flight answer after the cancel; none may outlive the area.
  for (const go of waiting.splice(0)) go();
  const err = await run;
  assert.equal(err.code, "cancelled");
  assert.equal(fetch.tileCalls().length, 4, "nothing is asked for after the cancel");
  assert.deepEqual(M.unfinishedAreas(), []);
  assert.deepEqual(M.areas(), []);
  assert.deepEqual(caches.urls("lift-map-tiles"), []);
});

test("a cancelled retry keeps the area it was retrying", async () => {
  const fetch = fakeFetch();
  const { M } = load({ fetch });
  const plan = M.plan(39.7392, -104.9903, 10);
  const id = M.beginArea(plan, "Earlier");
  const controller = new AbortController();
  controller.abort();
  const err = await M.resume(id, plan, () => {}, { signal: controller.signal }).then(() => null, (e) => e);
  assert.equal(err.code, "cancelled");
  assert.deepEqual(M.unfinishedAreas().map((a) => a.id), [id]);
  const again = new AbortController();
  again.abort();
  await M.resume(id, plan, () => {}, { signal: again.signal, deleteOnCancel: true }).catch(() => {});
  assert.deepEqual(M.unfinishedAreas(), []);
});

test("resuming an area that was deleted is refused before any request", async () => {
  const fetch = fakeFetch();
  const { M } = load({ fetch });
  await assert.rejects(M.resume("gone", M.plan(39.7392, -104.9903, 10), () => {}), { code: "unknownArea" });
  assert.equal(fetch.calls.length, 0);
});

test("only download reaches the network", () => {
  const start = src.indexOf("// BEGIN download");
  const end = src.indexOf("// END download");
  assert.ok(start > 0 && end > start, "the download section is marked");
  const inside = src.slice(start, end);
  const outside = src.slice(0, start) + src.slice(end);
  const fetches = [...src.matchAll(/fetch\(/g)].map((m) => m.index);
  assert.ok(fetches.length >= 1);
  for (const i of fetches) assert.ok(i > start && i < end, "fetch( outside download");
  assert.match(inside, /https:\/\/tiles\.openfreemap\.org/);
  for (const [url] of inside.matchAll(/https?:\/\/[^'"\s]*/g)) {
    assert.ok(url.startsWith("https://tiles.openfreemap.org/"), url);
  }
  assert.doesNotMatch(outside, /openfreemap\.org|https?:\/\//);
  for (const word of ["XMLHttpRequest", "WebSocket", "sendBeacon", "EventSource", "navigator.connection"]) {
    assert.ok(!src.includes(word), word);
  }
  // The one dynamic import loads MapLibre from the app's own map folder.
  assert.equal(src.split("import(").length - 1, 1);
  assert.ok(src.includes("import(baseUrl() + 'maplibre-gl.mjs')"));
});

// MARK: - Drawing a route

const inDenver = [[39.7392, -104.9903], [39.7400, -104.9890], [39.7410, -104.9880]];

function finishedDenver(M) {
  const id = M.beginArea(M.plan(39.7392, -104.9903, 10), "Denver");
  M.finishArea(id);
  return id;
}

test("a route outside every area is the plain line", () => {
  const gl = fakeMapLibre();
  const { M, win } = load({ maplibregl: gl });
  const container = win.document.createElement("div");
  const drawn = [];
  const h = M.mount(container, inDenver, { aspect: 2, fallback: (c, pts) => drawn.push([c, pts]) });
  assert.equal(drawn.length, 1);
  assert.equal(drawn[0][0], container);
  assert.equal(drawn[0][1], inDenver);
  assert.equal(gl.maps.length, 0);
  h.destroy();
});

test("a covered route is drawn over the streets, from local files only", async () => {
  const gl = fakeMapLibre();
  const { M, win } = load({ maplibregl: gl });
  finishedDenver(M);
  const container = win.document.createElement("div");
  const h = M.mount(container, inDenver, { aspect: 2, dark: true, fallback: () => assert.fail("no line") });
  await tick();
  assert.equal(gl.maps.length, 1);
  const map = gl.maps[0];
  const o = map.options;
  assert.equal(o.style, `${ORIGIN}/lift/map/style-dark.json`);
  assert.equal(o.attributionControl, false);
  assert.equal(o.interactive, false);
  assert.deepEqual(o.transformRequest("https://tiles.openfreemap.org/planet/v1/1/0/0.pbf"), { url: "liftmap://refused" });
  assert.deepEqual(o.transformRequest("https://example.com/x.png"), { url: "liftmap://refused" });
  assert.deepEqual(o.transformRequest("liftmap://tiles/14/3413/6218"), { url: "liftmap://tiles/14/3413/6218" });
  const styled = o.transformStyle(undefined, JSON.parse(readFileSync(join(here, "..", "style-dark.json"), "utf8")));
  assert.deepEqual(styled.sources.openmaptiles.tiles, ["liftmap://tiles/{z}/{x}/{y}"]);
  assert.equal(gl.workerUrl, `${ORIGIN}/lift/map/maplibre-gl-worker.mjs`);

  // The attribution sits on the map, not in MapLibre's control.
  const words = JSON.stringify(container, (k, v) => (k === "parentNode" ? undefined : v));
  assert.ok(words.includes("© OpenStreetMap contributors · OpenFreeMap"));

  // The route goes on top once the style has loaded: 5 px, round, two dots.
  map.fire("load");
  const line = map.layers.find((l) => l.type === "line");
  assert.equal(line.paint["line-width"], 5);
  assert.equal(line.layout["line-cap"], "round");
  assert.equal(line.paint["line-color"], "#C1442C");
  const dots = map.layers.filter((l) => l.type === "circle").map((l) => [l.paint["circle-radius"], l.paint["circle-color"]]);
  assert.deepEqual(dots, [[5, "#7C8B7A"], [6, "#C1442C"]]);
  assert.equal(map.layers.at(-1).id, "lift-route-end-dot");
  assert.equal(map.fits.length, 1);
  assert.deepEqual(map.fits[0][1].padding, { top: 24, right: 24, bottom: 50, left: 24 }, "the attribution never covers the route");
  assert.equal(map.fits[0][1].animate, false);
  h.destroy();
  assert.equal(map.removed, true);
});

test("the tile protocol answers from the cache, and never the network", async () => {
  const gl = fakeMapLibre();
  const fetch = fakeFetch();
  const { M, win } = load({ maplibregl: gl, fetch });
  const plan = M.plan(39.7392, -104.9903, 10);
  const id = M.beginArea(plan, "A");
  await M.putTile(id, { z: 14, x: 3413, y: 6218 }, new Uint8Array([7, 8]).buffer);
  M.finishArea(id);
  M.mount(win.document.createElement("div"), inDenver, { fallback: () => {} });
  await tick();
  const serve = gl.protocols.liftmap;
  assert.equal(typeof serve, "function");
  const hit = await serve({ url: "liftmap://tiles/14/3413/6218", type: "arrayBuffer" }, new AbortController());
  assert.deepEqual([...new Uint8Array(hit.data)], [7, 8]);
  const miss = await serve({ url: "liftmap://tiles/14/1/1", type: "arrayBuffer" }, new AbortController());
  assert.equal(miss.data.byteLength, 0);
  const refused = await serve({ url: "liftmap://refused", type: "arrayBuffer" }, new AbortController());
  assert.equal(refused.data.byteLength, 0);
  assert.equal(fetch.calls.length, 0);
});

test("the map decides again when an area finishes or is deleted", async () => {
  const gl = fakeMapLibre();
  const { M, win } = load({ maplibregl: gl });
  const container = win.document.createElement("div");
  let lines = 0;
  const h = M.mount(container, inDenver, { fallback: () => { lines += 1; } });
  assert.equal(lines, 1);
  assert.equal(gl.maps.length, 0);

  const id = finishedDenver(M);
  await tick();
  assert.equal(gl.maps.length, 1, "a finished download draws the streets");
  assert.equal(gl.maps[0].removed, false);

  await M.deleteArea(id);
  await tick();
  assert.equal(gl.maps[0].removed, true, "a deleted area takes the map away");
  assert.equal(lines, 2, "and the plain line comes back, never a blank square");
  h.destroy();
});

test("a fix that stays inside the route's bounds does not read the index again", async () => {
  const gl = fakeMapLibre();
  const { M, win, storage } = load({ maplibregl: gl });
  finishedDenver(M);
  const h = M.mount(win.document.createElement("div"), inDenver, { fallback: () => {} });
  await tick();
  gl.maps[0].fire("load");
  const reads = storage.reads;
  h.update([...inDenver, [39.7395, -104.9895]]);
  h.update([...inDenver, [39.7396, -104.9896]]);
  assert.equal(storage.reads, reads, "same bounds, same decision");
  const route = gl.maps[0].sources["lift-route"];
  assert.equal(route.data.geometry.coordinates.length, 4);
  h.update([...inDenver, [39.75, -104.98]]);
  assert.ok(storage.reads > reads, "new bounds are decided again");
  assert.equal(gl.maps.length, 1, "the same map, refitted");
  h.destroy();
});

test("a map that cannot be made is the plain line", async () => {
  const gl = fakeMapLibre();
  gl.Map = class { constructor() { throw new Error("no WebGL"); } };
  const { M, win } = load({ maplibregl: gl });
  finishedDenver(M);
  let lines = 0;
  M.mount(win.document.createElement("div"), inDenver, { fallback: () => { lines += 1; } });
  await tick();
  assert.ok(lines >= 1);
});

test("a style that fails to load falls back to the line", async () => {
  const gl = fakeMapLibre();
  const { M, win } = load({ maplibregl: gl });
  finishedDenver(M);
  let lines = 0;
  M.mount(win.document.createElement("div"), inDenver, { fallback: () => { lines += 1; } });
  await tick();
  const before = lines;
  gl.maps[0].fire("error");
  assert.equal(gl.maps[0].removed, true);
  assert.equal(lines, before + 1);
});

// MARK: - The words, the iPhone's

test("the copy is the iPhone's, word for word", () => {
  const { M } = load();
  const swift = ["LiftMap/StreetsSheet.swift", "LiftMap/MapsSection.swift", "LiftMap/RouteMap.swift", "LiftCore/RouteCanvas.swift"]
    .map((f) => readFileSync(join(here, "..", "..", "Sources", f), "utf8")).join("\n");
  for (const [k, v] of Object.entries(M.copy)) assert.ok(swift.includes(`"${v}"`), `${k}: ${v}`);
  assert.equal(M.copy.attribution, "© OpenStreetMap contributors · OpenFreeMap");
  assert.equal(M.copy.source, "OpenStreetMap data from OpenFreeMap");
  assert.equal(M.copy.serverLearns, "OpenFreeMap learns which area you asked for, once.");
  assert.equal(Object.isFrozen(M.copy), true);
  assert.equal(M.deleteTitle("Streets around 39.74, -104.99"), "Delete Streets around 39.74, -104.99?");
  assert.equal(M.radiusText(25), "25 km");
  assert.equal(M.nameAround(39.7392, -104.9903), "Streets around 39.74, -104.99");
  assert.equal(M.sizeText(40_000_000), "About 40 MB");
  assert.equal(M.sizeText(24_800_000), "About 24.8 MB");
  assert.equal(M.bytesText(512_000), "512 KB");
  assert.equal(M.bytesText(999_999), "1 MB");
  assert.equal(M.bytesText(1_250_000_000), "1.25 GB");
});

// MARK: - The vendored engine and the checksum the apps pin

test("MapLibre is the release VENDOR.md names, byte for byte", async () => {
  const { createHash } = await import("node:crypto");
  const vendor = readFileSync(join(here, "VENDOR.md"), "utf8");
  assert.match(vendor, /\*\*6\.16\.0\*\*/);
  const rows = [...vendor.matchAll(/^\| `([^`]+)` \| `[^`]+` \| `([0-9a-f]{64})` \|$/gm)];
  assert.deepEqual(rows.map((r) => r[1]).sort(),
    ["LICENSE-maplibre.txt", "maplibre-gl-worker.mjs", "maplibre-gl.css", "maplibre-gl.mjs"]);
  for (const [, file, hash] of rows) {
    assert.equal(createHash("sha256").update(readFileSync(join(here, file))).digest("hex"), hash, file);
  }
  assert.match(readFileSync(join(here, "maplibre-gl.mjs"), "utf8").slice(0, 300), /v6\.16\.0/);
});

test("the checksum file lists every web file the apps copy", () => {
  const listed = readFileSync(join(here, "..", "map-files.sha256"), "utf8").trim().split("\n").map((l) => l.slice(66));
  for (const f of ["map.js", "maplibre-gl.mjs", "maplibre-gl-worker.mjs", "maplibre-gl.css", "LICENSE-maplibre.txt", "VENDOR.md"]) {
    assert.ok(listed.includes(`web/${f}`), f);
  }
  assert.ok(!listed.some((l) => l.endsWith(".test.mjs")));
});
