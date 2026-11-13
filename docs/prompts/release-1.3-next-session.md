# Handoff: finish LidAwake 1.3.0 — one release with everything

This file is the entry point for the next session. Each session takes the first open arc in the queue below, and updates this file when its arc lands.

**Every push, tag, release and GitHub comment needs the owner's explicit approval in the session.**

## Read first
1. This file.
2. `docs/prompts/release-1.3-plan.md` — what was planned, built and decided on 2026-11-13 (its "Decisions" section is the record).
3. `docs/tech-debt.md` — the index of deferred work. The three "Release 1.3.0" lines are this queue.
4. The todo file of the arc you take (paths in the queue).
5. `docs/prompts/release-1.3-arc-a-plan.md` — Arc A as built, with the owner's decisions of 2026-11-13 (its "Decision" section and its Addendum).

## The decision that shapes this handoff
On 2026-11-13 the release was built, reviewed and ready. The owner held the push and chose **one release with everything**: the four arcs below are built on this branch first, then a single v1.3.0 goes out. The owner accepted the cost: macOS 27 users stay on the broken 1.2.0 until then.

## State at handoff
- **Branch:** `release-1.3`. HEAD is the commit that records Arc A in this file; the code head before it is `7b8deaf`. Local `main` is `7fb5f22`, `origin/main` is `e10fe0b`. **Nothing is pushed**; the branch is 22 commits ahead of `origin/main`.
- **Landed on the branch:**
  - `b24a1b9`, `c7bab37` — macOS 27: read `SleepDisabled` from the `IOPMrootDomain` registry entry when `pmset -g` omits it (outside PR #3 merged with `--no-ff`, plus the uninstall-script fallback and tests).
  - `88bc328` — the master switch is on only with at least one condition (Core only).
  - `24641f5` — LidAwake's own sentence in the two admin password dialogs.
  - `0beb8ba` — version 1.3.0 (build 10), README and manual checks.
  - `6fe6ce3` — `scripts/check-build.sh`: one `lipo -verify_arch` call per architecture (Xcode 27 rejects two).
  - `24bd8ec` — the redundant "LidAwake on GitHub" menu row is removed.
  - `34f22af` — `docs/menu.png`, a real screenshot, in the README (now out of date; see the queue).
  - Arc A: `d196cb1` — the compact layout of `SwitchMenuRow` and `MenuEntry.Style.compactToggle` (Core); `4bf8440` — the two condition rows use it, README and manual checks; `27430a6` — the compact title is drawn whole (a private cell removes AppKit's 2 pt text inset); `7b8deaf` — a running operation no longer dims the menu (`operationInFlight` replaces the disabled-while-pending signal; `setupSleep`, `uninstallApp` and `toggleLogin` got their own guard).
  - Docs: the plans, review files in `docs/reviews/release-1.3/`, index lines and todo files.
- **Review:** the whole-range codex gate is clean on `f05d57d..34f22af` (round 2, zero P0/P1) and on `34f22af..7b8deaf` (Arc A, round 1, zero findings; the spec check found no gap). The two ranges join with no gap; the commit after `7b8deaf` is docs only. Standalone P2 and theoretical findings of the first range are deferred by the owner; they stay deferred. Arc A deferred nothing.
- **Tests on `7b8deaf`:** `swift test` 111 executed, 1 skipped (the opt-in registry test), 0 failed. `LIDAWAKE_REAL_REGISTRY_TEST=1 swift test --filter testRegistryRead` passes on the owner's Mac. `scripts/test-recovery.sh` passes all 5 cases. `scripts/build-app.sh universal` and `scripts/check-build.sh universal` pass.
- **Owner device passes (2026-11-13):** the first pass covered the switch rule, relaunch and icon shapes. The Arc A pass found that the whole menu flashed on a small-switch toggle; after the fix the owner confirmed on `7b8deaf`: the menu stays open on the two rows, no flash, everything else works. The app in the owner's `/Applications` is the development build of `7b8deaf`.
- **Arc A decisions (owner):** switch rows on the two conditions only; mouse and VoiceOver only on those rows (no arrow keys or Return, as the master switch row); a running operation never dims a row.
- **Release notes draft:** `docs/prompts/release-1.3-notes-draft.md`. It describes the state at handoff and must be updated by the arcs (see the ship checklist).
- **Not verified by anyone here:** behavior on macOS 27 (the owner's Mac runs 26.x, where `pmset -g` still prints the line). Both PR authors reported their patch working on 27.0.1. The metrics of the two switch rows are those of macOS 26; on macOS 12–15 and 27 they may sit 2–3 pt off the standard rows.

## The queue
Each arc is its own session with its own plan, review gate and owner checks. The feature base of an arc is the commit that adds its plan file.

- [x] **Arc A — the menu stays open on condition clicks.** Landed 2026-11-13: "Connected to Power" and "On Battery" are switch rows (a small native switch, no hover highlight) that keep the menu open; a running operation no longer dims any row. Plan and decisions: `docs/prompts/release-1.3-arc-a-plan.md`. The owner's device pass passed.
- [ ] **Screenshot — `docs/menu.png` is still the old picture.** The owner captures it again (on battery, master on, both conditions on, External Display and Launch at Login checked). The README alt text already describes the new picture, so the two disagree until then. The commit that adds it gets one more review round. Any session may take this when the owner supplies the file; it must land before Ship.
- [ ] **Arc B — the password dialog names LidAwake.** Context: `docs/todos/admin-dialog-title.md`. The bold title is the asking process, today `osascript`. Running the script inside the app is expected to name LidAwake; nobody has seen that dialog yet. Needs the owner's test of Sleep Setup and of uninstall with a real password. When it lands, remove the "still titled osascript" sentence from the release notes draft.
- [ ] **Arc C — String Catalog locales.** Context: `docs/todos/string-catalog-locales.md`. After A and B, so it moves the final strings. The proof is a before/after comparison of every English and Russian text. Open scope point for its plan: Core's English-only error texts.
- [ ] **Arc D — Developer ID signing and notarization.** Context: `docs/todos/notarize-direct-dmg.md`. **Blocked on the owner:** a notary credential stored with `xcrun notarytool store-credentials`. Check the hardened runtime against Arc B's in-app script before signing off. It changes the install text in the README and in the release notes draft.
- [ ] **Ship.** The checklist below.

A and B may share one session only if the plan stays inside one arc's size (at most 5 execution steps, one review gate). Otherwise one arc per session.

## Ship checklist (after the last arc)
1. Update `docs/prompts/release-1.3-notes-draft.md` to the final state, and show it to the owner.
2. Full verification on the final head: `swift test`, the opt-in registry test, `scripts/test-recovery.sh`, universal build and check. Every arc's codex gate is clean, and the ranges join with no gap from `f05d57d` to the head.
3. Scan every commit to be pushed for names of other projects and for credentials.
4. With the owner's approval: fast-forward `main` to `release-1.3` and push `main`. GitHub then marks PR #3 as merged. Wait for CI to pass.
5. With the owner's approval: `./release.sh`, `shasum -a 256 LidAwake.dmg > SHA256SUMS.txt` (format: `<sha256>  LidAwake.dmg`), then the GitHub release `v1.3.0` with both files and the notes.
6. With the owner's approval: the three comments below, and close PR #2.
7. Check `releases/latest` returns `v1.3.0` with the `html_url` form the in-app update check expects (`Sources/LidAwakeCore/GitHubUpdates.swift`), and that the downloaded DMG matches the checksum.
8. Delete this file and the notes draft in the last docs commit; delete the merged local branches `lidawake-fixes` and `release-1.3`.

## Comment wording the owner approved on 2026-11-13
Ask again before posting; the wording was approved, the moment was not. No `@` mentions.

**PR #3** (shows as merged after the push):
> Thank you for this fix. It is merged into main unchanged and ships in v1.3.0. I chose this PR as the base because it keeps the strict parse: the registry is read only when `pmset -g` has no `SleepDisabled` text, and a malformed line still throws. On top of it, 1.3.0 gives the uninstall script the same fallback and makes the real-registry test opt-in. I have no Mac on macOS 27. If you can, please confirm that 1.3.0 turns keep-awake on and off on your machine.

**PR #2** (comment, then close):
> Thank you for this fix, and for being first with it. I merged #3 for 1.3.0 because it reads the registry only when `pmset -g` has no `SleepDisabled` text at all; this PR also falls back when the line is malformed or duplicated, and I want those cases to stay errors. The idea is the same, and you are credited in the v1.3.0 release notes. Closing this one as covered. I have no Mac on macOS 27; if you can, please confirm that 1.3.0 works on yours.

**Issue #1** (already closed):
> Fixed in v1.3.0: LidAwake now reads `SleepDisabled` from the IOPMrootDomain registry entry when `pmset -g` leaves it out (#3; #2 proposed the same idea). Thank you for the precise report. If it still fails on macOS 27, please reopen.

## The owner's standing instructions (verbatim)
- "I think we need to finish and to have this project like completed."
- On the menu: "I don't like that when I check or uncheck awake from battery or from power, the window disappears, which is not happening when I click the toggle. I think we should keep window open until I click outside."
- On locales: "make sure locales are living in corresponding folder so we can easily extend it later", then, after the String Catalog was explained as Apple's current practice: "ok lets do as apple says".
- On a render: "battery icon looks horizontally compressed on renders. check plz." Renders must draw symbols at their natural size.
- On this handoff: "prepare a handoff to finish all that what we planned in the new version", with the choice "One release with everything".
- Never push without explicit approval in the session.

## Environment traps
- **The installed app is live.** `/Applications/LidAwake.app` runs and manages the real sleep setting. Never run `pmset -a …`, never launch a second copy (it shares the session lock and the settings domain), and never trigger an admin password prompt. `swift test` and `scripts/test-recovery.sh` use fakes and are safe.
- **Screen capture is blocked for the agent.** `screencapture` fails with "could not create image from rect": the terminal has no Screen Recording permission. Real screenshots come from the owner (Cmd+Shift+4, Space, click the menu), unless the owner grants that permission and Accessibility.
- **`./build.sh` asks before it overwrites the installed app.** The owner runs it in their own Terminal (quit LidAwake first, answer `y`). Agents use `./scripts/build-app.sh` and `./scripts/check-build.sh` only.
- **The shipped binary is stamped `minos 12.0, sdk 12.0`** (`vtool -show-build`), so AppKit draws legacy-size controls in the app: a regular `NSSwitch` is 38×22 and a small one 32×18, while its intrinsic size stays 38×22. `swift test` and a bare `swiftc` binary link the current SDK and draw differently. A probe or render binary must be patched to compare with the app: `vtool -set-build-version macos 12.0 12.0 -replace -output <out> <in>`, then `codesign --force --sign - <out>`. No test asserts a switch's pixel size.
- **Renders** are built offscreen: states from the real `PolicyController` with a fake sleep, menus filled by the real `StableMenu` from a labeled copy of `updateMenu()` in `LidAwake.swift` (the app target cannot be imported), the real `SwitchMenuRow` views; standard rows are drawn by the harness. The harness lived in a temporary folder and is gone. Rules learned in Arc A:
  - Check the harness against `docs/menu.png` before a render is shown. AppKit on macOS 26 applies the image column per section (between separators) and reserves the 8 pt state column only while some item, view-backed ones included, has a state other than off.
  - An offscreen `NSSwitch` draws grey unless the offscreen `NSWindow` subclass answers `@objc(hasKeyAppearance)` with `true`. Force the Aqua appearance when the system is in Dark mode.
  - A text field's cell draws its text 2 pt inside its frame and needs 4 pt more than the string width.
  - A view-backed row cannot be judged without a render of the real view: Arc A's Step 3 render found truncated titles that the unit tests had passed.
- **Xcode 27.2:** `lipo -verify_arch` takes one architecture per call. `xcrun xcstringstool compile <catalog> --output-directory <dir>` works and writes `<lang>.lproj/Localizable.strings`; its `extract` and `sync` commands are untried.
- **Editor diagnostics are stale** in this repo; trust `swift build` and `swift test`.
- **zsh:** `${PIPESTATUS[0]}` is empty; use `${pipestatus[1]}`.
- **macOS 27 cannot be exercised** on the owner's Mac.

## Out of scope
- The keep-awake leases feature (`docs/prompts/keep-awake-leases-plan.md` stays parked).
- The deferred P2 and theoretical review findings in `docs/tech-debt.md`.
