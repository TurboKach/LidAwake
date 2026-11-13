# Handoff: finish LidAwake 1.3.0 — one release with everything

This file is the entry point for the next session. Each session takes the first open arc in the queue below, and updates this file when its arc lands.

**Every push, tag, release and GitHub comment needs the owner's explicit approval in the session.**

## Read first
1. This file.
2. `docs/prompts/release-1.3-plan.md` — what was planned, built and decided on 2026-11-13 (its "Decisions" section is the record).
3. `docs/tech-debt.md` — the index of deferred work. The four "Release 1.3.0" lines are this queue.
4. The todo file of the arc you take (paths in the queue).

## The decision that shapes this handoff
On 2026-11-13 the release was built, reviewed and ready. The owner held the push and chose **one release with everything**: the four arcs below are built on this branch first, then a single v1.3.0 goes out. The owner accepted the cost: macOS 27 users stay on the broken 1.2.0 until then.

## State at handoff
- **Branch:** `release-1.3`. HEAD is the commit that adds this file; the commit before it is `8edbdc6`. Local `main` is `7fb5f22`, `origin/main` is `e10fe0b`. **Nothing is pushed**; the branch is 15 commits ahead of `origin/main`.
- **Landed on the branch:**
  - `b24a1b9`, `c7bab37` — macOS 27: read `SleepDisabled` from the `IOPMrootDomain` registry entry when `pmset -g` omits it (outside PR #3 merged with `--no-ff`, plus the uninstall-script fallback and tests).
  - `88bc328` — the master switch is on only with at least one condition (Core only).
  - `24641f5` — LidAwake's own sentence in the two admin password dialogs.
  - `0beb8ba` — version 1.3.0 (build 10), README and manual checks.
  - `6fe6ce3` — `scripts/check-build.sh`: one `lipo -verify_arch` call per architecture (Xcode 27 rejects two).
  - `24bd8ec` — the redundant "LidAwake on GitHub" menu row is removed.
  - `34f22af` — `docs/menu.png`, a real screenshot, in the README.
  - Docs: the plan, review files in `docs/reviews/release-1.3/`, index lines and todo files.
- **Review:** the whole-range codex gate is clean on `f05d57d..34f22af` (round 2, zero P0/P1). Commits after `34f22af` are docs only. Standalone P2 and theoretical findings are deferred by the owner; they stay deferred.
- **Tests on that code:** `swift test` 97 executed, 1 skipped (the opt-in registry test), 0 failed. `LIDAWAKE_REAL_REGISTRY_TEST=1 swift test --filter testRegistryRead` passes on the owner's Mac. `scripts/test-recovery.sh` passes all 5 cases. `scripts/build-app.sh universal` and `scripts/check-build.sh universal` pass.
- **Owner device pass (2026-11-13):** all checks passed on this build — the switch rule, relaunch, icon shapes. The app in the owner's `/Applications` is now this development build of 1.3.0.
- **Release notes draft:** `docs/prompts/release-1.3-notes-draft.md`. It describes the state at handoff and must be updated by the arcs (see the ship checklist).
- **Not verified by anyone here:** behavior on macOS 27 (the owner's Mac runs 26.x, where `pmset -g` still prints the line). Both PR authors reported their patch working on 27.0.1.

## The queue
Each arc is its own session with its own plan, review gate and owner checks. The feature base of an arc is the commit that adds its plan file.

- [ ] **Arc A — the menu stays open on condition clicks.** Context: `docs/todos/menu-rows-stay-open.md`. The condition rows are standard menu items, which AppKit closes on click; the switch row stays open because it is a custom view. The owner wants rendered options before choosing which rows stay open and how they look. Needs a second device pass. `docs/menu.png` must be captured again afterward (by the owner).
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
- **Screen capture is blocked for the agent.** Real screenshots come from the owner (Cmd+Shift+4, Space, click the menu).
- **Renders** are built offscreen: states from the real `PolicyController` with a fake sleep, rows from a labeled copy of `updateMenu()` in `LidAwake.swift` (the app target cannot be imported), the real `SwitchMenuRow`, and the `NSMenuItem` images that `StableMenu` builds, drawn at their own size. An offscreen switch draws grey when it is on. The earlier harness lived in a temporary folder and is gone.
- **Xcode 27.2:** `lipo -verify_arch` takes one architecture per call. `xcrun xcstringstool compile <catalog> --output-directory <dir>` works and writes `<lang>.lproj/Localizable.strings`; its `extract` and `sync` commands are untried.
- **Editor diagnostics are stale** in this repo; trust `swift build` and `swift test`.
- **zsh:** `${PIPESTATUS[0]}` is empty; use `${pipestatus[1]}`.
- **macOS 27 cannot be exercised** on the owner's Mac.

## Out of scope
- The keep-awake leases feature (`docs/prompts/keep-awake-leases-plan.md` stays parked).
- The deferred P2 and theoretical review findings in `docs/tech-debt.md`.
