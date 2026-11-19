# Worker memory-leak fix: review close-out

Range `e4de2b8..96cccf6`, one-shot round 1: zero P0/P1/P2. Codex found nothing in the changed lines. Full output: `docs/reviews/worker-leak/round1.md`. One test gap and seven theoretical items in code this commit did not change. Four are already indexed (see the notes after the items).

- [test-gap conf:0.5] Tests/LidAwakeCoreTests/SleepControlTests.swift:465 — the test injects request strings and discards replies, so real stdin reads and stdout writes are not exercised. The leak was in the ProcessCommandRunner launch path, which the test does go through (38.5 MB before the fix, ~350 KB after).
- [conf:0.3] Sources/LidAwakeCore/SleepWorker.swift:48 — `readLine()` buffers a line of any length before the 1 KiB check. The only writer is the parent app, over a private pipe.
- [conf:0.3] Sources/LidAwakeCore/SleepWorker.swift:172 — nine serial 10 s commands could take longer than the client's 65 s reply deadline. Already indexed: release-1.3 close-out, "65 s reply deadline".
- [conf:0.3] Sources/LidAwakeCore/SleepWorker.swift:138 — a retried Quit counts any worker exit as restored, even after sudo is revoked. Already indexed: P2 `SleepWorker.swift:131`.
- [conf:0.3] Sources/LidAwakeCore/SleepWorker.swift:40 — a status read after a successful `stop()` can fail, so the reply reports a failed shutdown. The fix kept this behavior.
- [conf:0.2] Sources/LidAwakeCore/SleepControl.swift:156 — an external writer can race the probe's first read. Already indexed: P2 `SleepControl.swift:156`.
- [conf:0.2] Sources/LidAwakeCore/SleepControl.swift:80 — when sleep is already disabled, the probe never tests writing 0. This is deliberate (see the `probeRule` comment). Already indexed: `docs/todos/probe-one-sided-rule-when-already-awake.md`.
- [conf:0.2] Sources/LidAwakeCore/Commands.swift:38 — a worker killed during a command leaves its capture directory in the temporary directory.

Depends: nothing. Effort: small for each item.
