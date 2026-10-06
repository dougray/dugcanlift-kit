// Writes Tests/LiftCoreTests/Fixtures/route-projection-expected.json from
// Coach web's own coach/route.js: decodePolyline() then project(), at a square
// and a wide size. Run from the kit's root:
//
//   node scripts/make-route-projection-fixture.mjs ../dugcanlift-coach/coach/route.js
//
// The output is the oracle RouteProjectionTests checks the Swift port
// against. Never regenerate it from Swift: a fixture written by the code under
// test would agree with any bug in it.
import { readFileSync, writeFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';

const routeJs = resolve(process.argv[2] ?? '');
// route.js is an IIFE over `typeof window !== 'undefined' ? window : globalThis`.
new Function(readFileSync(routeJs, 'utf8'))();
const R = globalThis.CoachRoute;
if (!R) throw new Error(`no CoachRoute in ${routeJs}`);

const input = JSON.parse(readFileSync('Tests/LiftCoreTests/Fixtures/outdoor-share-expected.json', 'utf8'));
const polyline = input.lr[5];
const points = R.decodePolyline(polyline);
const sizes = [[300, 300], [343, 180]];
const commit = execSync('git rev-parse --short HEAD', { cwd: dirname(routeJs) }).toString().trim();

const out = {
  note: `Written by Coach web's coach/route.js (dugcanlift-coach ${commit}) under node: `
    + 'decodePolyline() then project(). Never regenerate from Swift.',
  polyline,
  cases: sizes.map(([width, height]) => ({
    width, height,
    points: R.project(points, width, height).map((p) => [p.x, p.y]),
  })),
};
writeFileSync('Tests/LiftCoreTests/Fixtures/route-projection-expected.json', JSON.stringify(out, null, 1) + '\n');
console.log(`${points.length} points at ${sizes.length} sizes`);
