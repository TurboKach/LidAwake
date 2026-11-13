# release-1.3 review close-out

Theoretical leftovers from the release-1.3 reviews that have no index line of their own. Each names its source file under docs/reviews/release-1.3/.

- [theoretical] Sources/LidAwakeCore/SleepControl.swift:162 — a delayed `pmset` apply after `stop()`: `pmset` applies a write asynchronously, so `stop()` can read `false` while a pending `1` is still to land; it then skips the restore and clears the journal. Source: step1.md. (Codex rated it P1; triage judged it theoretical.)
- [theoretical] Sources/LidAwakeCore/SleepControl.swift:95 and Sources/LidAwakeCore/PrivilegeSetup.swift:104 — on the macOS 27 registry fallback, the post-write check can read the previous registry value and reject a successful write. Source: step1.md.
- [theoretical] Sources/LidAwakeCore/SleepControl.swift:85 — a lid-closed suspend during the 0 -> 1 -> 0 rule probe: the intermediate restore can put the Mac to sleep before enable completes. Source: step4.md.
- [theoretical] Sources/LidAwakeCore/SleepWorker.swift:166 — the 65 s worker reply deadline is shorter than the nine sequential commands of the enable path at 8 s each. Source: step4.md.
- [theoretical] LidAwake.swift:45 — `persist` writes the three settings keys one after another; a crash after `lidAwakeEnabled=true` and before the condition keys leaves (ON, none), which startup normalization turns OFF. Source: whole-round1.md.

Note: step4.md also repeated the one-sided-rule point (`probeRule` when SleepDisabled is already 1). It already has its own index line: docs/todos/probe-one-sided-rule-when-already-awake.md.
