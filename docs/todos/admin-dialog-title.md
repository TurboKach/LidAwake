# The admin password dialog's title says "osascript"

What: the dialog that asks for the admin password shows LidAwake's own sentence since 1.3.0, but its bold title is still "osascript" and the icon is a generic lock. Own arc in 1.3.1.

Why (owner's device pass on 1.3.0, 2026-11-13): the title is the name of the process that asks for authorization. `PrivilegeSetup.install()` and `uninstall()` (`Sources/LidAwakeCore/PrivilegeSetup.swift:43`, `:60`) start `/usr/bin/osascript` through `runner.run(..., timeout: 120)`.

Direction (the owner approved pursuing it; the design is for that arc's plan): run the script inside the app, so macOS names LidAwake. Expected, not yet seen on a real dialog.

Facts the plan needs:
- The seam is the two `runner.run("/usr/bin/osascript", ...)` calls (`PrivilegeSetup.swift:44`, `:61`).
- `CommandRunning` (`Sources/LidAwakeCore/Commands.swift:25`) is shared with `LoginItems` (`LoginItems.swift:46`, osascript with a 20 s timeout), which must stay as it is.
- A cancel is detected today in `ProcessCommandRunner` by `(-128)` in stderr (`Commands.swift:75`) and thrown as `ControlError.canceled`. A replacement must map the cancel itself.
- Today's 120 s timeout terminates a stuck osascript (`Commands.swift:64-71`). An in-app script has no such kill.
- The app calls these from `perform { }` on a serial work queue (`LidAwake.swift:182`). The thread rules of the in-app scripting API must be checked.
- `Tests/LidAwakeCoreTests/SystemAdaptersTests.swift` pins the osascript path and arguments (`:255-258`, `:270`).

Verification that needs the owner: Sleep Setup and uninstall with a real password, on a real dialog.

Depends: nothing. Effort: medium. Own arc, with its own plan.

Update 2026-11-13: the owner later chose one release with everything. This item is built before the 1.3.0 release, not in a 1.3.1; see `docs/prompts/release-1.3-next-session.md`.
