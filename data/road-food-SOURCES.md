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

## Chains in the file (19 chains, 164 items)

`Read on` is the chain's `checkedOn`; `publishedOn` is the date the document
states about itself, blank when it states none. See "Published on" in
`README.md` for why metadata, `Last-Modified` and upload paths do not count.

| Chain | kind | Items | Source | Read on | `publishedOn` | What the document says about its own date |
|---|---|---|---|---|---|---|
| Wendy's | burgers | 7 | `api.app.prd.wendys.digital/.../NutritionServices/rest/nutritionalData` (the API order.wendys.com's nutrition panel calls) | 2026-09-20 | — | menu generated 2026-09-21T00:02 UTC — a live feed, which states no date of publication |
| Sonic | burgers | 7 | Nutrition brochure PDF linked from sonicdrivein.com/nutrition-allergen/ (Contentful asset host) | 2026-09-20 | — | "SUMMER 2026" — a season, not a month; the file is named September and its properties say September 2026, neither of which is the document speaking |
| Burger King | burgers | 9 | `bk-use1-prod.sites.rbictg.com/nutrition/nutrition.pdf` (RBI's production host for bk.com, the same host Popeyes' PDF sits on) | 2026-09-23 | 2022-11 | **"BURGER KING® USA Nutrition Information — NOVEMBER 2022"**, on every page |
| Whataburger | burgers | 9 | https://wbimageserver.whataburger.com/Nutrition.pdf | 2026-09-23 | 2021-03-29 | **"Nutritional information as of March 29, 2021"** (the file itself was created 2021-02-02; the printed statement is later and wins) |
| Chick-fil-A | chicken | 10 | https://www.chick-fil-a.com/nutrition-allergens (JSON embedded in the page) | 2026-10-28 | — | none shown |
| Popeyes | chicken | 6 | https://plk-use1-prod.sites.rbictg.com/nutrition/PLK_Nutrition.pdf (linked from popeyes.com) | 2026-09-20 | 2026-08 | "Popeyes® USA Nutrition Guide — August 2026", and "current as of August 2026" in the footnote (the file properties still say "Nutrition FEBRUARY 2023", a stale template title) |
| Taco Bell | mexican | 10 | The Nutritionix calculator embedded at https://www.tacobell.com/nutrition/info, whose menu grid is `www.nutritionix.com/taco-bell/menu/premium` | 2026-09-24 | 2026-09-24 | **"Last Updated: 09/24/2026"** above and below the grid |
| Chipotle | mexican | 9 | https://www.chipotle.com/content/dam/chipotle/menu/nutrition/US-Nutrition-Facts-Paper-Menu-3-2025.pdf | 2026-09-23 | 2024-10 | **footer code `OCT-2024-US-CK`** |
| Subway | sandwiches | 8 | us-nutrition-en.pdf on media.subway.com (the "Nutrition Data Tables" link on subway.com) | 2026-09-20 | 2026-01 | "U.S. NUTRITION INFORMATION — January 2026" |
| Starbucks | coffee | 8 | starbucks.com product nutrition pages, read through the `/apiproxy/v1/ordering/{product}/{form}` JSON they render from | 2026-09-20 | — | none shown |
| Panera Bread | coffee | 8 | https://www.panerabread.com/content/dam/panerabread/documents/c8-26-nutrition-guide.pdf | 2026-09-20 | 2026-09-02 | "Effective: 9/2/2026 Edition: 1", on every page |
| Sheetz | gas-station-kitchen | 9 | The Nutritionix calculator embedded at https://www.sheetz.com/nutrition, whose menu grid is `www.nutritionix.com/sheetz/menu/premium` | 2026-10-28 | 2026-10-23 | **"Last Updated: 10/23/2026"** on the calculator and on the grid (it said 09/23/2026 when first read on 2026-09-24) |
| QuikTrip | gas-station-kitchen | 8 | https://www.quiktrip.com/app/uploads/2025/09/nutritional-facts.pdf (linked from quiktrip.com product pages) | 2026-09-20 | — | none printed anywhere in the document; its file properties say 2025-09-12 and its URL path says 2025/09, neither of which is the document speaking |
| Arby's | sandwiches | 10 | `Arbys_Nutritional_and_Allergen_NOV_2026.pdf` on assets.ctfassets.net (Arby's Contentful space), linked from https://www.arbys.com/nutrition/ | 2026-10-28 | 2026-10 | **"This information is effective as of October 2026."** in the page-10 footnote (the file name says NOV_2026 and the server's Last-Modified is 2026-10-20; neither is the document speaking) |
| Love's | gas-station-kitchen | 9 | `loves-fresh-food-fda-master8242026.pdf` on Love's Sitecore asset host (`edge.sitecorecloud.io/lovestravela9dd-loves2161-lovesprod042a-cf5a/...`), the "View a list of allergens and nutrition information" link on https://www.loves.com/store-offerings/food-and-beverages | 2026-10-28 | — | none printed anywhere: the title is just "LOVE'S NUTRITIONAL INFORMATION". The file name says 8242026 and the server's Last-Modified is 2026-08-24, neither of which is the document speaking |
| Pilot Flying J | gas-station-kitchen | 9 | https://pilotcompany.com/file/nutrition-facts (the "Nutrition Facts" link on pilotcompany.com/food-and-drink; it answers with the PDF itself) | 2026-10-28 | — | none printed anywhere in the 58 pages. The server's Content-Disposition names the file `Item-Nutrition-Food-Beverage-October-26.pdf`, which is not the document speaking |
| Culver's | burgers | 10 | The Nutritionix calculator embedded at https://www.culvers.com/nutrition-and-allergen-guide (an iframe of `r.nutritionix.com/culvers/landing`), whose menu grid is `www.nutritionix.com/culvers/menu/premium` | 2026-10-28 | 2026-10-16 | **"Last Updated: 10/16/2026"** above and below the grid |
| Dunkin' | coffee | 8 | `DD_W7_nutrition_guide.pdf` on assets.ctfassets.net (Contentful), the "Nutrition Guide" link on https://www.dunkindonuts.com/nutrition/ | 2026-10-28 | 2026-09-21 | **"The information below was last updated on 09-21-2026."** at the head of both the Limited Time and Permanent sections |
| Jack in the Box | burgers | 10 | PDF on cdn.sanity.io (`content-production/5cbdb27f...pdf`), the `nutritionUrl` in jackinthebox.com's own home-page data | 2026-10-28 | — | **"2026 NUTRITION FACTS"** as the title, and **"The ingredient and nutrient information contained in this analysis is effective as of November 2026."** - a month after it was read |

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
  - Chicken Tortilla Soup lists 18 g fibre on 265 g. That looks high, but it
    is the published figure.
  - **Re-read 2026-10-28** after the refresh check reported the soup had
    moved. One plain request for the page (200); the soup's row in the
    embedded JSON, and its screen-reader text, now read 350 kcal, 25 g
    protein, 11 g fat, 39 g carbohydrate, 18 g fibre, 1115 mg sodium (was 280,
    24, 7, 31, 17, 1060). Saturated fat (2.5 g) and sugar (4 g) are unchanged,
    and so is the serving: still "265g", so the serving text stands. 4/4/9
    gives 355 against 350. The same weight of soup carrying 70 kcal more reads
    as a recipe change, not a new size; the page does not say. The other nine
    items were re-read from the same response and every figure is as bundled.
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
  - **Re-read 2026-10-28** after the refresh check reported the grid had
    been republished. One plain request each for sheetz.com/nutrition (200,
    9.4 MB; it still embeds `nutritionix.com/sheetz/nutrition-calculator/premium`
    in its iframes), the grid (200) and the calculator (200). The grid and the
    calculator both print **"Last Updated: 10/23/2026"**, so `publishedOn` is
    `2026-10-23`. Eight of the nine items read exactly as bundled.
  - **"Skinny Grilled Chicken - Half" is now "Premium Chicken - Half".** No
    row of the old name is left anywhere in the grid or the calculator. A row
    named "Premium Chicken - Half" sits in the same sections a half sub sits
    in (MTO, Eat Shmart, and Subz, Sandwiches & Wrapz), and every figure the
    file carries is identical to the old row: 510 kcal, 38 g protein, 17 g fat
    (3 g saturated), 52 g carbohydrate, 5 g fibre, 7 g sugar, 1,740 mg sodium.
    Eight matching figures is the same sandwich, so this was treated as a
    rename: the id `sheetz-skinny-grilled-chicken-half` is kept, because item
    ids are what coaches' road picks travel on, and only the name and the
    locator row changed. The id now names the old wording; it is a key, not
    a label. The same republish brought "Premium Steak" and "Premium Chicken
    Caesar Salad" in beside the Steakhouse Cutz rows, which looks like a line
    renamed "Premium". What could not be checked: no copy of the September
    grid was kept, so whether a "Premium Chicken - Half" row already stood
    beside the Skinny one then is not known. **Doug: if you would rather a
    renamed item take a new id, say so; the old one would then be dropped
    and skipped silently by every client.**
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

