# LidAwake 1.3.0, Arc A — the two condition rows keep the menu open

## Context

Owner, device pass 2026-11-13: "when I check or uncheck awake from battery or from power, the window disappears, which is not happening when I click the toggle. I think we should keep window open until I click outside."

Cause: "Connected to Power" (`ac`) and "On Battery" (`battery`) are standard `NSMenuItem`s, which AppKit closes on click. The master row stays open because it is a custom view (`SwitchMenuRow`). AppKit has no public setting that keeps a standard item open (checked in the macOS 27.2 SDK headers).

**Decided by the owner on 2026-11-13, from rendered option sheets:** switch rows (option B2). Only `ac` and `battery` change: each gets a native small `NSSwitch` at the right and no hover highlight. "Turn Off External Display on Lid Close" and "Launch at Login" stay standard checkmark rows that close the menu. Not chosen: self-drawn checkmark rows (A), re-opening the menu after the click (R), three or four switch rows (B3, B4).

Reference pictures (scratch, not in the repo; may be gone later): `sheet-en.png`, `sheet-ru.png`, `compare-en.png` and the prototype sources in `/var/folders/l7/91m9cppx1gs8v15q9hshwb780000gn/T/lidawake-arcA-H6eSe9` (SCRATCH). Column B2 is the approved look.

## Branch, base, parallel

- Branch `release-1.3`, nothing pushed. The plan is committed as `docs/prompts/release-1.3-arc-a-plan.md`; that commit is the feature base for the per-step rounds.
- The whole-range review runs on `34f22af..HEAD` (the head of the previous clean gate), so the reviewed ranges join with no gap. The commits between `34f22af` and the plan commit are docs only.
- `Parallel: none — Step 2 uses the style case that Step 1 adds; Step 3 verifies both.`

## Design

One row class, two layouts. `SwitchMenuRow` already has the logic these rows need: the click animates at once, the action is sent, the switch keeps its position while the operation runs and rolls back if the state did not change (`awaitingChange`, `SwitchMenuRow.swift:56-73, 87-93`). The condition actions use the same path as the master switch: `perform(showFailure: true)` raises `pendingUserOperations` and calls `updateUI()` synchronously (`LidAwake.swift:182-216`), so the rows are disabled while a toggle is in flight. A second class would copy that logic; a layout parameter does not.

