# Road Food: sources

Where every number in `road-food.json` came from, when it was read, and what a
reviewer should look at before it ships. Check the file with
`node data/validate-road-food.mjs`.

Ground rules: restaurant figures come only from the chain's own published
nutrition (its site, its PDF, or the JSON its own nutrition page loads). Snacks
come only from USDA FoodData Central Branded Foods (CC0). Nothing came from
memory, estimates, aggregators, SR Legacy, MenuStat, Nutritionix or Open Food
Facts. A chain whose current numbers could not be read from its own source is
left out. Blank stays blank: a field the source doesn't give is omitted.

Raw copies of every page, PDF and JSON that was read were kept during curation.
They are not committed, because they are the chains' own files.

## Chains in the file (8 chains, 62 items)

| Chain | kind | Items | Source | Read on | Source's own date |
|---|---|---|---|---|---|
| Wendy's | burgers | 7 | `api.app.prd.wendys.digital/.../NutritionServices/rest/nutritionalData` (the API order.wendys.com's nutrition panel calls) | 2026-09-20 | menu generated 2026-09-21T00:02 UTC |
| Sonic | burgers | 7 | Nutrition brochure PDF linked from sonicdrivein.com/nutrition-allergen/ (Contentful asset host) | 2026-09-20 | "Summer 2026", file named September |
| Chick-fil-A | chicken | 10 | https://www.chick-fil-a.com/nutrition-allergens (JSON embedded in the page) | 2026-09-20 | none shown |
| Popeyes | chicken | 6 | https://plk-use1-prod.sites.rbictg.com/nutrition/PLK_Nutrition.pdf (linked from popeyes.com) | 2026-09-20 | "current as of August 2026" |
| Subway | sandwiches | 8 | us-nutrition-en.pdf on media.subway.com (the "Nutrition Data Tables" link on subway.com) | 2026-09-20 | January 2026 |
| Starbucks | coffee | 8 | starbucks.com product nutrition pages, read through the `/apiproxy/v1/ordering/{product}/{form}` JSON they render from | 2026-09-20 | none shown |
| Panera Bread | coffee | 8 | https://www.panerabread.com/content/dam/panerabread/documents/c8-26-nutrition-guide.pdf | 2026-09-20 | effective 9/2/2026, edition 1 |
| QuikTrip | gas-station-kitchen | 8 | https://www.quiktrip.com/app/uploads/2025/09/nutritional-facts.pdf (linked from quiktrip.com product pages) | 2026-09-20 | PDF dated 2025-09-12 |

The exact `source` URL for each chain is in the JSON.

How the numbers were read. For PDFs: download, extract the text with PDFKit,
read each row from that raw text, then re-check every value against its row
with a script. For embedded or API JSON: read the values directly. Every item
was also checked for energy (4P + 4C + 9F against kcal). All are within about
5%, except Popeyes' Signature Chicken Breast, which is 12% under but is the
published figure.

### Per-chain notes and doubts

- **Wendy's.** There is no US PDF; the only PDFs on wendys.com are UK ones.
  The figures come from the same API calls the order site's nutrition panel
  makes (national menu, siteNum 0), built from each item's default components.
  They match the menu feed's own per-item figures exactly. `source` is the
  endpoint's base URL.
  - *Dave's Single, "Hold the mayo to save 50 kcal":* this is the calculator's
    own answer to a request with the Mayo component removed (510 kcal). But the
    request was built from the site's JS, not clicked in a browser. **Doug:
    keep or drop.**
  - 4 PC. Tenders exclude the two dipping sauces; the serving text says so.
  - Both chilis include crackers.
  - Salads were skipped, because "calories do not include dressing" and the
    default build was unclear.
- **Sonic.** There is no grilled chicken item on the current menu. Premium
  Chicken Bites are the medium size. "1% White Milk" is from the Wacky Pack
  kids' menu, with no volume printed. The only mayo row, "Light Mayo," isn't
  tied to any burger, so no modifications.
- **Chick-fil-A.** The table is embedded in the page as JSON, and the values
  were spot-checked against the page's own screen-reader text.
  - Grilled Chicken Club is the Colby Jack row (the standard cheese).
  - Chicken Tortilla Soup lists 17 g fibre on 265 g. That looks high, but it
    is the published figure.
  - 1% Milk is the published 213 g carton.
- **Popeyes.** popeyes.com is a JS shell. The PDF link was found in the site's
  own CMS page record for "Nutrition & Allergen Information", which is the
  link the site shows. Names were title-cased from the PDF's all-caps.
  - "Tender - Classic" (1 piece) is the kids'-meal row.
  - Blackened tenders are the standout (3 pc: 170 kcal, 28 g protein), but
    their sodium is high.
