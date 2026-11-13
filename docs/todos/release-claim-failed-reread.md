# releaseClaim: a failed re-read skips the probe on the next reconcile

What: in `Sources/LidAwakeCore/SleepControl.swift`, `releaseClaim(startedAwake:)` (the `!startedAwake` branch) keeps `ownsOverride = true` when `settings.read()` after a rejected probe fails or does not return `false`. The next `setAwake(true)` then sees `ownsOverride` and skips the `requireAutomaticControl()` probe, so the rule is not re-proven.

Why: keeping ownership after a failed re-read is correct by design (docs/reviews/lidawake-fixes/round4.md: from a 0 start the probe may have left sleep disabled, so restoring that is owed; a journal that says "owned" makes the next stop or relaunch restore it). The open point is only the skipped probe: after the rejected probe, the same bad rule can let the next reconcile write `1` with no proof that `0` is allowed.

Context: not found in the release-1.3 review rounds; found while reading the round4 verdict against the code at release-1.3.

Depends: nothing. Related index line: the `releaseClaim` stale-read item (docs/reviews/lidawake-fixes/round4.md #finding-1).

Effort: small. Idea: keep the ownership flag but add a separate "probe pending" flag that the next `setAwake(true)` honors.
