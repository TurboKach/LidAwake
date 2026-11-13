LidAwake 1.3.0 works on macOS 27, fixes a master switch that could be on while doing nothing, and adds an in-app uninstall.

### What's new

- **macOS 27 support.** On macOS 27, `pmset -g` no longer prints the `SleepDisabled` line, so 1.2.0 could never turn keep-awake on ([issue #1](https://github.com/TurboKach/LidAwake/issues/1), reported by KarimElBerniUNIBO). LidAwake now reads the value from the `IOPMrootDomain` registry entry when `pmset -g` leaves it out, in the app and in the uninstall script. A failed read is still an error and is never treated as "sleep enabled". The fix comes from [pull request #3](https://github.com/TurboKach/LidAwake/pull/3) by Fuadeiza; [pull request #2](https://github.com/TurboKach/LidAwake/pull/2) by Matte1404 proposed the same registry fallback. Both contributors reported their fix working on macOS 27.0.1. I could not test macOS 27 myself, so reports from macOS 27 are welcome.
- **“Uninstall LidAwake…”** in the menu restores sleep, removes the sleep rules after one admin prompt, turns off Launch at Login, deletes the settings, moves the app to the Trash, and quits.
- **Clearer admin dialogs.** The password dialogs for Sleep Setup and for uninstall now say in LidAwake's own words, in English or Russian, what the password is for, instead of “osascript wants to make changes”. The dialog is still titled “osascript”; that changes in a later release.

### Changed behavior

- **Connected to Power** and **On Battery** are now switches, and changing them no longer closes the menu; click outside it to close it.
- The LidAwake switch is on only while at least one **Keep awake when** condition is on. Switching off the last condition turns the switch off, and turning the switch on with none on switches both on.
- A fresh install starts with the switch off and both conditions on. A setup that keeps your Mac awake today is not changed by the upgrade.
- The “LidAwake on GitHub” menu row is gone; **About LidAwake** already shows the repository link.

### Reliability improvements

- Quitting and uninstalling are more robust: Quit waits for a running uninstall, the app quits at once after a successful uninstall, and the sleep worker has exited before a new session takes over.
- The sleep rule is checked in both directions before sleep is changed, and sleep is never set to normal while it is held disabled.
- The recovery journal is saved before the rule check can disable sleep.

### Download and installation

Download **LidAwake.dmg**, quit the running copy of LidAwake, and drag the app into **Applications** to replace it. Open the updated app and complete Sleep Setup if prompted.

The app supports **macOS 12 or later**, on **Apple Silicon and Intel**. It is ad-hoc signed and is not notarized; if macOS blocks the download, use **System Settings → Privacy & Security → Open Anyway**.

Validated with 111 regression tests, process-crash recovery checks, and a universal build with verified macOS 12 deployment targets. The macOS 27 read is covered by unit tests and by confirmation from its contributors; reports from macOS 27 are welcome.

Developed by [TurboKach](https://github.com/TurboKach).
