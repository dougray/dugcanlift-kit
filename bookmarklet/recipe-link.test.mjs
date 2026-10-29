import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { deflateRawSync } from 'node:zlib';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { build, TARGETS } from './build-bookmarklets.mjs';
import { decodeRecipeLink, MAX_BYTES } from './recipe-link.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const fixture = (name) => readFileSync(join(here, 'fixtures', name), 'utf8');
const bookmarklets = JSON.parse(readFileSync(join(here, 'bookmarklets.json'), 'utf8'));

// Runs a built javascript: URL the way a browser would, against a stand-in
// page, and resolves with the address it navigates to (or the alert it shows).
function run(url, { blocks, href = 'https://example.com/recipes/stew' }) {
  const code = decodeURIComponent(url.slice('javascript:'.length));
  return new Promise((resolve) => {
    const document = {
      querySelectorAll: (sel) => {
        assert.equal(sel, 'script[type="application/ld+json"]');
        return blocks.map((textContent) => ({ textContent }));
      },
    };
    const location = {
      get href() { return href; },
      set href(next) { resolve({ navigated: next }); },
    };
    const alert = (message) => resolve({ alert: message });
    new Function('document', 'location', 'alert', code)(document, location, alert);
  });
}

const page = JSON.parse(fixture('page-jsonld.json'));

test('bookmarklets.json is what send-recipe.js builds', () => {
  assert.ok(readFileSync(join(here, 'bookmarklets.json')).equals(build()),
    'run node bookmarklet/build-bookmarklets.mjs');
});

test('every target is a javascript: URL with no raw # in it', () => {
  for (const key of Object.keys(TARGETS)) {
    assert.match(bookmarklets[key], /^javascript:/);
    assert.ok(!bookmarklets[key].includes('#'), key);
  }
});

test('the bookmarklet sends the page address and its recipe blocks, and nothing else', async () => {
  const { navigated } = await run(bookmarklets.liftApp, { blocks: page.blocks });
  assert.ok(navigated.startsWith('dugcanliftlift://recipe#r1'), navigated);
  const decoded = decodeRecipeLink(navigated);
  // The breadcrumb block mentions no recipe and is left behind.
  assert.deepEqual(decoded, { url: 'https://example.com/recipes/stew', jsonld: [page.blocks[0]] });
});

test('each target opens its own app or page', async () => {
  const want = {
    liftWeb: 'https://www.dugcanlift.com/lift/#r1',
    coachWeb: 'https://www.dugcanlift.com/coach/#r1',
    liftApp: 'dugcanliftlift://recipe#r1',
    coachApp: 'dugcanliftcoach://recipe#r1',
  };
  for (const [key, prefix] of Object.entries(want)) {
    const { navigated } = await run(bookmarklets[key], { blocks: page.blocks });
    assert.ok(navigated.startsWith(prefix), `${key}: ${navigated.slice(0, 40)}`);
  }
});

test('a page with no recipe says so, by name, and goes nowhere', async () => {
  const lift = await run(bookmarklets.liftWeb, { blocks: [page.blocks[1]] });
  assert.match(lift.alert, /no recipe LIFT can read/);
  const coach = await run(bookmarklets.coachApp, { blocks: [] });
  assert.match(coach.alert, /Paste a recipe in Coach/);
});

test('the fixture link decodes to the expected page', () => {
  const link = fixture('recipe-link.txt').trim();
  assert.deepEqual(decodeRecipeLink(link), JSON.parse(fixture('recipe-link-expected.json')));
});

test('the fixture link is what the bookmarklet writes for the fixture page', async () => {
  // Pins the fixture to the encoder, so a decoder port that agrees with the
  // fixture agrees with the bookmarklet people actually run.
  const { navigated } = await run(bookmarklets.liftApp, { blocks: page.blocks });
  assert.equal(navigated, fixture('recipe-link.txt').trim());
});

const encode = (obj) => '#r1' + deflateRawSync(Buffer.from(JSON.stringify(obj)))
  .toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

test('refusals', () => {
  const ok = { v: 1, url: 'https://a.example/r', jsonld: ['{"@type":"Recipe"}'] };
  assert.ok(decodeRecipeLink(encode(ok)));
  assert.equal(decodeRecipeLink('dugcanliftlift://recipe'), null, 'no fragment');
  assert.equal(decodeRecipeLink('#1zabc'), null, 'a log link is not a recipe link');
  assert.equal(decodeRecipeLink('#r1!!!'), null, 'not base64url');
  assert.equal(decodeRecipeLink('#r1AAAA'), null, 'not deflate');
  assert.equal(decodeRecipeLink(encode({ ...ok, v: 2 })), null, 'unknown version');
  assert.equal(decodeRecipeLink(encode({ ...ok, url: 'javascript:alert(1)' })), null, 'not http(s)');
  assert.equal(decodeRecipeLink(encode({ ...ok, url: 7 })), null, 'url not a string');
  assert.equal(decodeRecipeLink(encode({ ...ok, jsonld: 'x' })), null, 'jsonld not an array');
  assert.equal(decodeRecipeLink(encode({ ...ok, jsonld: [] })), null, 'no blocks');
  assert.equal(decodeRecipeLink(encode({ ...ok, jsonld: [3, null] })), null, 'no string blocks');
});

test('a non-string block is dropped, not fatal', () => {
  const doc = { v: 1, url: 'http://a.example/r', jsonld: [5, '{"@type":"Recipe"}'] };
  assert.deepEqual(decodeRecipeLink(encode(doc)).jsonld, ['{"@type":"Recipe"}']);
});

test('more than MAX_BYTES once inflated is refused', () => {
  const big = { v: 1, url: 'https://a.example/r', jsonld: ['x'.repeat(MAX_BYTES + 1)] };
  assert.equal(decodeRecipeLink(encode(big)), null);
});
