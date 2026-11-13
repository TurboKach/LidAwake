# LidAwake 1.3.0 — the finishing release

## Context

LidAwake's last release is v1.2.0 (2026-09-14). Three things are open, and the owner decided on 2026-11-13 that the project counts as complete after one release that closes them:

1. **v1.2.0 does not work on macOS 27.** `pmset -g` no longer prints the `SleepDisabled` line, `PMSet.parse` throws, and the app can never turn keep-awake on (issue #1). Two outside pull requests offer a fallback read from the `IOPMrootDomain` registry entry: #2 (Matte1404) and #3 (Fuadeiza). Neither has an answer yet.
2. **The master switch can be ON with no "Keep awake when" condition checked.** In that state it does nothing. The owner decided the fix on 2026-10-06 (rules in Step 2).
3. **15 commits on `origin/main` were never released** (local `main` has one more, the CLAUDE.md commit): the "Uninstall LidAwake…" menu item and the quit/uninstall fixes.

Out of scope: the keep-awake leases feature (stays parked in `docs/prompts/keep-awake-leases-plan.md`).

Line numbers below are at `7fb5f22`. Step 1 shifts the lines in `SleepControl.swift`.

## Branch and base

- Work happens on a new branch `release-1.3`, cut from `main` (`7fb5f22`). UI work stays off `main` until the render and the owner's device pass confirm it.
- Feature base for the review range = the commit that adds this plan to `docs/prompts/release-1.3-plan.md` on that branch.
- `Parallel: none — Steps 1 and 2 both edit Sources/LidAwakeCore/SleepControl.swift.`

## Steps

### Step 1 — macOS 27: read `SleepDisabled` when `pmset -g` omits it
**Executor:** `step-executor` (Sonnet). Bug fix: red, then green, for the parts this step adds.

**Base: PR #3**, head `d3774f3`. It keeps today's strict parsing: the registry is read only when the pmset output has no `SleepDisabled` text at all; a malformed or duplicated line still throws. PR #2 replaces a malformed line with the registry value, which weakens the read.

1. `git fetch origin pull/3/head`. Stop and report if `FETCH_HEAD` is not `d3774f3` (the reviewed commit). Read the diff; it must touch only `Sources/LidAwakeCore/SleepControl.swift` and `Tests/LidAwakeCoreTests/SystemAdaptersTests.swift`.
2. `git merge --no-ff FETCH_HEAD` into `release-1.3`. The contributor keeps authorship, and GitHub marks PR #3 as merged when `main` is pushed.
3. A follow-up commit closes the gaps:
   - **Both-fail test:** pmset has no line and the registry read throws → `read()` throws. PR #3's code already does this, so the test documents it (green from the start).
   - **Host-dependent test:** PR #3's `testRegistryReadReturnsTheLiveSleepOverrideStateWithoutRoot` reads the real registry. It becomes opt-in (`XCTSkip` unless `LIDAWAKE_REAL_REGISTRY_TEST=1`), so no unit test can fail because of the host's power state.
   - **Same mechanism, second site:** the uninstall script at `Sources/LidAwakeCore/PrivilegeSetup.swift:85` runs `pmset -g | awk '$1 == "SleepDisabled" { print $2 }'`. Today an empty read gives `"" != 0`, so on macOS 27 the script prints its error and exits 1 before it removes the rule: "Uninstall LidAwake…" can never succeed there. Give it the same rule: pmset first; when pmset has no `SleepDisabled` text, read the property with `/usr/sbin/ioreg -r -c IOPMrootDomain -d 1` (it prints `Yes`/`No`). Extend the script test helper (`Tests/LidAwakeCoreTests/SystemAdaptersTests.swift:266-286` before the merge, about 26 lines lower after it). The helper replaces only the two pmset paths today, so it also needs a fake `ioreg`; without one the test would read this Mac's real state.

**Invariant:** a failed read throws; it never counts as "sleep enabled". pmset stays the first source. Bound: one `pmset -g` run plus at most one registry read per `read()` call; no retry, no cache.

**Callers of `PMSet.read()` whose result now may come from the registry** (no edits expected; check each still holds): `SleepControl.swift:52` (`probeRule`), `:69` (write verification), `:103` (`isAwake`), `:107` (`setAwake`), `:130` (`releaseClaim`, `try?`), `:136` (`stop`); constructor at `SleepWorker.swift:26`.

**Edge cases:** pmset prints the line → registry not read. Line missing, registry has a Bool → that value. Line missing, registry entry or property missing or not a Bool → throws. Malformed or duplicated line → throws, registry not read. pmset process failure → throws as today. Uninstall script: line missing and `ioreg` has no value → the failure path of today, never "enabled".

**Acceptance:** `swift test --filter SystemAdaptersTests` green with executed/skipped/failed counts shown (1 skip expected: the opt-in test); the uninstall-script "line missing" cases shown red before the script change and green after; `LIDAWAKE_REAL_REGISTRY_TEST=1 swift test --filter testRegistryRead` passes on this Mac; `./scripts/test-recovery.sh` still passes (it compiles Core with a bare `swiftc`, and PR #3 adds `import IOKit`).

### Step 2 — the switch needs a condition
**Executor:** `step-executor` (Sonnet). Bug fix: tests red first, then green.

**Rules (owner, 2026-10-06):**
- The switch is ON only if at least one condition is checked.
- Unchecking the last condition turns the switch off.
- Turning the switch on with no condition checked checks both.
- Fresh install: switch OFF, both conditions checked.
- A saved state that breaks the first rule (switch ON, no condition) loads as the fresh-install state.

**Design:**
- `SleepPolicy` (`Sources/LidAwakeCore/SleepControl.swift:147`): init defaults become `isEnabled: false, onAC: true, onBattery: true`. Add a pure `normalized` value: ON with no condition → `SleepPolicy()`; every other state unchanged.
- `PolicyController.init` stores `policy.normalized`, so the rule holds for every way a policy enters the controller and is testable through the existing seam.
- `PolicyController.setEnabled(true)` (`:173-179`) with no condition on → the new policy has both on. `toggle(onAC:)` (`:181-189`) that leaves no condition on while ON → the new policy is OFF. Both stay one transition: apply to `SleepControlling` first, commit and `persist` only on success (the existing pattern).
- App layer (`LidAwake.swift`): **no edit.** The read at `:32-34` and the registration at `:117` stay as they are. The registered `lidAwakeEnabled: true` must stay: v1.0 and v1.1 saved only the condition keys, and v1.2.0 saves only inside `setEnabled`/`toggle`, so an upgrader who never touched the menu has a condition saved and no `lidAwakeEnabled` key. The registration is what keeps that Mac awake today. A fresh install reads (ON, none) and the controller normalizes it to (OFF, both).
- No new strings and no menu layout change. `awakeControlsEnabled` (`:282`) is unchanged.

**Display:** (OFF, none) is a valid saved state. After the user unchecks the last condition the menu shows the switch OFF and both boxes unchecked (greyed), before and after a relaunch. Turning the switch on checks both.

**Invariant:** every policy the controller holds satisfies `isEnabled ⇒ (onAC ∨ onBattery)`. Bound: three booleans, a pure function, no I/O. Upgrade: a saved state that keeps the Mac awake today is untouched, and no state starts to keep it awake. Only (ON, none) changes, to (OFF, both). Its one visible side effect: the external-display option is greyed (`LidAwake.swift:282, :343`) and lid-close display blanking (`:232`) is off, as in any OFF state.

**Call sites:**
- `SleepPolicy(`: `LidAwake.swift:16`, `:32`; tests `SleepControlTests.swift:130, 140, 152, 154, 161, 172, 181, 191, 197, 213, 219, 228, 248, 252`. Eleven lean on the old defaults (`:130, 140, 152, 154, 161, 172, 191, 197, 213, 228, 248`; most on `isEnabled: true`). Each gets explicit arguments that keep its intent; `:213` must still test ON→OFF. A test that started from (ON, none) (`:130`, `:152`) starts from the nearest valid state, and the report names it. No assertion is weakened.
- `setEnabled(`: `LidAwake.swift:330`; tests `:178, 188, 201, 215, 231, 236`.
- `toggle(onAC:)`: `LidAwake.swift:340`; tests `:131, 153, 250, 251`.
- Defaults keys: `LidAwake.swift:32-34, 40-42, 117` only.

**Edge cases:** ON with AC only, uncheck AC → OFF, sleep restored, saved. OFF with no condition, turn ON → ON with both. OFF with AC only, turn ON → conditions unchanged. Condition edited while OFF → stays OFF (`SleepControlTests.swift:243-253` keeps passing). The sleep write fails in a combined transition → policy and saved values unchanged. Enabling opens Sleep Setup and the user cancels → still OFF, conditions unchanged. Unchecking the last condition while the other power source is active → OFF with no sleep write (the existing rule at `SleepControl.swift:155-156`; `SleepControlTests.swift:149-156` asserts no write for an inactive-source edit). `MenuState()` before the first snapshot (`LidAwake.swift:16`) shows OFF.

**Load cases** (Bool triples after the unchanged defaults read): no keys → (ON, none) → (OFF, both). Saved (ON, none) → (OFF, both). Saved (OFF, none) → unchanged. Only a condition saved (upgrade from 1.0/1.1, or an untouched 1.2.0) → (ON, that condition), unchanged.

**Acceptance:** new tests for each rule, for `normalized` on all eight states and for the `PolicyController.init` normalization, shown red then green; `swift test --filter SleepControlTests` green with counts.

### Step 3 — admin prompt wording
**Executor:** `step-executor` (Sonnet).
`Sources/LidAwakeCore/PrivilegeSetup.swift:39` (install) and `:56` (uninstall) build `do shell script … with administrator privileges` with no `with prompt`, so macOS shows "osascript wants to make changes".

**Design:** `LidAwakeCore` has no localization (`L` is private to the app, `LidAwake.swift:6-8`), so the text reaches Core as data.
- `PrivilegeSetup.init` (`PrivilegeSetup.swift:10`) gains `installPrompt: String? = nil` and `uninstallPrompt: String? = nil`. When a prompt is set, the script line gets ` with prompt <appleScriptString(prompt)>` (the existing escaping helper, `Commands.swift:83`). With `nil` the line is the same as today.
- The app passes both texts at its one construction, `LidAwake.swift:29`, through `L(en, ru)`.
- `Uninstaller`, `AppRuntime.uninstallApp()` and every test construction stay unchanged (default arguments). The exact-string assertion at `SystemAdaptersTests.swift:216-219` stays green.
- Texts: install — "LidAwake needs an administrator to install its sleep rule." / "LidAwake нужно разрешение администратора, чтобы установить правило управления сном."; uninstall — "LidAwake needs an administrator to remove its sleep rule." / "LidAwake нужно разрешение администратора, чтобы удалить правило управления сном."

**Edge cases:** a prompt with quotes or a line break is escaped by `appleScriptString`. `LoginItems.swift:46` is an Automation prompt, not an admin prompt, and stays as it is.

**Acceptance:** new tests assert the full osascript argument for install and for uninstall with a prompt set (including one with a quote character), and the unchanged argument with none; `swift test --filter SystemAdaptersTests` green with counts. The dialog itself is an owner check (it needs a password prompt).

### Step 4 — version and docs
**Executor:** `step-executor` (Sonnet).
- `Info.plist:9` `CFBundleShortVersionString` 1.2.0 → 1.3.0; `:10` `CFBundleVersion` 9 → 10.
- README: the install, uninstall (`:70-80`) and behavior sections match the app after Steps 1–3 (menu uninstall item, switch rule, macOS 27).
- `docs/testing.md` (`:18, :27, :41` name `pmset -g`): manual checks for the switch rule, and the macOS 27 note with the `ioreg` command. The README has no `pmset -g` instruction, so it needs no such note.
- Release notes draft in the session scratchpad (not in the repo), in the v1.2.0 structure, with credit to the authors of PR #3 and PR #2 and the reporter of issue #1.
**Acceptance:** `./scripts/build-app.sh native` builds; `./scripts/check-build.sh native` passes; the built `LidAwake.app/Contents/Info.plist` reads 1.3.0 and 10.

### Step 5 — full verification and render
**Executor:** `step-executor` (Sonnet). No product edits.
- `swift test` (full; counts), `./scripts/test-recovery.sh` (file-backed, never pmset), `./scripts/build-app.sh universal`, `./scripts/check-build.sh universal`, and the opt-in real-registry test on this Mac.
- **Render:** two PNGs (en, ru), four panels each: fresh install (OFF, both checked); ON with both; ON with AC only; after unchecking the last condition (OFF, none checked). A throwaway harness in the scratchpad, nothing added to the repo:
  - **States** come from the real `PolicyController` with a fake sleep, driven through the real transitions.
  - **Rows** come from a copy of the mapping in `private func updateMenu()` (`LidAwake.swift:289-315`), with its `L(en, ru)` strings. The app target is not reachable from tests (`Package.swift:11-17`), and the built app cannot be launched for this (the installed 1.2.0 holds the session lock and shares the defaults domain). Each PNG carries the caption "mapping copied from LidAwake.swift".
  - **Drawing:** the real Core menu rows (`Sources/LidAwakeCore/StableMenu.swift`) drawn in-process where they draw offscreen, otherwise a SwiftUI `ImageRenderer` mock; the caption names which.
  - The master opens the PNGs for the owner. The real pixels are covered by the owner's device pass.

**Acceptance:** every command above exits 0 with executed/skipped/failed counts shown; both PNGs exist and show the four states.

## Review
Per-step codex rounds after Steps 1–4 (pinned), one whole-range codex challenge plus `spec-reviewer` after Step 5, then the fix loop until zero P0/P1.

## Verification that needs a person
- **Owner device pass (about 5 minutes, before `release-1.3` merges into `main`):** install the build; uncheck the conditions one by one and see the switch turn off after the last; turn the switch on and see both conditions checked and ☕ on the right power source; quit and relaunch. See the new admin prompt text once (Cancel is enough).
- **macOS 27 cannot be exercised here** (this Mac runs 26.6.2, where pmset still prints the line). The unit seam covers the fallback logic and the opt-in test covers the real registry read on this Mac. The real macOS 27 run is a manual test by someone on 27: after the release, both contributors are asked in their PR threads to confirm, and a 1.3.1 fix follows if something is wrong.
- Unconfirmed: whether the registry value updates at once after a `pmset -a disablesleep` write on macOS 27 (write verification at `SleepControl.swift:69` depends on it). Both PR authors report their patch working on 27.0.1.

## Ship (each outward step needs the owner's approval in the session)
1. Fast-forward `main` to `release-1.3`; scan the range for private names; push `main` (this also publishes `7fb5f22`, the CLAUDE.md commit).
2. Tag `v1.3.0`, `./release.sh`, `shasum -a 256 LidAwake.dmg > SHA256SUMS.txt`, `gh release create` with both assets and the approved notes (ad-hoc signed, as v1.2.0; notarization follows in 1.3.1).
3. PR #3 shows as merged; thank its author in a comment. Close PR #2 with a comment that explains the choice and names the credit. Add a comment on the closed issue #1 that points to the release. Comment texts are shown for approval first.
4. Post-release check: `releases/latest` returns `v1.3.0` with the `html_url` form the in-app update check expects (`GitHubUpdates.swift:63`); the downloaded DMG matches the checksum; the owner's installed 1.2.0 shows the update.
5. Cleanup: delete the merged local branches `lidawake-fixes` and `release-1.3`; record the landed shas in the session's private notes, as the 2026-10-06 brief asks.
6. Write the handoff brief for the next arc (1.3.1: Developer ID signing and notarization of the direct DMG) to the session scratchpad. That arc runs in a new session.

## Deferred-work index (master, docs only)
- Add one line for `SleepControl.swift` `releaseClaim`: a failed re-read after the probe keeps `ownsOverride = true`, so the next reconcile skips the probe (P2; context in `docs/todos/`). Step 1 moves that file's lines by about 26, so the two existing index lines that cite it (`docs/tech-debt.md:13, :16`) get their line numbers corrected in the same commit.
- Add one line for the 1.3.1 follow-up: Developer ID signing and notarization of the direct DMG (context in `docs/todos/`; it needs a notary credential from the owner).

## Decisions (owner, 2026-11-13)
1. **Outside PRs:** merge PR #3, add the follow-up commit, close PR #2 with thanks and credit. (Not chosen: merge PR #2; an own fix that closes both.)
2. **macOS 27 confirmation:** release 1.3.0 directly and ask both contributors to confirm. (Not chosen: a pre-release first.)
3. **Admin prompt wording:** fix it in this release (Step 3). This replaces the 2026-10-06 decision to defer it.
4. **Notarization:** a follow-up 1.3.1 release; 1.3.0 stays ad-hoc signed. (Not chosen: stay ad-hoc for good; notarize in 1.3.0.)

Assumption: the version is 1.3.0, not 1.2.1, because the release adds a menu item and changes switch behavior.
