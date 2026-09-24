# Road Food: sources

Where every number in `road-food.json` came from, when it was read, and what a
reviewer should look at before it ships. Check the file with
`node data/validate-road-food.mjs`.

Ground rules: restaurant figures come only from the chain's own published
nutrition (its site, its PDF, the JSON its own nutrition page loads, or the
calculator its own nutrition page embeds). Snacks come only from USDA
FoodData Central Branded Foods (CC0). Nothing came from memory, estimates,
aggregators, SR Legacy, MenuStat or Open Food Facts, and nothing came from
anyone's nutrition database searched on its own account. A chain whose current
numbers could not be read from its own source is left out. Blank stays blank:
a field the source doesn't give is omitted.

**On embedded calculators (2026-09-24).** Two chains publish their food
nutrition only through a Nutritionix calculator embedded in their own
nutrition page. Doug's call is that this is the chain's own published source:
the chain chose the calculator, put it on its own page, and supplies the
figures it serves - it is their chart with someone else's software drawing it.
That is not the same as searching Nutritionix's database, which remains out.
The distinction is mechanical, so the check enforces it: for Taco Bell and
Sheetz it first re-reads the chain's own page and confirms the embed is still
there, and says so in the report. If the chain drops the embed, the figures
stop being the chain's own and the entry has to be re-read.

Raw copies of every page, PDF and JSON that was read were kept during curation.
They are not committed, because they are the chains' own files.

## Chains in the file (13 chains, 108 items)

`Read on` is the chain's `checkedOn`; `publishedOn` is the date the document
states about itself, blank when it states none. See "Published on" in
`README.md` for why metadata, `Last-Modified` and upload paths do not count.

