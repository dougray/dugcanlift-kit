#!/usr/bin/env node
// Writes map/map-files.sha256: one "<sha256>  <path>" line per file under map/,
// sorted by path, leaving out this checksum file, this writer and *.test.mjs.
// Apps pin their copies to it. Usage: node map/write-checksum.mjs
import { createHash } from "node:crypto";
import { readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, relative, sep } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(fileURLToPath(import.meta.url));
const files = [];
const walk = (d) => {
  for (const n of readdirSync(d)) {
    const p = join(d, n);
    if (statSync(p).isDirectory()) walk(p); else files.push(p);
  }
};
walk(root);
const rels = files.map((p) => relative(root, p).split(sep).join("/"))
  .filter((r) => r !== "map-files.sha256" && r !== "write-checksum.mjs" && !r.endsWith(".test.mjs"))
  .sort();
const out = rels.map((r) => `${createHash("sha256").update(readFileSync(join(root, r))).digest("hex")}  ${r}`).join("\n") + "\n";
writeFileSync(join(root, "map-files.sha256"), out);
console.log(`wrote ${rels.length} lines`);