- **Subway.** The Fresh Fit subs include multigrain bread, deluxe protein and
  all vegetables. Protein bowls use the footlong meat portion and exclude
  cheese and dressing.
  - **Dropped: the Grilled Chicken Protein Bowl** (620 kcal, 44 g fat). The
    6-inch grilled chicken portion is only 2 g fat, so the bowl row must
    include a sauce or cheese that its footnote says it doesn't. The figure
    is published, but a person ordering a plain chicken bowl would over-log.
  - "Grilled Chicken (6-inch portion)" lists 2 g fat and 2 g saturated fat.
    That is odd but published.
  - The Subway Club bowl is 2,280 mg sodium.
- **Starbucks.** One JSON call per item; the numbers match the page's display
  strings.
  - The protein latte is a Grande made with Starbucks' standard
    protein-boosted milk; another milk changes it.
  - Each item's own URL: product numbers 2122117, 2122116, 368, 371, 40677,
    2124812 and 2122004 (single), and 28500 (iced).
- **Panera Bread.** curl got an Akamai 403. One WebFetch retrieved the PDF
  itself, and the numbers were read from its extracted text, not from any
  summary.
  - The wraps and eggs are from the Grab N Go section and may not be in every
    café.
  - The PDF lists a whole-portion Green Goddess dressing (150 kcal), but it
    doesn't state that the Cobb uses that portion, so no dressing
    modification.
- **QuikTrip.** The PDF's text interleaves rows, so every item was re-read by
  position on the page.
  - Grab & Go wraps and subs are the pre-made case items. The made-to-order
    grid was ambiguous and was not used.
  - **Dropped: Protein Scramble** (590 kcal, 47 g fat), a poor fit.
  - Sodium is high across the board (up to 2,070 mg).
  - The PDF is a year old, but it is the one QuikTrip's pages link today.

## Chains left out

