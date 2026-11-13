# Localize the texts that are still English only

What: three groups of user-visible text have no Russian. Arc C of release 1.3 moved only the app's own texts to `Localization/Localizable.xcstrings`; the owner deferred these on 2026-11-13 ("Leave English, defer").

1. **Core's error texts.** About 40 `ControlError.message` texts in `Sources/LidAwakeCore` (`Commands.swift`, `GitHubUpdates.swift`, `RecoveryFiles.swift`, `LoginItems.swift`, `SleepControl.swift`, `SleepWorker.swift`, `PrivilegeSetup.swift`), plus "Authorization was canceled." They reach the user through `localizedDescription`: the error alert (`showError`), the status-item tooltip and the "Sleep setting needs attention…" alert (`state.error`), the quit-restore alert, the update-check alert, and the uninstall failure texts, which append them to a localized prefix.
2. **Four `echo … >&2` lines of the admin shell scripts** in `PrivilegeSetup.swift`. They come back as the AppleScript error message.
3. **`NSAppleEventsUsageDescription`** in `Info.plist`. macOS shows it in the Automation consent dialog. It needs an `InfoPlist` strings table (`InfoPlist.xcstrings`, compiled the same way).

Why: a Russian user reads Russian menus and alerts, but any failure text is English.

Context:
- The design choice is open: Core gets a catalog of its own, or Core's errors carry a key and values and the app's catalog translates them. Core has no bundle in the script build (`scripts/build-app.sh` copies the binary only), which favors keys passed to the app.
- Some Core texts quote menu titles ("Repair Sleep Setup", "Sleep Setup", "Launch at Login"). Their Russian must match the Russian menu titles in the catalog.
- The sleep worker is the same binary and sends its error text to the app as a string (`SleepWorker.swift`, `WorkerReply.error`). A text translated in the worker uses the worker's language; a key sent across is safer.
- Texts that are system or command output (stderr of a command, an AppleScript error message of the system) cannot be put in a catalog.
- About 44 new Russian texts must be written and the owner must review them. `scripts/check-strings.sh` reads one source file today and allows only `%@`; it must grow with this work (some Core texts carry numbers).

Depends: nothing. Effort: medium; its own arc with its own plan.
