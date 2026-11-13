# Tech debt index

One line per item, context in the linked file. Product ideas live in `TODO.md`.

## Gates (P1)

## P2
- **[P2 conf:0.5] LidAwake.swift:61** — `resumeSleep` failure after a stop timeout is swallowed; the controller stays bound to the old, closed worker until relaunch (same via "Stay Open" after a timed-out Quit, LidAwake.swift:173) → docs/reviews/lidawake-fixes/round2.md, round5.md #finding-2
- **[P2 conf:0.5] Sources/LidAwakeCore/SleepWorker.swift:131** — a retried `stop()` after a transport failure waits for the exit but doesn't check whether the worker actually restored sleep → docs/reviews/lidawake-fixes/round2.md
- **[P2 conf:0.45] Sources/LidAwakeCore/Uninstaller.swift:43** — a second app instance during the admin prompt, or external sudoers tampering before `rules.uninstall()`, can leave sleep off → docs/reviews/lidawake-fixes/round2.md
- **[P2 conf:0.5] Sources/LidAwakeCore/Uninstaller.swift:60** — support-dir removal fails after the rules are removed: `.incomplete`, but the worker stays stopped until relaunch → docs/reviews/lidawake-fixes/round3.md #finding-2
- **[P2 conf:0.4] Sources/LidAwakeCore/Uninstaller.swift:57** — `try? attributesOfItem` treats any error as "absent"; uninstall reports success and leaves data behind → docs/reviews/lidawake-fixes/round3.md #finding-3
- **[P2 conf:0.4] Sources/LidAwakeCore/SleepControl.swift:156** — `releaseClaim` trusts `setAwake`'s first read; an external 1→0 flip before the probe's re-read clears the journal with sleep left disabled (stale read also skips the enable, :145) → docs/reviews/lidawake-fixes/round4.md #finding-1, round5.md #finding-1
- **[P2 conf:0.3] Sources/LidAwakeCore/SleepControl.swift:36** — registry fallback skipped when `pmset -g` shows `SleepDisabled` outside its line (a process of that name); the read throws (fails safe); same in the uninstall script, PrivilegeSetup.swift:97 → docs/reviews/release-1.3/step1.md
- **[P2 conf:0.5] Sources/LidAwakeCore/SleepControl.swift:215** — unchecking the last condition of the inactive power source turns the switch off with no sleep write; after a failed restore the Mac can stay awake while the switch reads off → docs/reviews/release-1.3/whole-round1.md, step2.md
- **[P2 conf:0.35] Sources/LidAwakeCore/SleepControl.swift:156** — `releaseClaim`: a failed re-read after the probe keeps `ownsOverride = true`, so the next reconcile skips the probe → docs/todos/release-claim-failed-reread.md

## Unprioritized
- **[conf:0.5] Sources/LidAwakeCore/SleepControl.swift:73** — when SleepDisabled is already 1 and not owned, `probeRule()` proves only `disablesleep 1`; a rule denying `0` still passes → docs/todos/probe-one-sided-rule-when-already-awake.md
- **lidawake-fixes review close-out** — 2 theoretical leftovers (uninstall abort variant, login-item rollback) → docs/todos/lidawake-fixes-close-out.md
- **release-1.3 review close-out** — 5 theoretical leftovers (delayed pmset apply, macOS 27 post-write read, lid-closed probe suspend, 65 s reply deadline, persist key order) → docs/todos/release-1.3-close-out.md
- **Release 1.3.0: notarize the direct DMG** — Developer ID signing, hardened runtime, notarize and staple in `release.sh`; needs a notary credential from the owner → docs/todos/notarize-direct-dmg.md
- **Release 1.3.0: String Catalog locales** — move the `L("en", "ru")` pairs in LidAwake.swift to `Localizable.xcstrings`; own arc → docs/todos/string-catalog-locales.md
- **Arc B review close-out** — 2 theoretical leftovers of "no timeout" (power changes not applied, Quit waits, while a password dialog is unanswered) → docs/todos/arc-b-close-out.md
- **`swift build` warns about unhandled root files** — Package.swift's exclude list lacks `CLAUDE.md` and `CLAUDE.local.md`; warning only → docs/todos/swiftpm-unhandled-files-warning.md
