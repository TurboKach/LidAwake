# LidAwake

A tiny macOS menu bar app that controls whether your MacBook sleeps when you close
the lid — with **independent settings for AC power and battery**. Under the hood it
manages `pmset disablesleep` (`0` = sleep normally, `1` = stay awake on lid close).

- 🌙 `moon.zzz` — currently sleeps on lid close
- ☕ `cup.and.saucer.fill` — currently stays awake on lid close

Because `disablesleep` is a single live system value (not stored per power source),
LidAwake watches for plug/unplug events and applies the right setting itself.

When a stay-awake policy keeps the Mac running with the lid closed and **no external
display** is attached, `disablesleep` would otherwise leave the internal panel powered.
LidAwake detects the closed lid and runs `pmset displaysleepnow` to turn the screen off
while the Mac keeps running. With an external display attached it does nothing, so normal
clamshell mode (external stays on) is preserved.

Requires macOS 12 or later.

## Install (from a release)

1. Download `LidAwake.dmg` from the [Releases](../../releases) page and open it.
2. Drag **LidAwake** onto the **Applications** folder.
3. The app is not signed with an Apple Developer ID, so the first launch is blocked
   by Gatekeeper. To allow it:
   - **Open** `/Applications/LidAwake.app` — macOS says it can't verify the developer.
   - Go to **System Settings → Privacy & Security**, scroll to the LidAwake notice,
     and click **Open Anyway**, then confirm.

   Or, from Terminal, clear the quarantine flag in one step:

   ```sh
   xattr -dr com.apple.quarantine /Applications/LidAwake.app
   open /Applications/LidAwake.app
   ```

## Build from source

```sh
swiftc LidAwake.swift -o LidAwake -framework Cocoa -framework IOKit
./LidAwake          # icon appears in the menu bar
```

Or build the full `.app` bundle and install it:

```sh
./build.sh          # compiles, bundles, and copies to /Applications (asks before overwriting)
```

To produce a distributable universal DMG (arm64 + Intel, ad-hoc signed):

```sh
./release.sh        # builds LidAwake.dmg with a drag-to-Applications layout
```

## First launch

On first run LidAwake asks once for admin approval and installs a **scoped** passwordless
rule at `/etc/sudoers.d/lidawake` (limited to `pmset … disablesleep`, validated with
`visudo` before install). After that it changes the setting silently — no more password
prompts, including automatic AC↔battery switching.

If you click **Not Now**, the app still works, but it falls back to asking for your
password each time it needs to change the setting (and won't auto-switch unprompted).

## The menu

- **Status line** — current power source and effective state, e.g. *“On battery · sleeps on lid close”*.
- **Stay Awake on AC Power** — checkmark; policy used while plugged in.
- **Stay Awake on Battery** — checkmark; policy used while on battery.
- **Launch at Login** (`⌘L`) — add/remove the app from Login Items.
- **Quit** (`⌘Q`).

Toggling a source's policy applies immediately if that source is active; otherwise it
takes effect the next time you switch to that source. The display re-reads live state
whenever you open the menu and whenever the power source changes, so there's no manual
refresh.

## Launch at login

Use the in-app **Launch at Login** menu item (`⌘L`). The first time, macOS asks to allow
LidAwake to control System Events — approve it. There's no Dock icon (`LSUIElement`), so
it lives only in the menu bar and starts hidden. You can also set it manually:
System Settings → General → Login Items → `+` → `/Applications/LidAwake.app`.

## Removing the passwordless rule

```sh
sudo rm /etc/sudoers.d/lidawake
```
