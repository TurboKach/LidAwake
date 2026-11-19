# Status reads from the registry: review close-out

Two codex rounds, both with zero P0/P1/P2. The owner deferred all leftovers on 2026-11-19 ("Defer all").
- Whole range `6fbe61f..85d3272`, round 1: 7 theoretical. Full output: `docs/reviews/lightweight-reads/whole-round1.md`.
- 1.3.1 bump `d8da8ef..dee2b71`: 10 theoretical. Six were handled before B1 landed: release from a clean worktree at the tag, B0 poll bound and restore, the `??` compile form, the soak warm-up, the macOS 27 post-write half settled by B1, and the 65 s deadline (repeated below). The four that still apply to the B1 design are listed. Full output: `docs/reviews/lightweight-reads/release-1.3.1-round1.md`.

B0 measured the risk these items depend on: on macOS 26.6.2 the registry showed the written value on the first read after `sudo pmset` returned (max 0.3 ms over 20 writes, no stale value in back-to-back 1→0 pairs). Every decision read stays on `pmset -g` by the owner's design choice.

Whole range, round 1:
- [conf:0.5] Sources/LidAwakeCore/SleepControl.swift:186 — on macOS 27 with the registry value missing and an enable delayed past 2 s, `settle` does nothing and the `pmset -g` path decides (the plan's accepted fallback).
- [conf:0.4] Sources/LidAwakeCore/SleepWorker.swift:130 — a Quit retry after a restore timeout, with `pmset -g` at 0 and the registry stuck at 1. Accepted lag trade-off; decisions read `pmset -g`.
- [conf:0.4] Sources/LidAwakeCore/SleepControl.swift:169 — an enable with `pmset -g` at 1 and the registry stuck at 0. Reconcile reads `pmset -g`.
- [conf:0.3] Sources/LidAwakeCore/SleepControl.swift:110 — `try?` ends the settle loop on one failed registry sample. `write()` still checks `read() == awake` through `pmset -g`; at worst it acts as the old code did.
- [conf:0.3] Sources/LidAwakeCore/SleepWorker.swift:172 — the 65 s reply deadline overflows only if 8 commands each run near their timeout and both settles stall. Settle adds at most ~2.4 s.
- [conf:0.2] LidAwake.swift:232 — the lid state is sampled before `perform`, as before this change. The race predates the commit.
- [conf:0.3] Sources/LidAwakeCore/SleepControl.swift:109 — settle uses wall-clock `Date()`. A clock jump during the 2 s window ends it early (the write then fails safe) or makes it late. A monotonic clock is the cheap hardening.

1.3.1 bump round, still applying to B1:
- [conf:0.3] Sources/LidAwakeCore/SleepControl.swift:156 — if the probe's final `sudo 0` throws, settle never runs, and `releaseClaim` decides from `pmset -g`.
- [conf:0.3] Sources/LidAwakeCore/SleepControl.swift:162 — settle covers writes only. A `stop()` after a timed-out enable decides from `pmset -g`.
- [conf:0.3] docs/prompts/lightweight-reads-plan.md:66 — a transient registry error skips settle. The decision reads stay on `pmset -g`.
- [conf:0.3] LidAwake.swift:232 — a registry-first status on a lid-close tick could skip `displaysleepnow` while the registry lags.

Fix, if ever wanted: a monotonic clock in `settle` is a few lines. The rest needs a registry that lags or fails, which B0 did not observe. Re-measure B0 on a new macOS before acting.

Depends: nothing. Effort: small (clock), otherwise only after a measured lag.
