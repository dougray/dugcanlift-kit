# Recipe links: "Send to LIFT" and "Send to Coach"

A bookmarklet the person saves once and taps on any recipe page. It hands the
page's recipe to LIFT or Coach, on the web or in the installed app, **without
either one requesting the page**. The browser already has the page; the
bookmarklet reads its schema.org JSON-LD and opens a link carrying it. This is
the in-house rule's answer for every place Safari's share extension does not
reach: Android, the two web apps, and Chrome on iPhone.

It hands over exactly what Safari's share extension hands the iPhone apps
(`RecipePage.js`): the page's address and the raw text of its `ld+json` blocks.
So every build passes the blocks to the JSON-LD reader it already has
(`LiftCore.RecipeJSONLD`, kit-android's `RecipeJsonLd`, Coach web's
`recipeFromJsonLdPayload`) and opens the review it already has. The raw text is
the contract, as it is for Safari.

| File | What it is |
|---|---|
| `send-recipe.js` | The bookmarklet's source. Edited by hand. |
| `build-bookmarklets.mjs` | Writes `bookmarklets.json` and its checksum. CI runs it with `--check`. |
| `bookmarklets.json` | The four ready `javascript:` URLs. Never edited by hand. |
| `bookmarklets.sha256` | sha256 of `bookmarklets.json`'s bytes. Pinned by every app that ships it. |
| `recipe-link.mjs` | The reference decoder. Every build ports it. |
| `fixtures/recipe-link.txt` | A link the bookmarklet itself wrote, for `fixtures/page-jsonld.json`. |
| `fixtures/recipe-link-expected.json` | What it decodes to. Every port is checked against this pair. |

## The four targets

| Key | Opens | Used by |
|---|---|---|
| `liftWeb` | `https://www.dugcanlift.com/lift/#r1…` | LIFT web |
| `coachWeb` | `https://www.dugcanlift.com/coach/#r1…` | Coach web |
| `liftApp` | `dugcanliftlift://recipe#r1…` | LIFT iPhone and LIFT Android |
| `coachApp` | `dugcanliftcoach://recipe#r1…` | Coach iPhone and Coach Android |

On the web the payload is after `#`, so it never reaches the server. The app
targets reuse the iPhone apps' existing custom schemes; the Android apps
register the same two schemes with host `recipe`, so one bookmark works on
either phone.

## Wire format

```
<target>#r1<base64url(deflate-raw(JSON)), no padding>
JSON = {"v":1,"url":"<page address>","jsonld":["<block text>", ...]}
```

- Only blocks whose text contains "recipe" (any case) are sent. Never an
  exhaustive filter, only a size one; the reader decides what is a Recipe.
- A decoder **refuses** (no review opens, the app says the link could not be
  read) on: no `r1` prefix, bad base64url, bad deflate, more than 512 KiB
  inflated, JSON that is not `v: 1` with an `http`/`https` `url` and a
  `jsonld` array, or no string blocks. A non-string block is dropped, not
  fatal, as on the iPhone.
- The `url` becomes the recipe's source address, as a Safari share's does. It
  is never fetched.
- Measured on real pages: BBC Good Food 3.0 KB, Allrecipes 8.3 KB.

## Rules every build follows

- **Review, then save.** The link opens the build's existing review of a
  JSON-LD recipe (or, where a build has none, its recipe editor filled from
  it). Nothing is saved by opening a link.
- **Strip it once read.** The web apps remove the fragment with
  `history.replaceState` as soon as they have read it, as Coach web already
  does for log links, so a reload or a shared address never re-imports.
- **Macros follow the build's existing link-import rule** -- on the iPhones
  `LinkImportMacros` (the source's own figures win, costing only fills a gap,
  nothing costable stays nil).
- **Never fetch.** Not the page, not its images.
- **Show the bookmarklet where the person imports.** Each Cook tab offers
  "Send recipes from your browser" with the build's own `javascript:` string,
  a Copy button, and the steps to save it as a bookmark. Desktop browsers can
  drag it to the bookmarks bar; phone browsers need the copy-and-edit steps.
