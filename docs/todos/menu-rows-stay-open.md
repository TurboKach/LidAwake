# Keep the menu open on condition clicks

What: clicking the master switch keeps the menu open, but checking or unchecking "Connected to Power" or "On Battery" closes it. The owner wants the menu to stay open until a click outside. Own arc in 1.3.1.

Why (owner's device pass on 1.3.0, 2026-11-13): changing both conditions today takes two menu openings.

Cause:
- The switch row is a custom view (`Sources/LidAwakeCore/SwitchMenuRow.swift`, attached in `Sources/LidAwakeCore/StableMenu.swift:81` for `.toggle` entries). It sends its action itself (`SwitchMenuRow.swift`, `switchChanged`), so AppKit does not run the standard item-selection path.
- The condition rows are standard `NSMenuItem`s built by the `item()` helper in `updateMenu()` (`LidAwake.swift:288`). AppKit closes the menu on a standard item click.

What the work needs: custom-view rows for the checkable settings. A custom view gets nothing for free: checkmark column and indent alignment with standard rows, icon, disabled look, hover highlight, arrow-key selection, Space/Return, VoiceOver role and value.

What `SwitchMenuRow` has and lacks (from the code):
- Has: title label, subtitle label, status icon, a native `NSSwitch`; the switch is enabled or disabled with the item, its state follows the item, and its accessibility label is the item title; the label is greyed when disabled; a tooltip with the title and the key equivalent; a click on the title area (top 34 points) calls `toggle.performClick`.
- Lacks (no code for it): a hover or selection highlight, a checkmark column, indentation, arrow-key or Space/Return handling of its own, and an accessibility role or value set by hand (it relies on `NSSwitch`'s own).

Paths that must still close the menu: `promptSetup` and `showError` in `LidAwake.swift` (`:352`, `:423`) call `statusItem.menu?.cancelTracking()` before their alert; `uninstallApp` (`:367`) does the same.

Open decisions for that arc's plan:
- Which rows stay open: the two conditions; "Turn Off External Display on Lid Close"; "Launch at Login", whose action can raise a system prompt.
- How the rows look. The owner wants rendered options before choosing.
- `MenuEntry.Style` has two cases today (`standard`, `toggle`, `StableMenu.swift:4`); a third case or a new view is part of the design.

Verification: a second device pass by the owner (hover, keyboard, VoiceOver, Reduce Motion are not covered by unit tests).

Depends: nothing. Effort: medium. Own arc, with its own plan.
