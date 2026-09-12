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

Both apps point at a **local path**, `path: ../dugcanlift-kit`, not a tag or
a branch. That is deliberate, chosen 2026-09-12: editing shared code is
immediate, with no tag to cut and no version to bump in two places.

The trade is that nothing resolves anywhere else. A second machine, a fresh
clone, or CI cannot build either app unless this repo is checked out beside
it under exactly this name. Neither app has CI today, which is what makes
the trade worth taking.

**If that changes — CI, a second machine, or another person — switch both
apps to a pinned tag.** The relative path is the only thing holding them
together, and it is invisible until it fails.
