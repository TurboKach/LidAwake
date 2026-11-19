# Plan: 1.3.1 (leak fix) + routine sleep-state reads without process launches

## Context

The 1.3.0 `--sleep-worker` leaked ~130 KB per request (22.3 GiB after 3 d 16 h). The cause was autoreleased Foundation objects on a thread with no run loop. Fixed in `96cccf6` (an autorelease pool per request, with a red-then-green test). Review clean: `docs/reviews/worker-leak/round1.md`. The 35-min soak of the installed build passed: 6.2 → 7.6 MB in warm-up, then 7.6–7.8 MB, with live heap nodes flat at 4,033–4,034 from 15 min to 35 min.

The owner then asked for "robust and lightweight". The decisions on 2026-11-19 were:
- 1.3.1 ships the leak fix alone.
- Then items 1–3 of the advice: (1) a release soak step, (2) the reply reuses the read, (3) routine reads through IORegistry, with `pmset -g` only for verifying writes and for the probe.

Measured today: every tick (2 s timer, power notification, menu open, user action) sends a `set` and a `status` request, and that is 3 `pmset -g` launches. With keep-awake ON and the lid closed, it is 4 launches plus `pmset displaysleepnow` while a display is awake. In 6 minutes the worker used 1.6 s of CPU, without counting its children.

Goal: a tick launches **1 `pmset -g`** instead of 3–4. The one left is the `pmset -g` decision read, which stays because the registry can lag after a write. Writes and the permission probe launch as before. The recovery design (worker + journal + session lock) does not change.

## Track A: release 1.3.1 (the leak fix alone), on `main`

A1. **step-executor** (Sonnet): `Info.plist:10-11` 1.3.0 → 1.3.1 and build 10 → 11, one commit "Release 1.3.1: worker memory-leak fix". Nothing else changes. Acceptance: `./build.sh --no-install` passes. `/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' -c 'Print CFBundleVersion' LidAwake.app/Contents/Info.plist` prints `1.3.1` and `11`.

A2. Master, verification only: a one-shot codex round on `d8da8ef..<A1>` (background) + `codex-triage`. Then `swift test` (counts shown) and `./scripts/test-recovery.sh`. Then the worker-related checks from `docs/testing.md`, "Manual checks before publishing", that the master can drive: item 4 (Quit restores `SleepDisabled` 0; force-quit only the GUI PID, the worker restores and exits). The soak result (35 min, flat) is already shown.

A3. Ship steps, **each with the owner's approval in the session** (as in `docs/prompts/release-1.3-plan.md:118-126`):
1. Scan `origin/main..main` for private names. Then push `main`.
2. Tag `v1.3.1` and run `./release.sh`.
3. `shasum -a 256 LidAwake.dmg > SHA256SUMS.txt`.
4. `gh release create` with both assets and release notes that the owner approved (draft shown first). The notes say plainly that 1.3.1 is still not notarized, because `docs/todos/notarize-direct-dmg.md:7` says the 1.3.0 notes promised it.
5. Post-release checks:
   - `releases/latest` returns the `html_url` form that `GitHubUpdates.swift:62-63` expects.
   - The downloaded DMG matches `SHA256SUMS.txt`.
   - The installed build (1.3.0 version string) offers the update.
6. Install 1.3.1 from the released DMG. This is the B3.1 baseline.

## Track B: lightweight reads, on branch `lightweight-reads` from `main` after A1

**Feature base** = `main` HEAD when the branch is created, after A1 and any A2 fix. Recorded then.

### B0. Master, verification only: measure the registry lag (go/no-go before B1)

`pmset.m` hands `disablesleep` to configd ("PM configd picks them up and sends them to xnu"), so the kernel registry value can lag after `sudo pmset` returns.

Steps, with the installed app quit:
1. Use a throwaway Swift script in the scratchpad, 20 times: run `sudo -n -k /usr/bin/pmset -a disablesleep <0|1>`, alternating. Then poll `IORegistryEntryCreateCFProperty(IOPMrootDomain, "SleepDisabled")` in-process every 1 ms until it shows the written value. Record each lag and whether `pmset -g` already showed the value on the first read.
2. Then 5 back-to-back pairs, the probe's shape: write 1, then write 0 at once with no wait. Record whether a 1 shows in the registry after the 0 write returned, and for how long.
3. At the end, restore the starting value.

Decision:
- Max lag ≤ 400 ms: go, with `settleTimeout` 2 s.
- Max lag 400 ms–1 s: go, with `settleTimeout` 5 s, and report it.
- Any lag > 1 s: stop and re-plan.

