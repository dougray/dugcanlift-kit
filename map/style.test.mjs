import test from "node:test";
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { manifest, mapFiles } from "./write-checksum.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const styles = { light: "style-light.json", dark: "style-dark.json" };
const text = (f) => readFileSync(join(here, f), "utf8");
const LAYERS = new Set(["water", "waterway", "landcover", "landuse", "park",
  "transportation", "transportation_name", "place", "boundary", "building"]);

test("no style names a server", () => {
  for (const f of Object.values(styles)) assert.doesNotMatch(text(f), /https?:/i, f);
});

test("each style has exactly the two placeholders", () => {
  for (const f of Object.values(styles)) {
    assert.equal(text(f).split("{{TILES}}").length - 1, 1, f);
    assert.equal(text(f).split("{{GLYPHS}}").length - 1, 1, f);
    const s = JSON.parse(text(f));
    assert.equal(s.version, 8);
    assert.equal(s.sources.openmaptiles.type, "vector");
    assert.equal(s.sources.openmaptiles.url, "{{TILES}}");
    assert.equal(s.glyphs, "{{GLYPHS}}");
    assert.equal("sprite" in s, false);
  }
});

test("only OpenMapTiles layers are drawn", () => {
  for (const f of Object.values(styles)) {
    for (const l of JSON.parse(text(f)).layers) {
      if (l.type === "background") continue;
      assert.equal(l.source, "openmaptiles", l.id);
      assert.ok(LAYERS.has(l["source-layer"]), `${f}: ${l.id} draws ${l["source-layer"]}`);
      for (const font of l.layout?.["text-font"] ?? []) assert.equal(font, "Noto Sans Regular");
    }
  }
});

test("colors are LIFT's", () => {
  const bg = (f) => JSON.parse(text(f)).layers.find((l) => l.type === "background").paint["background-color"];
  assert.equal(bg(styles.light), "#F4EFE7");
  assert.equal(bg(styles.dark), "#1C1B19");
  for (const f of Object.values(styles)) assert.doesNotMatch(text(f), /#B23C25|#C1442C/i, f);
});

test("roads stay thinner than the 5 px route", () => {
  for (const f of Object.values(styles)) {
    for (const l of JSON.parse(text(f)).layers.filter((l) => l.type === "line")) {
      const w = l.paint["line-width"];
      const stops = typeof w === "number" ? [w] : w.stops.map((s) => s[1]);
      for (const v of stops) assert.ok(v < 5, `${f}: ${l.id} width ${v}`);
    }
  }
});

test("the checksum file matches every map file", () => {
  const rels = mapFiles(here);
  assert.equal(text("map-files.sha256"), manifest(here));
  assert.ok(rels.includes("style-light.json") && rels.includes("fonts/OFL.txt"));
  assert.equal(rels.filter((r) => r.endsWith(".pbf")).length, 256);
});

test("every glyph range ships, empty where Noto has nothing", () => {
  // MapLibre Native never finishes laying out a tile whose glyph range is
  // missing, so the street draws blank; an empty range is no glyphs.
  for (let start = 0; start <= 65280; start += 256) {
    const f = join(here, "fonts", "Noto Sans Regular", `${start}-${start + 255}.pbf`);
    assert.ok(statSync(f).isFile(), f);
  }
});

test("dotfiles never enter the manifest", () => {
  const dir = mkdtempSync(join(tmpdir(), "map-files-"));
  try {
    mkdirSync(join(dir, "fonts"));
    writeFileSync(join(dir, "style-light.json"), "{}");
    writeFileSync(join(dir, ".DS_Store"), "x");
    writeFileSync(join(dir, "fonts", ".DS_Store"), "x");
    mkdirSync(join(dir, ".hidden"));
    writeFileSync(join(dir, ".hidden", "a.pbf"), "x");
    assert.deepEqual(mapFiles(dir), ["style-light.json"]);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
