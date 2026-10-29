// "Send to LIFT" / "Send to Coach": the bookmarklet body. build-bookmarklets.mjs
// fills in __NAME__ and __TARGET__ and turns this into four javascript: URLs.
//
// It runs on a recipe page the person already has open, and hands LIFT or Coach
// the same thing Safari's share extension hands the iPhone apps (RecipePage.js):
// the page's address and the raw text of its schema.org JSON-LD blocks. The
// browser already has the page, so neither the bookmarklet nor the app requests
// anything. The payload rides in the link LIFT or Coach opens -- after `#` on
// the web, so it never reaches a server, and in a custom scheme for the apps.
//
// Wire format, read by every build (README.md, "Recipe links"):
//   <target>#r1<base64url(deflate-raw(JSON))>
//   JSON = {"v":1,"url":"<page address>","jsonld":["<block text>", ...]}
(async () => {
  const blocks = Array.from(document.querySelectorAll('script[type="application/ld+json"]'))
    .map((s) => s.textContent || '')
    .filter((t) => /recipe/i.test(t));
  if (!blocks.length) {
    alert('This page has no recipe __NAME__ can read. Copy the recipe text and use Paste a recipe in __NAME__ instead.');
    return;
  }
  const json = JSON.stringify({ v: 1, url: location.href, jsonld: blocks });
  const deflated = new Blob([json]).stream().pipeThrough(new CompressionStream('deflate-raw'));
  const bytes = new Uint8Array(await new Response(deflated).arrayBuffer());
  let binary = '';
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  const data = btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  location.href = '__TARGET__' + '#r1' + data;
})();
