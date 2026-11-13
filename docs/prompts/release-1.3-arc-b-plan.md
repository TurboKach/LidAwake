# Arc B — the password dialog names LidAwake

Repo `~/Dev/LidAwake`, branch `release-1.3`. Whole-range review base: `7b8deaf` (head of the last clean gate). Feature base: the commit that adds this plan as `docs/prompts/release-1.3-arc-b-plan.md`.

## Context
The admin password dialog shows LidAwake's own sentence since `24641f5`, but its bold title is "osascript", because `PrivilegeSetup.install()` and `uninstall()` start `/usr/bin/osascript` as a child process and macOS names the asking process. The owner approved the direction: run the script inside the app.

Evidence (2026-11-13, owner's Mac, macOS 26): a throwaway probe app ran `do shell script … with prompt … with administrator privileges` through `NSAppleScript` in its own process. The owner saw the title "LidAwake Probe". The script ran from a serial background queue and from the main thread, with the same dialog. A cancel returned error number -128. The run with a real password was not tried in the probe.

Outcome: Sleep Setup, Repair Sleep Setup and uninstall show a dialog titled "LidAwake". Nothing else changes for the user, except the text of a script failure (below).

## Design
- **Seam.** A new protocol in `Sources/LidAwakeCore/Commands.swift`, next to `CommandRunning` and `appleScriptString`:
  `protocol AppleScriptRunning { func run(_ source: String) throws -> String }` — runs one AppleScript source text in the current process and returns the result as text.
- **Production conformer** `InProcessAppleScriptRunner` (same file): a new `NSAppleScript(source:)` per call, `executeAndReturnError`. The result is read as an optional (the Swift annotation is wrong; Apple DTS notes this). Mapping:
  - error number `-128` → `ControlError.canceled`;
  - any other error → `ControlError.message(<NSAppleScript.errorMessage, trimmed>)`, or `"The admin script failed (<number>)."` when the message is empty;
  - success → `stringValue ?? ""`.
- **`PrivilegeSetup`** keeps its `runner:` label; the type changes from `CommandRunning` to `AppleScriptRunning`. `install()` and `uninstall()` build the same source text as today (`do shell script <appleScriptString(script)><promptClause> with administrator privileges`) and pass it to `runner.run(source)`. All later checks stay: `isInstalled`, the `kept-legacy` output, `remainingRules`.
- **Thread.** The call stays on the app's serial work queue (`perform { }`, `LidAwake.swift:182-215`). No change in `perform`, in the handlers or in their `pendingUserOperations == 0` guards.
- **`LoginItems` and `CommandRunning` stay as they are.** `ProcessCommandRunner` keeps its `(-128)` cancel mapping; `LoginItems` still uses it.

Invariant of the new mechanism: one script call ends only when the user answers the dialog (or macOS closes it), and it holds the serial work queue for that time. Bound: there is no timeout. Today osascript is killed after 120 s; an in-process script cannot be killed, and a watchdog could only abandon a blocked thread. While the dialog is open, other work on the queue waits, as it does today for up to 120 s. The user handlers refuse a second operation (`pendingUserOperations`). Two consequences have no end now, where today they end at 120 s:
- **Power-source changes are not applied.** `perform` drops polls while `busy` (`LidAwake.swift:187`), and Setup/Repair can run with keep-awake on (`LidAwake.swift:368-371`). A Mac that is unplugged while the dialog stays open keeps sleep disabled until the dialog is answered.
- **Quit waits.** `restoreSleepThenReply` queues `controller.stop()` on the same queue (`LidAwake.swift:158-162`) after the app returned `.terminateLater`.
Not known: whether macOS closes an unanswered password dialog by itself.

User-visible change in errors: a failing script's message is now the script's own text (for example the refusal line the shell script prints), without the `0:123: execution error: … (1)` frame that osascript adds. "osascript timed out." can no longer occur.

## Steps
Parallel: none — Step 2 is short and needs Step 1's code.

### Step 1 — the in-process runner and its use (`step-executor`, Sonnet)
Files: `Sources/LidAwakeCore/Commands.swift`, `Sources/LidAwakeCore/PrivilegeSetup.swift`, `Sources/LidAwakeCore/SleepWorker.swift`, `LidAwake.swift`, `Tests/LidAwakeCoreTests/SystemAdaptersTests.swift`, `Tests/LidAwakeCoreTests/UninstallerTests.swift` (the `:60` assertion).

Call sites of the changed `PrivilegeSetup.init(runner:)` — see "Call sites" below (filled from the explorer report).

Work:
1. Add `AppleScriptRunning` and `InProcessAppleScriptRunner` as designed.
2. Change `PrivilegeSetup` to the new seam; remove the `timeout: 120` arguments with the calls.
3. Production sites pass `InProcessAppleScriptRunner()`: the app's `AppRuntime.setup` and the worker.
4. Tests: `RecordingRunner` also conforms to `AppleScriptRunning` and records the source text. The two tests that pin `"/usr/bin/osascript"` and `["-e", …]` assert the recorded source text instead (same strings, without the path and `-e`).
5. New tests of `InProcessAppleScriptRunner` with scripts that need no password (safe: no dialog):
   - `do shell script "echo hi"` returns `hi`;
   - `do shell script "echo refused >&2; exit 3"` throws `.message` that contains `refused`;
   - `error number -128` throws `.canceled`;
   - the same three from a background serial queue.
   These run real `NSAppleScript` inside the `xctest` process, here and on the GitHub runner (CI runs `swift test`). If they fail under `xctest` on this Mac, the executor stops and reports; it does not delete or skip them. CI shows its result only after the push; a CI-only failure is fixed then with an opt-out for CI, with the owner's word.

Acceptance: `swift build` passes; `swift test` shows 0 failed with the executed/skipped counts; no test or source in the `PrivilegeSetup` path names `/usr/bin/osascript`; `LoginItems.swift` and `ProcessCommandRunner` have no diff. Never run the app, `pmset`, or a script with `with administrator privileges`.

### Step 2 — docs and the release build (`step-executor`, Sonnet)
Files: `docs/testing.md`, `docs/prompts/release-1.3-notes-draft.md`.
1. `docs/testing.md`, manual check 1 (`:27-28`, the one sentence about the password dialog): it also says the bold title is "LidAwake" and that the dialog opens in front. Add one line for the same check on uninstall (the file has none today).
2. Notes draft: remove the "still titled osascript" sentence; say the dialog names LidAwake.
3. Full verification: `swift test`, `LIDAWAKE_REAL_REGISTRY_TEST=1 swift test --filter testRegistryRead`, `scripts/test-recovery.sh`, `scripts/build-app.sh universal`, `scripts/check-build.sh universal`.

Acceptance: all five commands pass, with counts shown.

### Step 3 — the owner's device pass (master gate, AskUserQuestion)
The owner installs the build (`./build.sh` in their own Terminal; quit LidAwake first) and checks, with a real password:
- Repair Sleep Setup: the dialog title is "LidAwake", the sentence is LidAwake's, the setup is repaired.
- The same dialog, cancelled: no error box, nothing changed.
- Uninstall, cancelled: "Uninstall was canceled. Nothing was removed."
- Uninstall, with the password: the rules and the app are removed. Then install again with `./build.sh`.
- First-time Sleep Setup after that reinstall (the first-launch offer, `LidAwake.swift:141`, opens with no menu click): the dialog title is "LidAwake" and the setup works.
- In every case the dialog opens in front of other windows. `promptSetup` and `uninstallApp` do not activate the app; if the dialog opens behind, that is a finding for a fix step.
The whole-range codex challenge and the spec check run during this pass. A fix after the pass starts a new round.

### Close-out (master, docs only)
Delete the `docs/tech-debt.md` line and `docs/todos/admin-dialog-title.md`; tick Arc B in `docs/prompts/release-1.3-next-session.md` and record the arc, the review range and the note for Arc D; write the brief for Arc C.

## Call sites
`PrivilegeSetup(runner:)` is built in 28 places (2 production, 26 in tests; plan-reviewer count). `Tests/RecoveryProcess/main.swift` builds none, but `scripts/test-recovery.sh:8` compiles every `Sources/LidAwakeCore/*.swift` with bare `swiftc`: the new runner uses `Foundation` only (`NSAppleScript` is in Foundation) and adds no import.
- Production, both pass a `ProcessCommandRunner` today and change to `InProcessAppleScriptRunner()`:
  - `LidAwake.swift:29` (`runner` from `:27`, which stays for `LoginItems` and `pmset`);
  - `Sources/LidAwakeCore/SleepWorker.swift:26` (the local `runner` from `:25` stays for `PMSet`, which calls only `setup.isInstalled`, `SleepControl.swift:64`). The only callers of `install()` and `uninstall()` are `LidAwake.swift:369` and `Uninstaller.swift:49`.
- Tests, all pass a `RecordingRunner` and keep their text once `RecordingRunner` conforms to both protocols:
  - `UninstallerTests.swift:28`;
  - `SystemAdaptersTests.swift:35, 46, 56, 71, 98, 133, 178, 186, 239` (the same `runner` also goes to `PMSet`), `:262, 263, 266`, and inline at `:190, 201, 214, 227, 288, 311, 376, 383, 393, 402, 410, 417, 429`.
  - `SystemAdaptersTests.swift:438, 449, 463, 477` are not `PrivilegeSetup` sites (they test `ProcessCommandRunner` and `LoginItems`) and need no edit.
- Uses of the stored `runner` in `PrivilegeSetup.swift`: `:7` (property), `:13`, `:15` (init), `:44` (`install()`), `:61` (`uninstall()`). No other.

`RecordingRunner` (`SystemAdaptersTests.swift:5-12`) rules:
- The in-process call records its source text in a new `scripts: [String]` array, not in `calls`, and returns `try respond([source]).stdout` (`CommandOutput.stdout`, `Commands.swift:17`), so the `UninstallerTests` hooks (`:66, 85, 98, 111, 122, 133`; `:66` throws `.canceled`) keep their meaning. The argument is `[source]`, never an empty array (`SystemAdaptersTests.swift:84` uses `args.last!`).
- `UninstallerTests.swift:60` ("No admin prompt", `runner.calls.isEmpty`) must also assert `runner.scripts.isEmpty`; without it the test no longer covers the admin prompt.
- `SystemAdaptersTests.swift:255-258`: one script recorded, equal to `do shell script <appleScriptString(setup.uninstallationScript)> with administrator privileges`, and no `calls` entry for osascript.
- `testAdminPromptsAreAddedToTheScriptLinesAndEscaped` (`:260-285`): the same expected strings, compared with `scripts`.

## Edge cases
- Cancel: `.canceled`, no file touched; the uninstaller judges the result from the disk as today.
- Wrong password three times: macOS returns an error with its own message; it is shown as `.message`.
- The uninstall script prints `kept-legacy`: `do shell script` returns stdout without the final newline; the existing trim and compare stay.
- Prompts with quotes or newlines: the existing `appleScriptString` escaping and its test stay.
- The app is an `LSUIElement` app and the two flows do not call `NSApp.activate`; whether the dialog opens in front is checked in Step 3.
- Not seen by anyone: the dialog on macOS 12–15 and 27; the icon of the dialog (not reported from the probe).
- Arc D: with the hardened runtime, check that the in-process `do shell script` still works; no Apple event to another app is sent by it.

## Decisions
1. **The wait while the dialog is open — decided by the owner, 2026-11-13: "No timeout (Recommended)".** The two consequences in the invariant are accepted. The rejected option was to run the script off the work queue so the power policy and Quit continue (a restructure of `perform`, a larger arc).
2. **Thread of the script (assumption, the simplest option):** the work queue, as today. The owner's probe passed there and on the main thread; the main thread would freeze the app while the dialog is open and gives nothing more.
3. **Fallback error text (assumption)** when macOS gives no message: `"The admin script failed (<number>)."` (English only, like Core's other error texts; Arc C owns that scope point).

## Verification
Unit: Step 1's tests. Build: Step 2. The real flow: Step 3, by the owner — the agent must never trigger a password dialog, so this path cannot be exercised by the agent.
