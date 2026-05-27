# LidAwake

A tiny macOS menu bar app to toggle whether your MacBook sleeps when you close the lid.
Under the hood it flips `pmset -c disablesleep` between `0` (sleep normally) and `1`
(stay awake when the lid is closed).

- 🌙 `moon.zzz` — normal sleep behavior
- ☕ `cup.and.saucer.fill` — stays awake when the lid is closed

## Build

Compile the single source file:

```sh
swiftc LidAwake.swift -o LidAwake -framework Cocoa
./LidAwake          # icon appears in the menu bar
```

Or build the full `.app` bundle and install it:

```sh
./build.sh          # compiles, bundles, and copies to /Applications (asks before overwriting)
```

The menu has:

- a status line showing the current state,
- **Toggle** (`⌘T`),
- **Refresh** (`⌘R`),
- **Launch at Login** (`⌘L`) — a checkmark item to add/remove the app from Login Items,
- **Quit** (`⌘Q`).

Changing the setting prompts for your admin password (macOS requires root for `pmset`).

## Launch at login

Use the in-app **Launch at Login** menu item (`⌘L`) to toggle it. The first time, macOS
asks to allow LidAwake to control System Events — approve it. There's no Dock icon
(`LSUIElement`), so it just lives in the menu bar and starts hidden.

You can also set it manually: System Settings → General → Login Items → `+` → select
`/Applications/LidAwake.app`.

## Skip the password prompt (optional)

By default each toggle asks for your admin password. To allow `pmset -c disablesleep`
to run without one, add a sudoers rule. Edit safely with `sudo visudo` and add:

```
your_username ALL=(root) NOPASSWD: /usr/bin/pmset -c disablesleep *
```

Replace `your_username` with the output of `whoami`. This grants passwordless `sudo`
*only* for that exact `pmset` subcommand.

> Note: the app currently elevates via AppleScript's `with administrator privileges`,
> which always prompts. The sudoers rule is provided for those who'd rather change
> `toggle()` to shell out via `sudo` and skip the dialog.