| Chain | kind | Items | Source | Read on | `publishedOn` | What the document says about its own date |
|---|---|---|---|---|---|---|
| Wendy's | burgers | 7 | `api.app.prd.wendys.digital/.../NutritionServices/rest/nutritionalData` (the API order.wendys.com's nutrition panel calls) | 2026-09-20 | — | menu generated 2026-09-21T00:02 UTC — a live feed, which states no date of publication |
| Sonic | burgers | 7 | Nutrition brochure PDF linked from sonicdrivein.com/nutrition-allergen/ (Contentful asset host) | 2026-09-20 | — | "SUMMER 2026" — a season, not a month; the file is named September and its properties say September 2026, neither of which is the document speaking |
| Burger King | burgers | 9 | `bk-use1-prod.sites.rbictg.com/nutrition/nutrition.pdf` (RBI's production host for bk.com, the same host Popeyes' PDF sits on) | 2026-09-23 | 2022-11 | **"BURGER KING® USA Nutrition Information — NOVEMBER 2022"**, on every page |
| Whataburger | burgers | 9 | https://wbimageserver.whataburger.com/Nutrition.pdf | 2026-09-23 | 2021-03-29 | **"Nutritional information as of March 29, 2021"** (the file itself was created 2021-02-02; the printed statement is later and wins) |
| Chick-fil-A | chicken | 10 | https://www.chick-fil-a.com/nutrition-allergens (JSON embedded in the page) | 2026-09-20 | — | none shown |
| Popeyes | chicken | 6 | https://plk-use1-prod.sites.rbictg.com/nutrition/PLK_Nutrition.pdf (linked from popeyes.com) | 2026-09-20 | 2026-08 | "Popeyes® USA Nutrition Guide — August 2026", and "current as of August 2026" in the footnote (the file properties still say "Nutrition FEBRUARY 2023", a stale template title) |
| Taco Bell | mexican | 10 | The Nutritionix calculator embedded at https://www.tacobell.com/nutrition/info, whose menu grid is `www.nutritionix.com/taco-bell/menu/premium` | 2026-09-24 | 2026-09-24 | **"Last Updated: 09/24/2026"** above and below the grid |
| Chipotle | mexican | 9 | https://www.chipotle.com/content/dam/chipotle/menu/nutrition/US-Nutrition-Facts-Paper-Menu-3-2025.pdf | 2026-09-23 | 2024-10 | **footer code `OCT-2024-US-CK`** |
| Subway | sandwiches | 8 | us-nutrition-en.pdf on media.subway.com (the "Nutrition Data Tables" link on subway.com) | 2026-09-20 | 2026-01 | "U.S. NUTRITION INFORMATION — January 2026" |
| Starbucks | coffee | 8 | starbucks.com product nutrition pages, read through the `/apiproxy/v1/ordering/{product}/{form}` JSON they render from | 2026-09-20 | — | none shown |
| Panera Bread | coffee | 8 | https://www.panerabread.com/content/dam/panerabread/documents/c8-26-nutrition-guide.pdf | 2026-09-20 | 2026-09-02 | "Effective: 9/2/2026 Edition: 1", on every page |
| Sheetz | gas-station-kitchen | 9 | The Nutritionix calculator embedded at https://www.sheetz.com/nutrition, whose menu grid is `www.nutritionix.com/sheetz/menu/premium` | 2026-09-24 | 2026-09-23 | **"Last Updated: 09/23/2026"** on the calculator and on the grid |
| QuikTrip | gas-station-kitchen | 8 | https://www.quiktrip.com/app/uploads/2025/09/nutritional-facts.pdf (linked from quiktrip.com product pages) | 2026-09-20 | — | none printed anywhere in the document; its file properties say 2025-09-12 and its URL path says 2025/09, neither of which is the document speaking |

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
- **Burger King.** The PDF is served from RBI's production site host, the same one
  Popeyes' PDF sits on, and it is the only Burger King nutrition document that
  answers a plain request: bk.com/nutrition-explorer and every bk.com PDF path
  return the app shell, and company.bk.com no longer resolves.
  - **The document is dated NOVEMBER 2022** (Last-Modified 2022-12-02), so
    `publishedOn` is `2022-11`. It is what Burger King publishes today, and the
    nine items are rows a four-year-old chart is least likely to have moved on
    - the plain burgers, nuggets and Chicken Fries - but four years is four
    years. The apps say so in words: the chain page reads "Published Nov 2022 ·
    checked Sep 23, 2026" and warns "These numbers are from the chain's chart
    dated Nov 2022."
  - *"Hold the cheese to save 40 kcal"* is read off the chart's own rows, not
    guessed: Cheeseburger 290 minus Hamburger 250, Double Cheeseburger 400
    minus Double Hamburger 360, and American Cheese (2 slices) 80 kcal. All
    three agree at 40 kcal a slice.
  - **Dropped: both chicken salads.** Chicken Garden Salad is published as 550
    kcal with 81 g of carbohydrate, and Chicken Club Salad as 670 with 82 g.
    Those carbohydrate figures are 30% out by 4/4/9 and look like a chart
    error, so neither is in the file.
  - **Dropped: Garden Side Salad and 4 pc Nuggets.** Both publish "< 1" for
    fibre. Blank stays blank, and an item the check cannot read a full row for
    is not worth the entry.
  - PDFKit glues the "Beverage" section heading to the milk row, so the
    locator's `row` is "BeverageFat FREE Milk (8 fl oz)". `pdftotext` will
    almost certainly split it differently.
- **Whataburger.** wbimageserver.whataburger.com is still the only Whataburger
  nutrition document that a request can reach; whataburger.com is a JavaScript
  shell and whataburger.com/files/Nutrition.pdf redirects into it. The ordering
  API needs a key from the app bundle and was not touched.
  - **The document says "Nutritional information as of March 29, 2021."** Five
    and a half years, so `publishedOn` is `2021-03-29` and every screen says
    "Published Mar 29, 2021". **This is the weakest link in the file.** Every
    item chosen avoids the `*` (limited market) and `†` (limited time) marks,
    which is the best that can be done from inside the document, but a 2021
    chart cannot know what left the menu in 2024. The file itself was created
    2021-02-02; the printed statement is nearly two months later, which is why
    the printed statement is the one recorded.
  - Salads: the chart lists dressings in their own "DIPPING SAUCES &
    DRESSINGS" section and says nothing about whether a salad row includes one.
    The serving text says "dressing listed separately", which is what the
    document supports; it does not claim the row is dressing-free.
  - Whatachick'n Bites (4) is the kids'-menu row, as Popeyes' 1-piece tender is.
  - The `®` and `™` marks are dropped from the names and kept in the locators,
    because the locator matches the PDF's text and the name is what a screen
    shows.