- **Arby's.** www.arbys.com/nutrition/ answered a plain request with 200 and
  server-rendered HTML that links four PDFs on Arby's own Contentful asset host;
  "Nutritional and Allergen" is the nutrition table. One plain request for it,
  200, 316,572 bytes. Text extracted with PDFKit (`page.string`), every row read
  through `check-road-food-lib.mjs`'s own `findPdfRow` with the locator here,
  and each value then compared by eye with its line in the raw text.
  - **The file name says November 2026, the text says October 2026.** The text
    is the document speaking, so `publishedOn` is `2026-10`. A November date
    would also fail the validator (after `checkedOn`). **Doug:** if Arby's
    re-issues the same file in November with the footnote moved, the check will
    report "no longer states its date", which is the file being re-dated, not a
    fault.
  - Columns, left to right: serving weight (g), calories, calories from fat, fat,
    saturated fat, trans fat, cholesterol, sodium, carbohydrate, fibre, sugars,
    protein. PDFKit emits the twelve headings out of order, so the order was
    taken from the rows themselves (calories-from-fat ~ 9 x fat on every row;
    shakes show fibre 0-2 before sugars 64-138) and every item passes 4/4/9.
  - **Each row label runs on into its allergen statement**, and fried items
    wrap a "† ... (where available)" line under it, so the locators carry that
    text as extracted. "**Milk" on the roast beef rows is the footnote for
    buttered buns at two markets; the locator keeps it (asterisks are stripped
    when matching).
  - **Sauces are separate rows marked "Adds"** (Arby's Sauce 15 kcal, Horsey
    Sauce 60, dipping sauces 10-130), so the roast beef and tender rows exclude
    them; the serving text says so.
  - The French Dip row is "Classic French Dip & Swiss/Au Jus", so the au jus is
    counted; the name drops "/Au Jus" and the serving says "with au jus".
    Sodium 2,540 mg.
  - Half Pound Roast Beef is 2,040 mg sodium; the 5 tenders 1,990 mg.
  - **Milk is Shamrock Farms Lowfat White Milk (214 g)**, the Kids Menu row
    (repeated under Miscellaneous Drinks with the same figures). The chart also
    has "1% Lowfat Milk ... 8oz" (110 kcal, 8 g protein), but its serving
    column holds the word "8oz" instead of a gram weight, so the PDF check
    would read only 11 of the 12 cells and report it "not compared". The
    Shamrock row is clean and unmarked. **Doug:** swap it for the 8 oz 1% row
    if you would rather, at the cost of a locator the check cannot read.
  - **Avoided:** everything under LIMITED TIME OFFERS (Chicken Cheesesteaks,
    Steak Nuggets, Steak 'n Mac / Potato Bowls - Steak Nuggets (9) at 240 kcal /
    36 g would otherwise top the list), everything marked "•" ("may not be
    available at all Arby's restaurants": all of breakfast, chocolate milks,
    ArbyQ), and the OPTIONAL/REGIONAL block (Super Roast Beef, Roast Beef Gyro,
    Arby's Melt, Ham & Swiss Sandwich).
  - Not picked, all clean rows: the Beef 'n Cheddars (lower protein per kcal
    than the plain roast beef), Angus Cheesesteaks, Reuben, Turkey Ranch &
    Bacon (800 kcal), Chicken Slider, the crispy chicken sandwiches.
  - **No "< 1" anywhere in the chart**, so nothing was dropped for it.
  - **Energy check:** all ten within 5% of 4P+4C+9F. Largest: the milk, 90 kcal
    vs 86 (-4.4%), which is label rounding on a small number.
  - `kind` is `sandwiches` (Subway's), whose rule "A smaller sandwich with
    double meat beats a bigger one with single" is exactly the Double Roast
    Beef case. No new kind.
- **Love's.** loves.com/store-offerings/food-and-beverages answered a plain
  request (200) and links one PDF, "a list of allergens and nutrition
  information on our food and beverage options in our stores". The PDF
  (200, application/pdf, 439,208 bytes) sits on Love's own Sitecore asset
  tenant, the host the page itself links. It covers only food Love's makes
  and sells itself (bakery, bowls, roller grill, salads, sandwiches, tacos,
  wraps); none of the restaurant brands inside Love's stores are in it, and
  none of them are in this entry.
  - **How it was read.** PDFKit puts each food row on one line, with its
    allergen statement and serving between the name and the numbers
    ("Chef Salad Contains: Egg, Milk 9.2oz (261g) 1 260 153 17 ..."), so the
    locators carry that text exactly. Columns, left to right: Serving Size,
    Servings Per Container, Calories, Calories From Fat, Total Fat, Saturated
    Fat, Trans Fat, Cholesterol, Sodium, Total Carbohydrates, Dietary Fiber,
    Sugar, Protein. The column order was confirmed from the header's x
    positions and against the Hot Dog row (260 kcal, 207 kcal from fat, 23 g
    fat). Every value was re-checked with the kit's own `findPdfRow` against
    the extracted text: all 9 rows match.
  - **Section headings are printed at the foot of each page's text**, not
    above their rows, so "LIMITED TIME OFFER" was placed by its position on
    the page (line bounds from PDFKit): it sits above Steak & Queso Philly
    and Steak & Queso Taco only. **Both are left out.**
  - **Two items are per serving of a two-serving pack.** The chart's
    Servings Per Container is 2 for Hard-Boiled Eggs (89 g a serving) and the
    Club Wrap (162 g a serving), so the row is half the pack. The serving
    text says so in words. **Doug:** whether to add a `modification` "The
    whole pack is this row twice", in the way Chipotle's double-chicken line
    states no number of its own.
  - The salads (Chicken Caesar, Southwest Chicken, Chef) are published as
    single rows. The chart lists no dressings anywhere, so it says nothing
    either way about a dressing packet; the serving text claims nothing about
    one.
  - The drumsticks row gives 10 oz (291 g) and no piece count, so the serving
    is the weight. Sodium 1,770 mg.
  - Energy check (4P + 4C + 9F): every item is within 5%. Largest: Chicken
    Taco −4.3%, Spicy Chicken Sandwich +3.8%.
  - **Not picked, and why** (none of these is in the file):
    - Steak & Queso Philly, Steak & Queso Taco: limited time.
    - Cheddar Smoked Sausage: 170 kcal vs 152 by 4/4/9 (−11%).
    - Turkey & Cheese Wedge Sandwich: +7%. Chicken Bacon Ranch Wrap: −5.2%
      (the Club Wrap is the wrap in the file).
    - Hot Dogs (150 kcal, 17 g protein for one frank) looks odd beside the
      All-Beef Hot Dog's 11 g; published, but not chosen.
    - Maple Breakfast Sausage publishes "<1" for carbohydrate; several
      fountain rows publish "<1" or "> 1 gram". Blank stays blank.
    - Protein Snack Tray (560 kcal, 27 g protein) and the breakfast biscuits
      and croissants: a poor fit for a protein-per-calorie ranking.
  - Love's names the file after a date, so a replacement would arrive at a
    new address, as QuikTrip's does. The locator note says to confirm each
    quarter that the food-and-beverages page still links this PDF.
- **Pilot Flying J.** pilotflyingj.com/nutrition (both hosts) 301s to the
  pilotcompany.com home page; the company now trades as Pilot there. The
  home page links /food-and-drink, whose "Nutrition Facts" button ("Check out
  the full nutritional details for everything we offer") is
  `/file/nutrition-facts`. That address answered 200 with application/pdf
  directly (817,307 bytes, 58 pages, no redirect), so it is the `source`: the
  same address will serve whatever Pilot publishes next. The older
  `pilotflyingj.com/media/...food-nutrition-*-2020/2021.pdf` files a search
  turns up are not linked from anything and were not used.
  - Only food Pilot makes itself is in the PDF (pizza, wings and tenders, hot
    food, cold case, soup, roller grill, drinks). The restaurant brands inside
    Pilot stores are not in it and not in this entry.
  - **How it was read.** PDFKit gives one clean line per row: Item, Serving
    Size (g), Calories, Calories From Fat, Total Fat, Saturated Fat, Trans
    Fat, Cholesterol, Sodium, Total Carb, Dietary Fiber, Sugars, Protein -
    the same eleven numeric columns from the right as Burger King's. Every
    value was re-checked with the kit's own `findPdfRow` against the
    extracted text: all 9 rows match.
  - **No item in the file is starred.** Every page header says
    "*Available only in select locations", and the stars mark the
    select-location rows (the JUMBO Lunch Burritos, the dressing packets).
    On the Wings/Tenders and "Non Fryer Locations" pages a star or double star
    instead marks the non-fryer figure. Nothing starred was taken.
  - Section headings come at the foot of each page's text, after the rows
    they head; they were matched to their rows by page, not by order.
  - The two salads say "dressing listed separately": the chart has its own
    Dipping Sauce/Salad Dressing section and the salad rows do not say they
    include one.
  - Roasted Half Chicken is published as 252 g, which reads as the edible
    portion of a half bird; the serving text gives the chart's weight and
    nothing more. Sodium 1,830 mg; the Chicken Bacon Ranch Wrap is 2,070 mg.
  - The Boiled Egg Cup (180 g, 280 kcal, 24 g protein) gives no egg count.
  - Energy check: every item in the file is within 5% (largest: Chef Salad
    +4.7%, Boiled Egg Cup +4.3%).
  - **Left out, and why:**
    - **Chicken Tenders (5 ct): three rows with one name disagree.** 369 g /
      830 kcal on the Wings/Tenders page, 364 g / 910 kcal in Hot Food, and
      620 kcal for non-fryer stores. There is no telling which a traveller is
      handed.
    - **Wings:** the fryer and non-fryer figures differ (Mild 5 ct: 660 vs 520
      kcal), and a traveller cannot tell which kind of store they are in.
    - **Southern Chicken Sandwich:** published 550 kcal, but 31 g protein, 51 g
      carbohydrate and 12 g fat make 436 (−21%), and its own Calories From Fat
      (108) agrees with the 12 g. One of the figures is wrong; not used.
    - Smoked Turkey & Cheddar Wrap (+11%) and Steak & Gravy (+7.7%): over 5%
      out, and the sandwich versions are in the file.
    - Protein Box: +5.3%, with 260 mg sodium against 510 mg cholesterol, which
      reads oddly; not used.
    - Pizza: the chart carries two pizza programmes ("Pizza" and "Artisan",
      the second on the Non Fryer page) with different figures for a
      pepperoni slice (500 vs 550 kcal), and no way to tell which a store
      sells.
    - JUMBO Lunch Burritos: starred, select locations.
  - **Doug:** the chain's `name`. "Pilot Flying J" is what the travel centres
    are signed as; the website now says Pilot. The id `pilotflyingj` follows
    the brief.
- **Culver's.** culvers.com/nutrition-and-allergen-guide is server-rendered (Next.js) and
  its page data names a `ContentIframe` titled "Culver's Nutritionix Allergen & Nutrition
  Guide" with `iframeUrl` `https://r.nutritionix.com/culvers/landing`. That is the Taco
  Bell / Sheetz position: an embedded official calculator. The figures were read from the
  same brand's server-rendered grid at `www.nutritionix.com/culvers/menu/premium`, through
  the repo's own `parseNutritionixGrid` / `findNutritionixRow`, and every carried figure
  matches chain.json.
  - **The embed is the newer Nutritionix loader, not the grid URL itself.** Taco Bell's
    page names `nutritionix.com/taco-bell/menu/premium` outright; Culver's names
    `r.nutritionix.com/culvers/landing`, a JS app that loads
    `nix-vue-inm.s3.amazonaws.com/restaurant/culvers/data/menu-latest.json.gz`
    (generatedAt 2026-10-12T13:12Z). That data file was fetched once and every chosen item's
    stored total (`calculatedCalories` etc., precomputed by the widget, not summed in the
    browser) agrees with the grid after label rounding — e.g. Grilled Chicken Sandwich
    481.25 kcal / 35.74 g protein / 19.16 g fat vs 480 / 36 / 19. The locator's `embed`
    string is `r.nutritionix.com/culvers/landing`, which the existing embed check finds in
    the page HTML. **Doug: confirm the loader counts as the same widget as the grid.**
  - **publishedOn is the grid's "Last Updated: 10/16/2026".** The loader page is JS-only, so
    whether it prints the same date could not be seen. The data file's own `generatedAt`
    (2026-10-12) and Last-Modified are metadata and were not used.
  - The grid has a **"Test and LTOs (Preview Only)"** section (103 rows, e.g. Bacon Bleu Pub
    Burger); nothing was taken from it. The chart's note says test products and regional
    items are not on the website.
  - Salads: the widget's default build of each salad is grilled chicken, greens and toppings
    (Garden Fresco includes croutons), with no dressing; dressings are separate rows in
    "Sauces, Dressings & Condimentss". Serving text says "dressing listed separately".
  - ButterBurgers: the widget's default build is bun and patty (or patties) only, so the
    serving text says so; toppings are separate rows.
  - George's Chili, Medium includes saltine crackers in its default build.
  - White Milk's default build is "Milk, 1%", 227 g.
  - **Dropped for "< 1" in a carried column:** Original Chicken Tenders 4 Piece (sugar),
    Buffalo Chicken Tenders 1 and 4 Piece (fibre, sugar), Chicken Noodle Soup Medium,
    Side of Thick Cut Bacon. The 2-piece Original Tenders row is clean and is in.
  - No modifications: the Grilled Chicken Sandwich's build includes mayonnaise, but a
    "hold the mayo" saving would be a subtraction of a component row, not a published total.
  - Energy check: all ten within 3.2% (White Milk 106.5 vs 110).
  - The grid repeats ButterBurger Single and Original Tenders 2 Piece under Kids' Meals;
    the repeats agree.
- **Dunkin'.** dunkindonuts.com/nutrition/ answers a plain request (after two redirects
  from /en/menu/nutrition) and links the nutrition guide PDF and the allergy guide PDF,
  both on Dunkin's Contentful asset host. Read with PDFKit; every row re-read through the
  repo's `findPdfRow` and matched; every row was also confirmed against the rendered page
  image (pages 49 and 50).
  - **Pages 1-13 are "Limited Time Products"; page 14 starts "Permanent Products".**
    Nothing was taken from the LTO pages. That rules out the Bacon & Cheddar Omelet Bites
    (2 bites, 280 kcal, 17 g protein), every "Protein" latte/refresher (e.g. Protein Iced
    Latte Large, 230 kcal, 20 g), and Snackin' Bacon, which a lifter would otherwise want.
    The Egg White & Veggie bites are not on the chart at all.
  - **Regional sections avoided:** "Sandwiches - Regional" (the biscuit sandwiches and the
    Chicken Croissant Sandwich), "Donuts - Regional", "Kolache - Regional". On the page the
    section heading sits above its rows, but in PDFKit's text it comes *after* them -
    e.g. "Sandwiches - Regional" is extracted below the four biscuit rows. The images
    settled which rows are regional; the text alone would have misled. Spam Breakfast
    Sandwich and both turkey-sausage items are in the permanent "Sandwiches" block on p50.
  - **Split labels.** PDFKit emits several two-line labels with the second line elsewhere
    (e.g. "Muffin" comes out *before* "Bacon, Egg and Cheese on English"). Three locators
    therefore match the label fragment that sits directly before the figures; the note in
    locator.json says which. Like Burger King's "BeverageFat FREE Milk", pdftotext will
    almost certainly split these differently.
  - **Hot Latte with Skim Milk (Large)**: the row is "Hot Latte with Skim Milk - Large
    Large", the serving column printed inline, so the locator includes it. No volume is
    printed for "Large". 12 g protein, 18 g sugar (lactose; the chart's added sugars is 0).
  - **Turkey Sausage Wake Up Wrap** is spelled without the hyphen on the chart, unlike the
    other Wake-Up Wraps; the `name` uses the hyphen for consistency, the locator keeps the
    chart's spelling. **Doug: or keep the chart's spelling in `name`.**
  - Sourdough Breakfast Sandwich is 1,300 mg sodium.
  - Energy check: all eight within 3.9% (Turkey Sausage Wake Up Wrap 239 vs 230).
  - `kind` is `coffee`, the café/breakfast kind Starbucks and Panera use; its rule ("A
    protein box, egg bites or a wrap over a pastry, and the drink unsweetened") fits.
  - The file sits under a Contentful asset path that changes when the file is replaced
    (Sonic's position): each quarter, confirm dunkindonuts.com/nutrition/ still links it.
- **Jack in the Box.** jackinthebox.com/food/nutrition is a 404 (Next.js); the home page
  answers and its server-rendered page data carries `"nutritionUrl"` pointing at a PDF on
  the site's Sanity CMS asset host. That PDF is the chain's own nutrition chart. It is one
  18 x 24 in poster page.
  - **The PDF's extracted text is unusable for rows.** PDFKit emits the figures in blocks
    with no names and the names in separate blocks, often splitting one row's numbers across
    lines. So every item was **read by position from the rendered page** (PDFKit rendering,
    zoomed tiles), as QuikTrip's were, and locator.json is `manual`. As a second check, the
    run of figures for seven of the ten rows appears contiguously in the extracted text
    exactly as read; the other three (Teriyaki Bowl, both grilled-chicken salads) are split
    in the text and were confirmed on a second, closer render.
  - **`publishedOn` is left out, on purpose.** The document states "effective as of
    November 2026", which is after `checkedOn` (2026-10-28); the validator refuses a
    `publishedOn` later than `checkedOn`, and inventing an earlier date is worse.
    "2026 NUTRITION FACTS" is a year, not a month. **Doug: leave it out, or record
    `2026-11` once November arrives (the check would then also need to re-read the chart).**
  - **The Breakfast table looks misaligned, so nothing was taken from it.** Its "Meat Lovers
    Breakfast Burrito (no salsa)" row is identical to the Hash Brown row (64 g, 190 kcal,
    2 g protein), and "Extreme Sausage® Sandwich" reads 68 g / 260 kcal / 5 g protein, which
    cannot be that sandwich. With two rows evidently belonging to other labels, no row of
    that table can be trusted to its label. **Doug: worth reporting to the chain, and a
    reason to revisit breakfast when the chart is reissued.**
  - Salads: "Nutrition information does not include salad dressing or crunchy toppings";
    the serving text says so. Dressings, tortilla strips and croutons are their own rows.
  - Teriyaki Grilled Chicken Bowl is the white-rice row (a Brown Rice row is also printed:
    580 kcal, 29 g protein, 7 g fibre); it appears in both "Better for You" and "Chicken &
    More" with identical figures. 1,910 mg sodium, 26 g sugar.
  - Crispy Chicken Strips (3 pc.) excludes dipping sauces (separate rows). 1,760 mg sodium.
  - **Energy flag: Milk**, 110 kcal published against 102 by 4/4/9 (7% under the label
    figure). 214 g, 2 g fat; a footnote reads "*71% fat reduction compared to whole milk",
    but the Milk row carries no asterisk, so the serving text does not claim a fat level.
    Published figure kept. **Doug: keep or drop.**
  - Avoided: "Fish Sandwich (seasonal)". The chart says "limited time only items and some
    regional items are not included", so everything else on it is standing menu.
  - Jumbo Jack Cheeseburger's printed serving size is "38" g (clearly a typo for a 600 kcal
    burger); the serving column isn't carried and the item isn't in the file.
  - Energy check: the other nine within 3.8% (Southwest Salad 301 vs 290).
  - The PDF sits under a Sanity content hash, so a replacement appears at a new address:
    each quarter, confirm the home page's `nutritionUrl` still names this file.

## Chains left out

Re-tried on 2026-09-23, and the new candidates tried on 2026-10-28, with the same ground rules: the chain's own published
document, one plain request each, a User-Agent naming this work, no retries and
nothing worked around. Taco Bell and Sheetz came off this list on 2026-09-24,
when an embedded official calculator became an acceptable source; the other
four are still out for reasons the rule change does not touch.

| Chain | Why |
|---|---|
| McDonald's | Every mcdonalds.com path answers **HTTP 403** to a plain request - the nutrition calculator, the full menu, and the `/content/dam/.../nutrition` PDF paths alike. A WebFetch of the calculator is refused the same way. There is no US PDF on another host. Not bypassed. |
| Jersey Mike's | `subs.jerseymikes.com/nutrition/{product}/{size}` returns **per-ingredient rows only** - values like `136.539000` calories - and the page sums the default ingredients in the browser for its "Totals" footer. There is no published total to read; producing one means re-running the page's arithmetic. Left out under "don't sum components". **Doug:** still a policy call, not a data problem. |
| Wawa | Unchanged since 2026-09-23, and if anything worse: **`www.wawa.com/nutrition` now answers HTTP 403** to a plain request (an Incapsula challenge page, 961 bytes, re-checked 2026-10-28). The `/nutrition/lower-sodium` pages SOURCES.md recorded publish calories and sodium only, so nothing there could fill a required field anyway. Not bypassed. |
| Buc-ee's | buc-ees.com still publishes no nutrition at all: not a figure on the site. |
| Raising Cane's | https://www.raisingcanes.com/nutrition/ answers a plain request (curl, User-Agent naming this work) with **HTTP 403** and a Cloudflare-fronted error page: "Oops! There has been an error accessing the page ... this site is temporarily unavailable", with an error code and the requester's IP and geo. One WebFetch of the same page, the step that retrieved Panera's PDF, was refused the same way (**HTTP 403**). No nutrition document on another host was found, and the page itself was the only route to one. Not bypassed. Read on 2026-10-28. |
| Panda Express | https://www.pandaexpress.com/nutrition answers a plain request (curl, User-Agent naming this work) with **HTTP 403** and a DataDome bot-check page ("Please enable JS and disable any ad blocker", scripts from `captcha-delivery.com`) - a captcha, not the page. One WebFetch of the same page was refused the same way (**HTTP 403**). No nutrition PDF on another host is linked from anything that could be reached. Not bypassed. Read on 2026-10-28. |
| KFC | https://www.kfc.com/nutrition **sends no response** to a plain request: curl (User-Agent naming this work) fails with `HTTP/2 stream 1 was not closed cleanly: INTERNAL_ERROR` and no status code. One WebFetch of the same page timed out after 60 s with nothing returned. One plain request to the home page, https://www.kfc.com/, failed identically, so it is the whole site refusing, not that page. No KFC nutrition PDF or JSON on another host was found without the site. Not retried over HTTP/1.1 or with another client: that would be working around it. Read on 2026-10-28. |
| Dairy Queen | Every dairyqueen.com path answers **HTTP 403** from Cloudflare ("Sorry, you have been blocked") to a plain request - `/en-us/nutrition/` and the `/en-us/` home page alike. A WebFetch of `/en-us/nutrition/treats`, the chain's nutrition page, is refused the same way (403). No nutrition document on another host is linked from anything the chain serves that could be read. Not bypassed. |
| Waffle House | wafflehouse.com answers every plain request with a **Cloudflare JavaScript challenge** (HTTP 403, `cf-mitigated: challenge`, "Just a moment... Enable JavaScript and cookies to continue") - `/nutrition/` and the home page alike - and a WebFetch of the home page is refused the same way (403). Whether Waffle House publishes a nutrition chart at all could not be seen. Not bypassed. |
| Circle K | **circlek.com has no Circle K nutrition chart of its own.** `www.circlek.com/nutrition` answers **301 to `/us/holiday-station/nutrition`**, the page of Holiday Stationstores (Circle K's Midwest brand), which says it covers "food and beverages at Holiday and Circle K" but links only Holiday's documents: the quick reference is headed **"HOLIDAY STATIONSTORES NUTRITION INFORMATION May 2026"** and its sandwiches are "Holiday Turkey & Cheese Wedge" and the like. Nothing ties any row to a Circle K store outside Holiday's footprint. **And the documents that page links disagree with each other on the same items**: Chicken & Swiss Sandwich is 660 mg sodium in the quick reference and 810 mg in the "Sandwiches & Burrito Nutritional" PDF; Sausage Egg & Cheese Croissant 560 vs 500 kcal; Sausage Egg & Cheese Muffin 470 vs 430 kcal; Brunch Burger 640 vs 620 kcal. The quick reference's rows also drop cells (Calories From Fat is missing on some rows and present on others, and "Cheeseburger" has no serving), so its columns cannot be read by position. `/us/nutrition` and `/us/food` are 404. Not bypassed. |

### Held for Doug (curated 2026-10-28, not in the file)

Both were read under the ground rules and are ready to add, but each sits one
step further from the chain's own page than the rule has allowed so far. Their
entries, locators and notes are kept outside the repo until Doug decides.

- **Jimmy John's** (9 items, sandwiches, "Last Updated: 10/26/2026"). jimmyjohns.com
  is a JavaScript shell; the only place the chain names its nutrition is a
  footer link, inside its JS bundle, to `restaurant.nutritionix.com/jimmy-johns/landing`.
  That is a **link out** to the calculator, not one embedded in a page the chain
  serves, so the 2026-09-24 embedded-calculator rule does not plainly cover it;
  and checking it would need new code, because the bundle's name changes on
  every deploy. **Doug:** does a link the chain itself puts in its footer count?
- **Casey's** (9 items, gas-station-kitchen, "Updated 9/30/2026"). www.caseys.com
  answers with a Cloudflare challenge (403) for the home page, /nutrition and its
  own copy of the PDF; the figures were read from
  `store.caseys.com/media/cms/Nutrition-and-Ingredients.pdf`, which is Casey's own
  host and answered 200. What could not be seen is whether the nutrition page
  links that copy today, and a search summary claimed the www copy differs.
  **Doug:** is the chain's own second host enough, as Burger King's RBI host was?

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
| Greek yogurt | Oikos Triple Zero Mixed Berry (2778000, 2026-09); Oikos Plain Nonfat (2619049, 2023-08) |
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
