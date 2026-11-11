# Vendored: MapLibre GL JS

| | |
|---|---|
| Package | `maplibre-gl` |
| Version | **6.16.0** (published to npm 2026-10-25; the newest release at least two weeks old on 2026-11-10) |
| Source | `https://registry.npmjs.org/maplibre-gl/-/maplibre-gl-6.16.0.tgz` |
| Tarball sha256 | `1504a18021fc6d9329a9dc7c949525822c8ae5e2fe3e3751df9262a13af5de4b` |
| Tarball integrity (npm) | `sha512-gApO66EMtoDZuio680RUBvskR7ahFd/NNhLN4tBAs+Y7FeT4gQV8zVFgYVMRmFxQznOEzecW19w6xOd9XjZjiA==` |
| Licence | BSD-3-Clause, `LICENSE-maplibre.txt` (the package's `LICENSE.txt`) |

Each file is copied byte for byte from the tarball, never edited:

| File here | From the package | sha256 |
|---|---|---|
| `maplibre-gl.mjs` | `dist/maplibre-gl.mjs` | `fbbdf8ddd9a48e49059a4be6795a4f214a711314bb5809f72d3730b48e7897e3` |
| `maplibre-gl-worker.mjs` | `dist/maplibre-gl-worker.mjs` | `0bf06492bdb7ba3d4132b78e435621bfba60d5250967991c02b1a73affea8cd5` |
| `maplibre-gl.css` | `dist/maplibre-gl.css` | `a90798a1953017790e590f7e1bd35ff103a8a4263972cb47290b78adf86f8c20` |
| `LICENSE-maplibre.txt` | `LICENSE.txt` | `ee5fc05a0677eaf69601d2c7db0d9ecd6cc27c3abc1d0733bc9ed34707cf8ef2` |

## Why `.mjs`, and how it loads

MapLibre GL JS 6 ships ES modules only: there is no `dist/maplibre-gl.js`
script build any more. LIFT web and Coach web stay classic scripts, so
`map.js` (a classic script) loads MapLibre with one dynamic
`import(baseUrl() + 'maplibre-gl.mjs')` from the app's own map folder, the
first time a route is covered by downloaded streets. A route with no
downloaded streets never loads it. `map.js` sets the worker to
`<base>maplibre-gl-worker.mjs` with `setWorkerUrl`, so the worker's address
carries no `?v=` query and a service worker can cache it under its plain path.
It adds `maplibre-gl.css` itself, once.

Every one of these is on the app's own origin. Nothing is loaded from a CDN.

A server must send `.mjs` as JavaScript (`text/javascript`); GitHub Pages does.

The two `.mjs` files end in a `//# sourceMappingURL=` comment. The maps are not
vendored: a browser asks for one only while its developer tools are open, and
gets a 404 from the app's own origin.

## Updating

1. `npm pack maplibre-gl@<version>` into an empty scratch directory (never run
   its scripts), and check the tarball's sha512 against `npm view
   maplibre-gl@<version> dist.integrity`.
2. Copy the four files above over these, update this table, and run
   `node map/write-checksum.mjs`.
3. `node --test map/*.test.mjs map/web/*.test.mjs`, then copy `map/` into both
   apps with the new `map-files.sha256`.
