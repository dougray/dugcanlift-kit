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