### B1. step-executor (Sonnet): status reads from the registry + settle after write, plus docs

Design (owner, 2026-11-19, "Registry for status"):
- Reporting reads use the registry.
- Every decision read stays on `pmset -g`.
- A write returns only when the registry shows the written value.
- Item 2 (reuse the read) is dropped: after B1 the reply's read is in-process.

**`Sources/LidAwakeCore/SleepControl.swift`:**
- `PowerSettings` gains `func currentState() throws -> Bool`, **declared in the protocol body** (a requirement, so `PMSet`'s version is dispatched through `settings: PowerSettings`), with a default `{ try read() }` in a protocol extension. So the conformers `FakePower`, `CommandPower`, `ProbingPower` and `FilePower` do not change.
- `PMSet.currentState()` is `(try? registryState()) ?? (try read())`. Registry first. With no usable property, it falls back to `pmset -g` (macOS 12–25 not verified to carry the key).
- `SleepSession.isAwake()` (`:129`) calls `settings.currentState()`. This is the only `SleepSession` change.
- These decision reads keep `settings.read()`: `:133` (setAwake), `:156` (releaseClaim), `:162` (stop), and `probeRule` `:78`.
- `PMSet.write(v)` (`:93-98`; its callers are `:85` probe, `:145` enable, `:147` disable, `:162` stop, and tests `SystemAdaptersTests.swift:77`, `:141`) becomes: `sudoWrite(v)`, then `settle(v)`, then the unchanged `guard try read() == v`.
- `settle(v)` polls `registryState()` every 20 ms until it equals `v`:
  - On a timeout (init parameter `settleTimeout`, default 2 s), it throws the same "macOS did not apply the sleep setting. Try Repair Sleep Setup." error.
  - If `registryState()` throws, it returns at once (no registry to wait for).
- Settle before verify closes the `SleepControl.swift` half of the macOS 27 post-write leftover, where `read()` is the registry and a stale value rejected a successful write. In `docs/todos/release-1.3-close-out.md:6`, narrow that item to the half that stays open: the uninstall script, `PrivilegeSetup.swift:94/:101/:104`, still writes, reads `ioreg` once and aborts on a stale value. The index count stays 5.
- The probe's intermediate `sudoWrite`s do not settle. Its final `write(false)` does.
- Replace the comment at `:28-31` to say what each read is for.

**Consumers of the changed `isAwake()`.** None of them needs an edit, and each now gets the registry value:
- `SleepWorker.swift:40` and `:43`, the reply.
- The worker's `status` reply, used by `LidAwake.swift:87` (the snapshot after every perform) and `LidAwake.swift:232` (the gate for `pmset displaysleepnow`).

**Tests, `Tests/LidAwakeCoreTests/SystemAdaptersTests.swift`:**
- **Hermetic:** every `PMSet(` in Tests passes `registryState:` (and a short `settleTimeout:` where a timeout is tested), because `write` now reads the registry. Each closure is chosen so that the test's own assertion still holds. Usually it mirrors the fake's state. The sites are:
  - `:76`: use `{ true }`. The registry agrees with the write and the fake `-g` (always `SleepDisabled 0`) disagrees, so the `-g` check still rejects it and `calls[1]` exists. A mirrored `{ false }` would time out in settle and crash the test at `:79`.
  - `:103`, the `probe()` helper used by `:106`, `:114`, `:121` and `:129`.
  - `:138`, `ProbingPower`, used by `:144` and `:170`.
  - `:183` and `:191`.
  - The opt-in `:67` stays the only real-registry test.
  - Acceptance check: each of the 8 construction sites (`:40`, `:51`, `:61`, `:76`, `:103`, `:138`, `:183`, `:191`, before the edit) passes `registryState:`. `:51` and `:61` already do, on the next line. Show the check with `grep -n -A1 "PMSet("`.
- **Unchanged and still green:** `:36`, `:47`, `:58`, `:188` (`read()` parse and fallback), `:73` (sudo, then `-g`) and the probe tests.
- **New (a):** `currentState()` returns the registry value with zero runner calls. Use a runner that calls `XCTFail` on any call.
- **New (b):** `currentState()` falls back to `pmset -g` when the registry throws. It throws (never reports enabled) when the registry throws and `pmset -g` omits the key.
- **New (c):** `write` returns after the registry flips on poll k. It throws the "did not apply" error when the registry never flips within `settleTimeout`. It skips the settle when the registry throws.
- **New (d):** `SleepWorker.serve` with `SleepSession` + `PMSet` + `RecordingRunner` + `registryState`, state 0, not owned, counted before EOF:
  - N `status` requests make **0** runner calls.
  - N `set false` requests make exactly **N** `-g` calls and 0 sudo calls (one decision read each).
- **New (e):** owned session, registry 0, `-g` 1, `shutdown`. A sudo `0` write must happen. This pins `stop()`'s decision on `-g`.
- **New (f):** a probe whose registry stays 1 after the final sudo `0` throws the "did not apply" error. This pins the final `write(false)` settling.
- **Red first:** write (d) alone, before any source change, and show its red run (it counts the reply's extra `-g` calls). (a), (c) and (f) do not compile on the old code, so they need no red run.

**Docs:**
- `README.md:45-46`: status from the registry; `pmset -g` for decisions and write verification; a write waits for the kernel to apply.
- `docs/testing.md`: new item 11 under "Manual checks before publishing", before the closing paragraph, in the style of item 4. Install the build, then record the worker's `vmmap --summary <pid> | grep "Physical footprint"` at start and after 30+ min. It must stay within ~1 MB.
- Fix the `SleepControl.swift` line cites that B1 shifts in the live index `docs/tech-debt.md`. Close-out files stay as dated snapshots, apart from the narrowing above.

**Invariants and bounds:**
- A reporting read (`isAwake`: worker status and reply) is 1 IORegistry read and launches no process. Its fallback is 1 `pmset -g` when the registry has no value.
- After `PMSet.write(v)` returns, the registry shows `v` (or has no value). Otherwise `write` threw. The settle bound is ≤ `settleTimeout` of 20 ms polls per write, in-process.
- Known limit: settle cannot tell a stale value from a fresh one when they are equal. After the probe (0→1→0, the 1 not settled), a reporting read can show a short-lived 1. Decisions are not affected (they read `-g`). B0 step 2 measures how long it lasts.
- A tick launches 1 `pmset -g` (the `setAwake` decision) in any healthy state. Today it launches 3, or 4 with keep-awake ON and the lid closed. `pmset displaysleepnow` while the lid is closed and a display is awake is unchanged.
- Unchanged: with the switch ON and the sudo rule denied, each tick still probes.

**Acceptance:** `swift build`. `swift test --filter SystemAdaptersTests` and `--filter SleepControlTests` with executed/skipped/failed counts. The red run of (d) is shown. The hermetic check is shown. One commit. Files: `SleepControl.swift`, `SystemAdaptersTests.swift`, `README.md`, `docs/testing.md`, `docs/tech-debt.md`, `docs/todos/release-1.3-close-out.md`.

### B2. Master, verification only: full suite and harness

`swift test` (counts), `./scripts/test-recovery.sh`, `./scripts/check-strings.sh`, `./scripts/build-app.sh universal && ./scripts/check-build.sh universal`. Pass: every command exits 0, with no failures and no new skips.

### B3. Master, verification only: real-app proof (positive path)

1. Baseline on the 1.3.1 installed at A3.6: worker CPU time (`ps -o time`) over 10 min.
2. Install: quit the app (`osascript -e 'tell application id "local.lidawake" to quit'`), then `rm -rf /Applications/LidAwake.app && cp -R LidAwake.app /Applications/LidAwake.app && open /Applications/LidAwake.app`. Check that the installed `CFBundleVersion` and binary match the branch build (`codesign -dv` cdhash = the built bundle's).
3. Over 10 min, sample worker CPU time and footprint. Pass:
   - CPU per minute ≤ 50% of the baseline.
   - Footprint within 1 MB.
4. Owner pass:
   - In the menu, turn keep-awake off, then on. While it runs, the master samples `pmset -g` and `ioreg` every 0.5 s. Both must follow each change within 2 s, and the menu state must match.
   - Lid closed on battery for 2 min with keep-awake ON, then open. The Mac stayed awake, and the display blanked as before.

### Stage 5

One whole-range `codex-challenge.sh <feature-base>..HEAD` + `spec-reviewer` in parallel. The fix loop runs on P0/P1. Ship (push, 1.3.2 or not) is a separate owner gate.

Parallel: none. B1 is the only code step, and Track A must land on `main` before B branches.

## Decisions (owner, 2026-11-19)

1. 1.3.1 = the leak fix alone. Then items 1–3.
2. Read design: "Registry for status". Item 2 is dropped as unnecessary.