- **Chipotle.** The PDF is linked under chipotle.com's own content path. The
  live calculator is a keyed API (`Ocp-Apim-Subscription-Key` out of the order
  site's bundle) and was not used: a key lifted from someone else's page is not
  a published source.
  - **The document is footed OCT-2024** (Last-Modified 2025-03-05), so
    `publishedOn` is `2024-10` and the screens read "Published Oct 2024". The
    file name says 3-2025 and the server says March 2025; the footer is the
    document's own statement and wins over both.
  - **The rows are components, not meals**, which is how Chipotle publishes and
    how a bowl is actually ordered. Nothing is summed. Cilantro-Lime Brown Rice
    is in the list at 1.9 g of protein per 100 kcal, last in any ranking, so a
    bowl can be logged as it was built rather than only its meat.
  - *"Double chicken is this row twice"* is the whole modification: the chart
    publishes a 4 oz portion and says nothing about an 8 oz one, so the line
    says what to log rather than a number.
  - Page 1 of the PDF is the paper menu, whose prose repeats "CHICKEN* 180 cal
    | 4 oz". Every locator reads after the nutrition table's own "Protein (g)"
    heading so the prose cannot match first.
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
- **Taco Bell.** tacobell.com/nutrition/info renders the full nutrition grid
  inline, inside the Nutritionix calculator it embeds; the page's own HTML
  names that widget as the thing it renders. The grid is server-rendered HTML
  with a row per item and a column per figure, read straight out of it.
  - **The widget prints "Last Updated: 09/24/2026"**, which is the day it was
    read. That is not a coincidence the file should hide: other brands on the
    same widget print older dates of their own (Wendy's 08/05/2025, Subway
    03/22/2025), so the line is a real per-brand date and not a render stamp,
    and Taco Bell's simply moved that day. If a later check reports that the
    document no longer states 2026-09-24, that is the widget being updated
    again, not a fault. **Doug: worth a second look.**
  - **There are no Power Menu Bowls.** They are not on the chart at all. The
    Cantina Chicken Bowl is the bowl the current menu has, and it is in the
    file.
  - **Fresco Style publishes no figure.** The chart's own disclaimer says
    Fresco-Style "replaces any mayo based sauces, reduced-fat sour cream,
    nacho cheese sauce, and shredded cheeses with diced tomatoes" and that it
    "typically results in a reduction in calories and fat" - no number, and no
    per-item Fresco row anywhere. So the two `modification` lines say the swap
    and say plainly that no figure is published, the way Chipotle's "double
    chicken is this row twice" states no number. They are worded as an
    ordering option, not a claim about what any item contains, because the
    chart does not publish ingredients. **Doug: cut them if a derived-free
    modification is still too much.**
  - **Dropped: Cantina Chicken Crispy Taco.** It publishes "< 1" for sugar,
    like Burger King's dropped rows. Blank stays blank.
  - Items were taken from the standing menu sections. The two nugget rows and
    the strips sit in the grid's "New" section, which is where Taco Bell files
    its newest standing items; they are the highest-protein rows on the whole
    chart, and if they leave the menu the quarterly check will not know - only
    a person reading the grid will.
  - `®` is dropped from the names and kept in the locators, as Whataburger's
    are.
- **Sheetz.** sheetz.com/nutrition embeds the calculator; the same widget
  publishes the whole menu as a grid at `/sheetz/menu/premium`, which is what
  the figures were read from. The chain page is the `source` because it is the
  chain's own page and the embed is what makes these Sheetz's figures; the
  grid address is in the locator, and the check confirms the embed each run.
  - **Sheetz's own page is 9 MB and takes over a minute to send.** The check
    gives it a longer timeout for that one request, and reads one string out
    of it.
  - **Traps in the grid, deliberately avoided.** Several made-to-order rows
    are named like a finished sandwich but are only its meat: "MTO Grilled
    Chicken Sandwich" is 120 kcal with 0 g of carbohydrate (the same row as
    "Grilled Chicken Breast Filet"), and "Made-To-Order Steakhouse Cutz Sub -
    Half" is 190 kcal with 2 g - no roll. Those are the calculator's
    build-your-own starting points, and none of them is in the file under a
    sandwich's name. The one component that is in the file, Grilled Chicken
    Breast Filet, says so in its serving text.
  - **"Catina Bowl" is spelled that way on the chart.** It looks like Sheetz's
    typo for Cantina. The name is what the source publishes. **Doug: say the
    word and it is spelled Cantina, at the cost of no longer matching.**
  - **Dropped: Farmhouse and Sausage Keto Cups, and Shredded Chicken.** Each
    publishes "< 1" in a column the file carries. The Mexican Keto Cup, whose
    row is clean, is in.
  - **Dropped: Protein Showdown** (330 kcal, 20 g protein). The chart gives no
    serving and no description, and nothing about the item says what one of it
    is, so there is no honest `serving` to write.
  - The grid repeats an item in every menu section it belongs to. The repeats
    agree for every item in the file, and the check refuses to pick among
    repeats that disagree rather than taking the first.
  - Drinks were left out. Sheetz's own server-rendered page covers drinks and
    the protein lattes rank high, but the kitchen is what the entry is for.
