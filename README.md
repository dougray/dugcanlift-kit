# LiftKit

Shared Swift code for the DUGCANLIFT apps. Two products:

- **`LiftCore`** — domain models, wire codecs, theme, day keys. No SQLite
  dependency, so the LIFT widget extension can link it.
- **`LiftReference`** — the USDA and exercise reference databases, and the
  GRDB layer over them. Apps only; a widget never opens SQLite.

Consumed by [`lift-ios`](https://github.com/dougray/dugcanlift-lift-ios) and
[`coach-ios`](https://github.com/dougray/dugcanlift-coach-ios). Both pin a
tag rather than tracking a branch: a change here reaches two shipped apps.

## How the apps consume this

Both apps pin an **exact tag** — `url:` plus `exactVersion:` in their
`project.yml` — not a range and not a branch.

This replaced a local `path: ../dugcanlift-kit` dependency on 2026-09-12.
The path made editing shared code immediate, but nothing resolved anywhere
else: a fresh clone of either app could not build at all unless this repo
happened to sit beside it under exactly this name. That was verified broken
and then verified fixed, by cloning `coach-ios` into an empty directory with
no sibling package and building it.

**Exact, not a range, because a change here reaches two shipped apps at
once** — and `@Model` types are shared, so a property change here is a
schema change for both, against stores holding real data. Upgrading is a
deliberate one-line edit, never something that happens on a
`swift package update`.

Cutting a release: merge to `main`, then tag and push the tag to both
`origin` and `behemoth`. Bump the two apps in separate PRs.

## Changelog

### 1.13.0 — readable rust tint

- `.liftScreen()` now applies `.tint(Theme.accentText)` instead of `.tint(Theme.accent)`. Visible change: tinted controls and plain text buttons/links inside a lift screen use the lighter rust in dark mode (`E0674D`, 5.09:1 on `background`, 4.69:1 on `surface`; was `C1442C` at 3.39:1 / 3.12:1). Under Increase Contrast they pick up `accentText`'s `962F1B` / `EE8A70`. Light mode is unchanged: `accentText` light is `B23C25`, the same as `accent`.
- Rule, now applied everywhere in the kit: rust as TEXT or a tint is `accentText`; rust as a FILL (chip and button backgrounds, progress bars, the tab underline, the route line) stays `accent`. Every other rust use in the kit already followed it.
- Internal `Theme.screenTint` (= `accentText`) names the tint; `ThemeTests.testScreenTintIsTheReadableRust` pins it.

### 1.12.0 — accessibility, rust text and palette parity

Fixes from the 2026-10-08 Impeccable audit. Android's `liftcore` 1.7.0 has the matching palette and display changes.

**Colour**

- `Theme.accentText` added: light `B23C25` (same as `accent`), dark `E0674D`. Use it for rust TEXT. Dark `accent` (`C1442C`) was 3.39:1 on `background` and 3.12:1 on `surface`; `E0674D` is 5.09:1 and 4.69:1. `accent` is unchanged and is now for fills only (chips, buttons, progress, the tab rule). `LiftCard` titles, `MacroProgressRow` values and the selected `LiftTabButton` label use it.
- Selected `LiftChip` label is `onAccent`, not `textPrimary` (was 2.68:1 light, 4.13:1 dark; now 5.67:1 and 4.53:1).
- Increase Contrast: `Color(light:dark:)` gains optional `lightHighContrast:` / `darkHighContrast:` parameters (source-compatible). `hairline` and `cardBorder` go to `857B6C` / `777065` (3:1 or better), `textSecondary` to `4E473D` / `C9C2B5`, `accentText` to `962F1B` / `EE8A70`. In dark, `cardBorder` becomes visible under Increase Contrast.
- `Tests/LiftCoreTests/Fixtures/palette.json` is the canonical token list. `ThemeTests` checks every token against it, checks that every `textPairs` entry is 4.5:1 or better in both appearances, and compares it byte for byte with the Android kit's copy when that checkout sits beside this one.

**Type**

- All five type tokens are Dynamic Type text styles: `cardTitle` = headline bold, `figure` = title bold, `body` = callout, `detail` = subheadline, `sectionLabel` = subheadline bold. At the default size two change: `detail` 14 → 15pt and `figure` 26 → 28pt. The rest keep their point size.
- `Theme.control` added (subheadline semibold), used by chips, tabs and buttons, which had inline fixed sizes.
- `MacroProgressRow` and `StatRow` stack the value under the label when one line does not fit (accessibility sizes).

**Components**

- `LiftChip` and `LiftTabButton` expose `.isSelected` to VoiceOver. `LiftTabBar` is announced as a tab bar. Tabs support the Large Content Viewer.
- `LiftCard` titles carry `.isHeader`, so they appear in the Headings rotor.
- `MacroProgressRow` is one VoiceOver element ("Protein, 120 of 200 g"), and `StatRow` is combined. `MacroProgressRow` no longer traps on NaN, infinite or huge values.
- `LiftChip` hit area is at least 44pt (the visible chip is unchanged). `LiftButton` is at least 44pt.
- `LiftChip` and `LiftButton` are `ButtonStyle`s: they dim when pressed, and when disabled the filled variants use `accentMuted` with a `textPrimary` label.

**Fixes**

- `RecipeIngredient.displayText` no longer crashes on a quantity past `Int.max` ("99999999999999999999 g oats" now reads "1e+20 g oats"). It now uses `CookFormat.trimmed` rather than an unguarded private copy, and a quantity that overflows to infinity shows the raw line.

**No schema change.** Nothing here is a `@Model` property.

### 1.11.0 — routes with no map

A route drawn with no tile server, so no tile server learns where the route is. `RouteProjection` is a port of Coach web's `coach/route.js` `project()`, checked point for point against `Tests/LiftCoreTests/Fixtures/route-projection-expected.json`, which route.js wrote (`scripts/make-route-projection-fixture.mjs`) and which is never regenerated from Swift. `RouteCanvas` renders the projected line; a guard in the Canvas closure handles zero-sized layout passes. `NoNetworkTests` fails the build if LiftCore or LiftReference makes a request.

**API added**

- `RouteProjection.project(_:width:height:) -> [CGPoint]` — projects
  `[OutdoorShareCoordinate]` to screen space, centred and scaled to fit
  inside 10% padding.
- `RouteProjection.minimumSpanDegrees: Double = 0.0001` — the span below
  which the projection treats coordinates as identical.
- `RouteCanvas(points:aspectRatio:) -> View` — draws a route in the accent
  colour with a start dot in the secondary accent and an end dot in the full
  accent, or shows "Waiting for GPS…" under two points. Reads as "Route" to
  VoiceOver; while waiting it reads "Waiting for GPS…".
- `RouteCanvas.waitingText: String = "Waiting for GPS…"` — pinned to
  LIFT Android's `RoutePolylineCanvas`.
- `RouteCanvas.accessibilityName: String = "Route"` — also pinned to
  Android.

**No schema change.** Nothing here is a `@Model`.

### 1.10.0 — per-side prescriptions

A coach's plan can say an exercise is done each side, and that a set is for
one side only (PLAN-FORMAT.md "Sides"). Additive, `v` stays `1`.

**API added**

- `PlanWorkoutExercise.b: Int?` — `1` is each side; a trailing `b: Int? = nil`
  init parameter, and `isEachSide`. Omitted from the JSON when nil. Decoding is
  lenient: `b` that is not a number reads as nil and the plan still opens.
- `PlanSetFlags` — the sixth set-tuple position. `sideBits(of:)` masks bits
  1-2 (`1` left, `2` right, nil for both, and for `3`, a missing or a
  non-integral value); `flags(sideBits:)` is what a sided set writes (`2`, `4`).
  Integers rather than a side type, because each app has its own `SetSide`.

**No schema change.** Nothing here is a `@Model`: `Routine`,
`RoutineExercise` and `RoutinePrescribedSet` are untouched, so neither app
needs a schema version for this release. Where each app keeps a prescribed
side is its own business (see each app's `CLAUDE.md`).

The set tuple itself (`[[Double?]]`) already carried a sixth number: 1.9.0 and
earlier decode a plan with sides unchanged, as two-sided sets. `PlanSidesTests`
reads `Fixtures/web-plan-per-side.txt`, a link Coach web's own encoder wrote.

### 1.9.0 — saturated fat, sugar and sodium

Tracked and shown, never targeted, and sent to coaches. Wire rules are
SHARE-FORMAT.md and PLAN-FORMAT.md, "Saturated fat, sugar and sodium"; names
and rounding match LIFT Android's kit.

**API added**

- `NutritionFacts.saturatedFatG: Double?`, and a trailing
  `saturatedFatG: Double? = nil` init parameter. `+` and `scaled(by:)` carry it
  like sugar and sodium: nil + nil stays nil, known + nil is the known value.
- `WireNutrientDetails` — `[saturatedFatG, sugarG, sodiumMg]` per serving,
  trailing nulls trimmed on encode. `init(_: NutritionFacts)`, `isEmpty`.
- `WireNutrientTotals` — a day's `fx`, seven positions, explicit nulls.
- `WireDay.fx: WireNutrientTotals?` and `WireDay.fe: [WireNutrientDetails?]?`,
  as trailing `= nil` init parameters. A malformed `fx` or `fe` decodes as nil
  and the day keeps its food; a malformed `fe` entry is nil on its own; an `fe`
  whose length differs from `f` is dropped whole.
- `PlanRecipe.ux: WireNutrientDetails?`, trailing `= nil`. Malformed or
  all-null decodes as nil and the recipe stays.
- `ShareNutrients.dayTotals(_:)`, `itemRow(_:)`, `itemRow(perServing:)`,
  `items(_:)`, `roundGrams(_:)`, `roundMilligrams(_:)` — grams to one decimal
  and sodium to whole mg, half-up (`floor(x + 0.5)`), totals summed unrounded.
- `NutritionFacts.merging(_: WireNutrientDetails?)` for the receiving side.
- `FoodRecord.saturatedFatPer100g: Double?`, from USDA nutrient 1258, and
  `nutrition(grams:)` fills `saturatedFatG`. `food.db` gains the column: 7,528
  of 7,928 foods have a value; the other 400 are nil, never zero. Every other
  row, id, rowid and value is identical to 1.8.0's file.
- `RecipeJSONLD` reads `saturatedFatContent`. Its sodium unit is now read as a
  word: `mg`/`milligram(s)` is mg, else `g`/`gram(s)` is grams × 1000, else mg.
  The old substring check read "320 milligrams" as 320,000 mg.

**Schema consequence — read before bumping an app**

SwiftData does not store `NutritionFacts` as a blob. It flattens it into one
column per field on the owning entity (`ZSUGARG`, `ZSODIUMMG`, …, and
`ZSUGARG1`, … for a second `NutritionFacts` property on the same model), so
`saturatedFatG` is a new column on `FoodEntry`, `Recipe` and `PlannedMeal`
(two on `PlannedMeal`), and it changes each entity's version hash. All of this
was measured against real on-disk stores with SwiftData on macOS 26, not
inferred:

- **Coach iOS: no schema version needed.** It opens its container with no
  migration plan, and SwiftData's inferred lightweight migration adds the
  nullable columns; existing recipes and planned meals keep every value and
  read `saturatedFatG` as nil. Worth confirming by installing over a real store,
  as the outdoor change was.
- **LIFT iOS: needs `LiftSchemaV7` in the same PR as the bump, or every
  existing install fails to open its store on launch.** Every version in
  `LiftSchemaVersions.swift`, frozen shapes included, references the live
  `NutritionFacts`, so after the bump none of V1–V6 matches the checksum of the
  store V6 wrote, and staged migration refuses it: *Cannot use staged migration
  with an unknown model version* (`NSCocoaErrorDomain` 134504). Reproduced.
  The fix that was verified: freeze a copy of the seven-field `NutritionFacts`
  (nested in an enum; its type name does not enter the checksum), point every
  model V1–V6 lists that holds one at a frozen shape using it — which means
  freezing `FoodEntry`, `Recipe`, `RecipeIngredient` and `PlannedMeal` as they
  stood in V5/V6 too, since those versions list the live classes — add V7 with
  the live classes and a lightweight `v6ToV7`. The comment above
  `LiftPreGramServingShapes` predicted exactly this.
