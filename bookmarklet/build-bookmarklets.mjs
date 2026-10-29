// Writes bookmarklets.json and bookmarklets.sha256 from send-recipe.js.
// Usage: node bookmarklet/build-bookmarklets.mjs [--check]
//   --check exits 1 if either file is out of date (CI runs it).
//
// Each value is a complete javascript: URL, ready to save as a bookmark. The
// apps copy both files verbatim, as they copy road-food.json, and show the one
// for their own target.
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const OUT = join(here, 'bookmarklets.json');
const SUM = join(here, 'bookmarklets.sha256');

export const TARGETS = {
  liftWeb: { name: 'LIFT', target: 'https://www.dugcanlift.com/lift/' },
  coachWeb: { name: 'Coach', target: 'https://www.dugcanlift.com/coach/' },
  liftApp: { name: 'LIFT', target: 'dugcanliftlift://recipe' },
  coachApp: { name: 'Coach', target: 'dugcanliftcoach://recipe' },
};

// Comments and line breaks out, nothing renamed: the source stays readable in
// send-recipe.js and the bookmark is that source, compacted.
export function compact(source) {
  return source
    .split('\n')
    .filter((line) => !line.trim().startsWith('//'))
    .map((line) => line.trim())
    .join('');
}

export function bookmarklet(source, { name, target }) {
  const code = compact(source).replaceAll('__NAME__', name).replaceAll('__TARGET__', target);
  // Percent-encoded because a javascript: URL's own `#` would start a fragment
  // and cut the script short; the browser decodes it before running it.
  return 'javascript:' + encodeURIComponent(code);
}

export function build() {
  const source = readFileSync(join(here, 'send-recipe.js'), 'utf8');
  const doc = {
    note: 'Built from send-recipe.js by build-bookmarklets.mjs. Never edit by hand.',
    format: 'r1',
  };
  for (const [key, t] of Object.entries(TARGETS)) doc[key] = bookmarklet(source, t);
  return Buffer.from(JSON.stringify(doc, null, 1) + '\n', 'utf8');
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const data = build();
  const digest = createHash('sha256').update(data).digest('hex') + '\n';
  if (process.argv.includes('--check')) {
    const stale = [[OUT, data], [SUM, Buffer.from(digest)]]
      .filter(([p, want]) => !existsSync(p) || !readFileSync(p).equals(want))
      .map(([p]) => p.split('/').pop());
    if (stale.length) {
      console.error(`out of date: ${stale.join(', ')} -- run node bookmarklet/build-bookmarklets.mjs`);
      process.exit(1);
    }
    console.log('bookmarklets.json matches send-recipe.js');
  } else {
    writeFileSync(OUT, data);
    writeFileSync(SUM, digest);
    console.log(`wrote bookmarklets.json (${data.length} bytes) and bookmarklets.sha256`);
  }
}
