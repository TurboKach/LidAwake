# LidAwake

**Close your MacBook lid and keep working.** A tiny macOS menu bar app that stops your
Mac from sleeping on lid close — so **Claude Code**, **Codex**, builds, downloads, and
other long-running terminal jobs keep running with the laptop shut. No external display needed.

A focused, closed-lid alternative to **Amphetamine** / **Caffeine**.

## Why

- macOS sleeps the instant you close the lid → your task dies mid-run.
- Clamshell mode needs an external monitor + keyboard you don't always have.
- LidAwake keeps the Mac awake lid-closed *and* switches the internal screen off, so nothing's wasted.

## Features

- ☕ / 🌙 **menu bar toggle** — stay awake vs. sleep on lid close, at a glance.
- **Per power source** — independent AC and battery policies; auto-applied on plug/unplug.
- **Screen off when closed** — blanks the internal panel on lid close, and the external monitor too (uncheck the toggle to keep clamshell mode and leave the external on).
- **Launch at Login** (`⌘L`) — starts hidden in the menu bar.
- Live status line, e.g. *“On battery · sleeps on lid close”*.

## How it works

Toggles `pmset disablesleep` (`0` = sleep, `1` = stay awake) — one live, system-wide
value, so LidAwake watches power changes and applies your per-source policy itself. On lid
close it runs `pmset displaysleepnow` to blank the internal screen — and the external one
too, unless you keep clamshell mode on. Requires **macOS 12+**.

> [!NOTE]
> Keeping a Mac awake lid-closed in a bag can get warm and drain the battery. Keep it
> ventilated; prefer AC-only if unsure.

## Install

1. Download `LidAwake.dmg` from [Releases](../../releases), open it, drag **LidAwake** → **Applications**.
2. It's unsigned, so the first launch is Gatekeeper-blocked. Either:
   - Open it → click **Done** (*not* Move to Trash) → **System Settings → Privacy & Security → Open Anyway**, or
   - run `xattr -dr com.apple.quarantine /Applications/LidAwake.app`

**First run** installs a scoped passwordless rule at `/etc/sudoers.d/lidawake` (limited to
`pmset … disablesleep`, validated with `visudo`) so it can switch silently. Click *Not Now*
to skip and it'll ask for your password each time instead. Remove later with
`sudo rm /etc/sudoers.d/lidawake`.

## Build

```sh
./build.sh     # compile + bundle + install to /Applications
./release.sh   # universal (arm64 + Intel) LidAwake.dmg for distribution
```
