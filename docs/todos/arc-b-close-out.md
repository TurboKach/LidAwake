# Arc B review close-out

Range `7b8deaf..2f880d8`, whole-range round 1: zero P0/P1. Full output: `docs/reviews/release-1.3/arc-b-whole-round1.md`. Two theoretical leftovers, both the accepted effects of the owner's decision of 2026-11-13, "No timeout" (`docs/prompts/release-1.3-arc-b-plan.md`, "Design" invariant and "Decisions" 1).

Why they exist: the admin script now runs inside the app through `NSAppleScript` (`InProcessAppleScriptRunner`, `Sources/LidAwakeCore/Commands.swift`), so the password dialog is titled "LidAwake". An in-process script cannot be killed; the old 120 s osascript timeout is gone. The script holds the app's serial work queue until the user answers the dialog.

- [conf:0.9] LidAwake.swift:188 — unanswered admin dialog keeps `busy` true, so power-source (AC to battery) changes are not applied.
- [conf:0.9] LidAwake.swift:161 — Quit during an unanswered dialog waits behind the script, so `.terminateLater` does not finish.

The same claim was the one finding of the per-step round on `5b2b6c8..df0d606` (`Sources/LidAwakeCore/Commands.swift:97`, theoretical).

Fix, if it is ever wanted: run the script off the work queue so the power policy and Quit continue. That restructures `perform` and its `busy` state and needs a rule for Quit while a root script may run. The owner declined it for 1.3.0. Not known: whether macOS closes an unanswered password dialog by itself.

Depends: nothing. Effort: medium, own arc.