| Chain | Why |
|---|---|
| McDonald's | mcdonalds.com resets or stalls non-browser connections (bot protection). One WebFetch timed out. No PDF exists. Not bypassed. |
| Burger King | bk.com's PDF URLs return an app shell. company.bk.com no longer resolves. The Nutrition Explorer loads from a Sanity/RBI GraphQL backend that would have to be reverse-engineered. An originqa.bk.com PDF is a QA host and dated 2022. |
| Whataburger | The only published document (wbimageserver.whataburger.com/Nutrition.pdf, still the footer link) is dated **March 29, 2021**. The ordering API needs an API key from the app bundle. **Doug:** if a 2021 document is acceptable, clean rows exist (e.g. #11 Grilled Chicken Sandwich 430 kcal / 32 g). |
| Chipotle | The newest US PDF on chipotle.com (`US-Nutrition-Facts-Paper-Menu-3-2025.pdf`) is footed **OCT-2024** and is no longer linked from any current chipotle.com page; it was found by search. The live calculator uses a keyed API. Left out for the same reason as Whataburger. **Doug:** the proteins are the kind of thing that rarely changes (Chicken 4 oz: 180 kcal, 32 g protein), so this is a judgement call. The 10 curated component rows can be re-read from that PDF in minutes. |
| Taco Bell | tacobell.com publishes calories only. Its full nutrition is an embedded Nutritionix iframe, which the brief excludes. **Doug:** if a chain's own embedded official calculator counts as the chain's source, Taco Bell (and Sheetz) become possible. |
| Jersey Mike's | The calculator's JSON gives unrounded per-ingredient rows; the page sums the default ingredients for its "Totals" footer. Reproducing that footer is re-running the page's arithmetic rather than reading a published figure, and the results carry values like 1153.04 mg. Left out under "don't sum components". **Doug:** the reconstruction matched the page's code exactly, so this is a policy call, not a data problem. |
| Sheetz | sheetz.com's own HTML has only drink nutrition. Food is a Nutritionix iframe, and the ordering site sits behind Imperva. |
| Wawa | The full calculator is behind an Incapsula 403. wawa.com's own "Calorie-Conscious" page and its PDF give kcal and protein only, and **disagree with each other** on the same items (e.g. Original Chicken Sandwich 37 g vs 41 g protein). |
| Buc-ee's | buc-ees.com publishes no nutrition at all. |

## Snacks (22 products, 9 categories)

Source: USDA FoodData Central, Branded Foods (public domain, CC0), searched
through the FDC API on 2026-09-20/21. Each entry's `source` is its FDC page
and `fdcId` is its id. `barcode` is FDC's `gtinUpc`, kept exactly as FDC
stores it (some have a leading 0 or 00, some don't: normalise when matching
scans). No Open Food Facts data was used.

**How per-serving figures were made.** FDC stores branded nutrients per
100 g/ml, derived from the label. The label panel itself (`labelNutrients`)
was empty on these records. Each figure is therefore the per-100 value times
the serving size, rounded to one decimal, then rounded by the FDA label rules
(21 CFR 101.9: kcal to 5 or 10, fat to 0.5 or 1, grams to 1, sodium to 5 or
10). It has **not** been checked against physical labels. It is a derivation,
not a copy of the label, and it may be off by one rounding step.
Under 1 g ("<1 g" on a label) would be left blank; none remained. **Doug:
worth scanning a few products in hand against the file.**

| Category | Products (fdcId, FDC publication date) |
|---|---|
| Beef jerky and meat sticks | Jack Link's Original Beef Jerky (2675686, 2023-11); Chomps Original Beef Stick (2652237, 2023-10) |
| Protein bars | Quest S'mores (2669774, 2023-11); Pure Protein S'mores (2545908, 2023-05); Premier Protein Salted Caramel (1926282, 2021-07); RXBAR Blueberry (2659057, 2023-10) |
| Greek yogurt | Oikos Triple Zero Mixed Berry (2775572, 2026-08); Oikos Plain Nonfat (2619049, 2023-08) |
| String cheese | Sargento Light (2622114, 2023-08); Frigo Cheese Heads Light (2471313, 2023-02); Polly-O (2597806, 2023-07) |
| Hard-boiled eggs | Hillandale Eggs2Go, 2 eggs (2484289, 2023-02); Almark, 1 egg (2104085, 2021-10) |
| Tuna and chicken pouches | StarKist Chunk Light Tuna in Water pouch (2490104, 2023-02); Sweet Sue Premium Chicken Breast pouch (1 pouch, 2077402, 2021-10) |
| Nuts | Blue Diamond Roasted Salted Almonds 1.5 oz package (2655951, 2023-10); Wonderful Pistachios Roasted & Salted (2674310, 2023-11) |
| Protein shakes | Premier Protein Chocolate 11.5 oz (2622653, 2023-08); Core Power Elite Chocolate 42g 14 oz (2742751, 2025-09); Muscle Milk Chocolate 11 oz (2460427, 2023-02) |
| Fruit | Dole Mixed Fruit in 100% Fruit Juice cup (2672034, 2023-11); Crunch Pak Apple Slices (2627630, 2023-08) |

Snack doubts:
- **FDC's figures are only as fresh as the manufacturer's last submission.**
  Several are from 2021–2023, and recipes change.
- **Fruit.** Whole bananas and apples are not in Branded Foods (fresh produce
  carries no label). The two fruit entries are a packaged cup and packaged
  slices. The Crunch Pak record's serving is 140 g (1.5 cups), a bag-serving,
  not a single snack pack.
- **Dropped: Great Day Farms Hard-Boiled Egg (2390333).** Its FDC record gives
  8 g fat for a 60 kcal egg, which is impossible, so the record is wrong.
- **Quest S'mores:** 180 kcal against 239 by 4/4/9. The 13 g fibre and sugar
  alcohols explain it; the figure is FDC's.
- **Missing fields, left blank:**
  - Almark eggs: fibre and sugar.
  - StarKist pouch: sugar.
  - Core Power Elite: fibre and saturated fat.
- **Zeros are FDC's stored 0**, e.g. Pure Protein fibre 0 and Crunch Pak
  protein 0. FDC does not distinguish a label "0 g" from a missing value
  entered as 0; the ones kept are all plausible.
- **Snack `name` includes the brand**, because LIFT web shows only `name`;
  `brand` is also there for iOS. iOS may want to avoid printing both.
- **Picking.** Several FDC records often exist for one product (different pack
  sizes or years), sometimes with different numbers (e.g. Jack Link's Original
  at 10 g vs 11 g protein per oz). The most recent manufacturer-submitted
  record matching a single-serve or standard size was used. The 2026 records
  with no brand owner (retailer-sourced, with odd serving weights) were
  avoided.

## Rules

Five plain rules show on every chain (the spec's timeless ones). One
kind-specific line each for burgers, chicken, sandwiches, coffee and
gas-station-kitchen. Two `"snacks"` rules show only on the Gas station
screen. The Mexican line was written but left out, because no Mexican chain
made it; add it back with Chipotle or Taco Bell.

## Refresh

Re-read each source above and diff against the file (the spec's refresh
script). Snack figures are re-derived from FDC by id. Never auto-update the
bundle.