- **QuikTrip.** The PDF's text interleaves rows, so every item was re-read by
  position on the page.
  - Grab & Go wraps and subs are the pre-made case items. The made-to-order
    grid was ambiguous and was not used.
  - **Dropped: Protein Scramble** (590 kcal, 47 g fat), a poor fit.
  - Sodium is high across the board (up to 2,070 mg).
  - The PDF is a year old, but it is the one QuikTrip's pages link today.

## Chains left out

Re-tried on 2026-09-23, with the same ground rules: the chain's own published
document, one plain request each, a User-Agent naming this work, no retries and
nothing worked around. Taco Bell and Sheetz came off this list on 2026-09-24,
when an embedded official calculator became an acceptable source; the other
four are still out for reasons the rule change does not touch.

| Chain | Why |
|---|---|
| McDonald's | Every mcdonalds.com path answers **HTTP 403** to a plain request - the nutrition calculator, the full menu, and the `/content/dam/.../nutrition` PDF paths alike. A WebFetch of the calculator is refused the same way. There is no US PDF on another host. Not bypassed. |
| Jersey Mike's | `subs.jerseymikes.com/nutrition/{product}/{size}` returns **per-ingredient rows only** - values like `136.539000` calories - and the page sums the default ingredients in the browser for its "Totals" footer. There is no published total to read; producing one means re-running the page's arithmetic. Left out under "don't sum components". **Doug:** still a policy call, not a data problem. |
| Wawa | wawa.com's own pages (`/nutrition/lower-sodium` and its siblings) publish **calories and sodium only** - no protein, fat or carbohydrate - so nothing there can fill a required field. The full calculator is still behind a 403. |
| Buc-ee's | buc-ees.com still publishes no nutrition at all: not a figure on the site. |

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
kind-specific line each for burgers, chicken, mexican, sandwiches, coffee and
gas-station-kitchen. Two `"snacks"` rules show only on the Gas station
screen. The Mexican line was held back in the first pass because no Mexican
chain made it; Chipotle brought it in, and Taco Bell is the second chain it
shows on. Sheetz is the second gas-station kitchen. No rule was added or
changed for either.

## Refresh

`node data/check-road-food.mjs` re-reads each source above and diffs it
against the file; snack figures are re-derived from FDC by id. It writes
`data/road-food-CHECK.md` and never updates the bundle. How to run it and the
quarterly routine are in `data/README.md`.
