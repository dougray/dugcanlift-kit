#!/usr/bin/env node
// Writes map/map-files.sha256: one "<sha256>  <path>" line per file under map/,
// web/ included (map.js, the vendored MapLibre GL JS and VENDOR.md), sorted by
// path, leaving out this checksum file, this writer, *.test.mjs and anything
// whose name starts with "." (a Finder .DS_Store must never enter the
// manifest). Every app pins its copy to it: the native builds the styles and
// fonts, LIFT web and Coach web all of it. Usage: node map/write-checksum.mjs
import { createHash } from "node:crypto";
import { readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

/** Every file the manifest lists under `root`, as sorted "/"-separated paths. */
export function mapFiles(root) {
  const files = [];
  const walk = (d) => {
    for (const n of readdirSync(d)) {
      if (n.startsWith(".")) continue;
      const p = join(d, n);
      if (statSync(p).isDirectory()) walk(p); else files.push(p);
    }
  };
  walk(root);
  return files.map((p) => relative(root, p).split(sep).join("/"))
    .filter((r) => r !== "map-files.sha256" && r !== "write-checksum.mjs" && !r.endsWith(".test.mjs"))
    .sort();
}

/** The manifest's text for `root`. */
export function manifest(root) {
  return mapFiles(root)
    .map((r) => `${createHash("sha256").update(readFileSync(join(root, r))).digest("hex")}  ${r}`)
    .join("\n") + "\n";
}

const self = fileURLToPath(import.meta.url);
if (process.argv[1] && resolve(process.argv[1]) === self) {
  const root = dirname(self);
  const out = manifest(root);
  writeFileSync(join(root, "map-files.sha256"), out);
  console.log(`wrote ${out.trim().split("\n").length} lines`);
}
