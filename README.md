# LiftKit

Shared Swift code for the DUGCANLIFT apps. Two products:

- **`LiftCore`** — domain models, wire codecs, theme, day keys. No SQLite
  dependency, so the LIFT widget extension can link it.
- **`LiftReference`** — the USDA and exercise reference databases, and the
  GRDB layer over them. Apps only; a widget never opens SQLite.

Consumed by [`lift-ios`](https://github.com/dougray/dugcanlift-lift-ios) and
[`coach-ios`](https://github.com/dougray/dugcanlift-coach-ios). Both pin a
tag rather than tracking a branch: a change here reaches two shipped apps.