- `MenuEntry.Style` (`StableMenu.swift:4`) gains `compactToggle`.
- `SwitchMenuRow.init(item:layout:)` with `layout: Layout = .regular`; `Layout` is `regular` (today's row, unchanged pixels) or `compact`.
- `StableMenu` (`:81-94`) attaches a `SwitchMenuRow` for both toggle styles, with the layout that matches the style. `item.state` stays the row's data source (`:70` is unchanged), and `item.image` stays `nil` for view-backed rows, so the heading "Keep awake when:" sits at the plain title position, as in sheet B2.

Compact layout (metrics measured against `docs/menu.png` on macOS 26, from SCRATCH `src/Views.swift`):
- Row height 24. Title font `NSFont.menuFont(ofSize: 0)`, one line, tail truncation as a last resort.
- Content inset: 24 when the menu has a state column, 16 when it has none (see mechanism 2). Then `indentationLevel × 12`, a 19 pt icon column (symbol at 11 pt, centred; see mechanism 5), a 6.5 pt gap, the title.
- `NSSwitch` with `controlSize = .small`, trailing inset 14 (the master switch's inset), vertically centred; at least 16 pt between title and switch.
- Disabled: the title and the icon use `disabledControlTextColor`, the switch is disabled. (AppKit dims a disabled standard row's icon the same way; the option sheet drew the icon dark, a harness simplification.)
- Click target: the whole row. `mouseUp` inside the bounds calls `toggle.performClick` (the regular layout keeps its top-34-pt rule); `hitTest` routes the label and the icon to the row.
- No hover highlight, no tooltip (the rows have no key equivalent). Accessibility as the master row: the switch carries the title as its label; the label and the icon are not accessibility elements.

Mechanisms, invariants, bounds:
1. **Row width.** Invariant: the title never runs under the switch. The row's frame width is at least its fitting width at the larger inset (24 + indent + icon column + title + gap + switch + trailing), set when the title or the icon changes, so an inset change never needs a new width; the menu stretches the row to its own width. Bound: one label, one icon, one switch per row.
2. **State-column inset.** Invariant: on macOS 26 the row's content inset equals the x of AppKit's plain titles in the same menu (24 with a state column, 16 without). `StableMenu.update` computes `hasStateColumn` once per pass, before the item loop, from the entries of that pass (an entry counts when its `state != .off`, so `.mixed` counts) and gives it to each compact row, also to a row created in that pass; the row changes its constraint only when the value changes. Which entries count (all, standard rows only, or a constant 24) is taken from the Step 1 probe. Bound: one pass over the entries (about 20) per update.
3. **Stable menu (existing invariant, extended).** Identical polls replace no view and post no `NSMenu` notification, also for compact rows.
4. **Pending and rollback (existing logic, shared).** While the item is disabled after a click the switch keeps the requested position; the next enabled update shows the item's state.
5. **Icon size.** `StableMenu`'s image cache (`:73-80`) is keyed by symbol name and point size: 14 pt for standard and regular rows as today, 11 pt for compact rows (the size AppKit shows the 14 pt image at on a standard row). Invariant: one `NSImage` instance per name and size for the life of the menu, so the identity check in `updateStatus` (`SwitchMenuRow.swift:53`) holds across polls. Bound: two sizes times the symbol names in use (five today).

Not verified here: macOS 12–15 and 27 (no such Mac). The metrics are those of macOS 26; on older systems the two rows may sit 2–3 pt off the standard rows.

## Steps

### Step 1 — Core: compact switch row
**Executor:** `step-executor` (Sonnet).
Files: `Sources/LidAwakeCore/StableMenu.swift`, `Sources/LidAwakeCore/SwitchMenuRow.swift`, `Tests/LidAwakeCoreTests/SwitchMenuRowTests.swift`, `Tests/LidAwakeCoreTests/StableMenuTests.swift`.

1. **Probe first** (scratch only, nothing in the repo). The shipped app is stamped `minos 12.0, sdk 12.0` (`vtool -show-build`), so AppKit draws legacy-size controls for it; `swift test` links the current SDK and does not. Build a small probe the way SCRATCH `build.sh` does (`swiftc … -o p.unpatched`, `vtool -set-build-version macos 12.0 12.0 -replace -output p p.unpatched`, `codesign --force --sign - p`) and print: (a) `intrinsicContentSize` and `fittingSize` of an `NSSwitch` with `controlSize = .small`; (b) `NSMenu.size.width` for the same menu in three cases, all other items off: a standard item `.on` against `.off` (the control), and a view-backed item `.on` against `.off`. Apply: (a) if the intrinsic size is the drawn size (32×18 expected), size the switch by its intrinsic size as the regular row does; if not, pin the compact switch to the drawn size. (b) if the control does not change the width, this build always keeps the state column: the inset is a constant 24 and mechanism 2 is not built. If the control changes it and the view-backed item does too, `hasStateColumn` counts every entry; if only the control does, it counts `.standard` entries only. The report shows the probe output and the two choices.
2. Implement the design above.
3. Tests (follow the patterns at `SwitchMenuRowTests.swift:1-36` and `StableMenuTests.swift:22-28`; never assert a switch's pixel size, it depends on the linked SDK):
   - A `compactToggle` entry gets a `SwitchMenuRow` with the compact layout; `item.image` is `nil`; the switch has `controlSize == .small` and the title as accessibility label; state and enabled follow the entry.
   - Five identical polls: same view, zero `NSMenu` notifications.
   - Click: one action per click; while the item is disabled the switch keeps the requested position; an enabled update with the old state rolls it back, with the new state confirms it. A disabled row sends no action.
   - A row that stays disabled after its click (the "last condition off" path): click to off, a disabled update with state off, a later enabled update with state on → the switch shows on.
   - Layout, with the longest Russian title ("При питании от батареи") and a longer synthetic one: after layout the title ends at least 16 pt before the switch and the frame width is at least the fitting width; the row height is 24. The label and the icon are found by subview lookup, as `SwitchMenuRowTests.swift:24` does; no property changes its access level.
   - Inset (when mechanism 2 is built): 16 with no counted state, 24 with one `.on` or `.mixed`; it follows a later update in the same menu, and a row created in a pass gets that pass's value.
   - Icons: a compact row's image is the 11 pt instance and a standard row's the 14 pt one for the same symbol; both keep their identity across polls.
   - A style change for one id (`toggle` ↔ `compactToggle`) replaces the row with one of the right layout.
   - The three existing `SwitchMenuRowTests` and four `StableMenuTests` pass unchanged (the regular layout keeps one `NSImageView`).

Call sites of what changes:
- `MenuEntry.Style`: declaration `StableMenu.swift:4`, default `:19`, branch `:81`; uses `LidAwake.swift:297-299` (master, stays `.toggle`), `SwitchMenuRowTests.swift:13`. No exhaustive `switch` exists today.
- `SwitchMenuRow(`: `StableMenu.swift:85` only; the reuse cast at `:83` must also compare the layout. `updateStatus(subtitle:image:)`: `StableMenu.swift:89` only (the compact row uses the image, no subtitle).

**Acceptance:** `swift build` passes; `swift test --filter SwitchMenuRowTests` and `--filter StableMenuTests` pass with executed/skipped/failed counts shown; the probe output is in the report.

### Step 2 — App and docs: the two rows use the new style
**Executor:** `step-executor` (Sonnet).
- `LidAwake.swift:288-293`: the `item()` helper gains `style: MenuEntry.Style = .standard` and passes it on. `:306` (`ac`) and `:307` (`battery`) pass `.compactToggle`. Calls of `item(`: `:302, 305, 306, 307, 309, 311, 312, 314, 316, 317, 319`; only `:306` and `:307` change. No action handler changes: `toggleAC`, `toggleBattery`, `toggle(onAC:)` (`:337-345`) and the three `cancelTracking()` sites (`:353, :368, :424`) stay.
- Docs, wording for switches (on/off in place of checked/unchecked where the text means the two conditions) and the new behavior (the menu stays open on these two rows):
  - `README.md:9` (alt text of `docs/menu.png`: both conditions on), `:29-32`, `:35-37`. `:22` is about the display row and stays.
  - `docs/testing.md:34-36` (the conditions dim and keep their switch positions; the display row keeps its checkmark), `:39` (add the two condition switches: mouse, VoiceOver, the menu stays open, a click outside closes it), `:61-75` (the switch-rule check).
  - `docs/prompts/release-1.3-notes-draft.md:11-12` wording, plus one new line: changing "Connected to Power" or "On Battery" no longer closes the menu.

**Acceptance:** `./scripts/build-app.sh native` and `./scripts/check-build.sh native` pass; `swift test --filter StableMenuTests` passes with counts.

### Step 3 — full verification and render of the real rows
**Executor:** `step-executor` (Sonnet). No repo edits.
- `swift test` (full; counts), `LIDAWAKE_REAL_REGISTRY_TEST=1 swift test --filter testRegistryRead`, `./scripts/test-recovery.sh`, `./scripts/build-app.sh universal`, `./scripts/check-build.sh universal`.
- Render in SCRATCH (rebuild the harness if the folder is gone; SDK-12 patch as in Step 1): menus filled by the real `StableMenu` from a labeled copy of `updateMenu()`, states from the real `PolicyController` with a fake sleep, the real compact `SwitchMenuRow`s. `real-en.png` and `real-ru.png`, each with three panels: on with both conditions on; off after turning the last condition off; everything off (both conditions, External Display, Launch at Login) to show the 16 pt inset. Symbols at their natural size. The executor reads each PNG and compares it with column B2 of the approved sheets; it reports differences in points. If the sheets are gone, it compares with the metrics in this plan's Design section and, for the unchanged rows, with `docs/menu.png`.
- Traps for this step, from the earlier harness: screen capture is blocked; never launch the app or a GUI prototype; an offscreen `NSSwitch` draws grey unless the offscreen `NSWindow` subclass answers `@objc(hasKeyAppearance)` with `true`; set `autoresizesSubviews = false` on a panel whose rows have `autoresizingMask = [.width]`; standard rows are drawn by the harness, not by AppKit.

**Acceptance:** every command exits 0 with counts shown; both PNGs exist and match column B2 within about 2 pt, or the report lists what differs.

## Edge cases
- A click on the switch, the title or the icon of an enabled row toggles once; the menu stays open. A click on a disabled row does nothing.
- Turning the last condition off turns the master switch off in the open menu; both rows go off and disabled. Turning the master on with no condition turns both rows on.
- Enabling a condition while Sleep Setup is not ready closes the menu for the setup alert (`:353`, as the master switch today); after Cancel the switch is off again. After a successful setup the switch goes on, off, on while the menu is closed (`updateUI()` at `:205` runs before `afterSuccess` at `:209`); nobody sees it.
- A failed toggle rolls the switch back; the error alert closes the menu (`:424`).
- A second click while the first is in flight finds the row disabled and is ignored.
- The 2-second poll while the menu is open replaces nothing.
- No state column in the menu: inset 16. Long titles widen the menu; nothing clips.
- External Display, Launch at Login, `⌘E`, `⌘L`, `⌘Q`: unchanged.

## Review
Per-step codex round after Step 1 and after Step 2 (pinned; correctness and requirement gaps only). After the owner's device pass and the screenshot commit: one whole-range codex challenge on `34f22af..HEAD` plus `spec-reviewer`, then the fix loop until zero P0/P1. If a fix changes the rows after the device pass, the owner checks that behavior again.

## Verification that needs a person
**Owner device pass (after Step 3, before the whole-range review; about 5 minutes).** Install with `./build.sh` (quit the running copy first). Check, in English or Russian:
1. Toggle "Connected to Power" and "On Battery" by a click on the switch and on the title: the menu stays open; a click outside or Esc closes it.
2. The switch rule in the open menu: last condition off → master off, both rows dimmed; master on → both on.
3. External Display and Launch at Login behave as before; `⌘E` and `⌘L` work.
4. Alignment of the two rows under "Keep awake when:" in three states: as installed; master on with External Display and Launch at Login both off (the state where the inset rule matters most, and which no render can show); everything off. When the last checkmark or switch goes off in the open menu, the two rows and AppKit's own titles move together or not at all.
5. VoiceOver reads the two switches with title and state.
6. Quit and relaunch: the states are kept.
Then capture `docs/menu.png` again (Cmd+Shift+4, Space, click the menu) in the state of today's screenshot: on battery, master on, both conditions on, External Display and Launch at Login checked. The README alt text (`README.md:9`) from Step 2 describes that state. The master commits the file.

## After the gate (master, docs only)
Tick Arc A in `docs/prompts/release-1.3-next-session.md` and update its state section and traps (the SDK-12 stamp and the harness patch); delete the index line in `docs/tech-debt.md` and `docs/todos/menu-rows-stay-open.md`; set the test count in the notes draft (`:27`) to the Step 3 count. Nothing is pushed in this arc.

## Decision (owner, 2026-11-13, at the plan gate)
**Keyboard on the two rows: mouse and VoiceOver only, as the master switch row.** Standard rows react to the arrow keys and Return; view-backed rows do not. The owner accepted that keyboard-only users (arrow keys without VoiceOver) can no longer reach these two rows. Not chosen: arrow keys with Return/Space (needs a selection highlight that also shows on hover, and an `NSMenu` subclass); key equivalents shown in a tooltip. A review finding about this loss is a recorded product decision, not a defect to fix.

Plan review: one `plan-reviewer` pass, 2 blocking findings (the source of the 11 pt icon; a control case for the state-column probe and a device check for the state no render shows) and 8 advisory ones, all folded in.

## Assumptions
- A disabled row dims its icon with its title.
- The two rows get no tooltip.
- The device pass comes before the whole-range review, so the new screenshot is inside the reviewed range.

## Addendum (2026-11-13): findings before and at the device pass

1. **Truncated titles (Step 3 render, fixed in `27430a6`).** The compact title was framed to the bare string width; the text field's cell needs 4 pt more and draws 2 pt inside its frame. A private cell for the compact title removes that inset.
2. **The menu flashes on a small-switch toggle (owner, device pass on `27430a6`: "it blinks when i toggle small ones"; asked what blinks: "The whole menu flashes").** Cause, from a code trace (nobody here can see the screen): `perform(showFailure: true)` raises `pendingUserOperations` and calls `updateUI()` at once (`LidAwake.swift:191-194`); `controlsEnabled` (`:286`) then disables seven rows (master, `ac`, `battery`, `external`, `setup`, `uninstall-app`, `login`) until the completion enables them again. For a condition of the inactive power source no sleep write happens, so the pair lands within a frame or two. Before this arc the menu closed on the click and hid it. Excluded by the trace: frame or width writes on a toggle, a menu relayout call, a knob that jumps back.
   **Decision (owner): never dim for a running operation.** Not chosen: dim only when the operation lasts longer than about 0.3 s; leave as is. Accepted cost: a rare slow or stuck operation shows no busy look until it ends or reports an error.
   Invariants for the fix:
   - A running user operation changes no row's look. Rows dim only for states: master off, `gate.locksMenuActions`, `terminating`, `checkingUpdates`.
   - While an operation runs, a click or key equivalent on a row that starts or needs an idle operation is ignored: no second operation, no alert.
   - A switch row keeps the requested position until the operation ends, then shows the item's state (the new state on success, the old one on failure or a rejected click). The in-flight signal is no longer `item.isEnabled`. This replaces mechanism 4 for both layouts.
   - Stable menu: identical polls replace no view and post no `NSMenu` notification.
   The owner checks the menu again before the whole-range review.
