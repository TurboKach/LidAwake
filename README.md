# LidAwake

**Close your MacBook lid and keep working.** LidAwake is a tiny macOS menu bar app
that stops your Mac from sleeping when you shut the lid — so long-running terminal
jobs and AI coding agents like **Claude Code**, **OpenAI Codex CLI**, **Gemini CLI**,
and **Aider** keep running while the laptop is closed. No external display required.

## The problem

You kick off a long task in your terminal — an AI coding agent grinding through a
refactor, a test suite, a build, a big download, a local dev server — then you want to
close your MacBook and walk away from the desk. By default macOS **sleeps the instant
you close the lid**, so everything halts mid-run. The usual fix is clamshell mode: plug
in an external monitor, keyboard, and power. But you don't always have a monitor nearby,
and you shouldn't need one just to let a job finish.

## The solution

LidAwake lets you **close the lid without sleeping** — with nothing plugged in but power
(or not even that, your call). Flip it on and your Mac keeps running lid-shut: your coding
agent finishes the task, your build completes, your server stays up. Flip it off to get
normal sleep-on-close back.

It also turns the **internal screen off** while the lid is closed — so you're not burning
power lighting a panel nobody can see — and stays out of the way of real clamshell mode
when an external display is connected.

If you've used **Amphetamine** or **Caffeine** to keep a Mac awake, LidAwake is the
focused, closed-lid version: one menu, lid-close sleep only, per-power-source policies.

## How it works

Under the hood LidAwake manages a single macOS setting, `pmset disablesleep`
(`0` = sleep normally on lid close, `1` = stay awake). Because that's one live,
system-wide value — not something macOS stores per power source — LidAwake watches for
plug/unplug events and automatically applies the policy you chose for whichever source
is currently active.

When a stay-awake policy keeps the Mac running with the lid closed and **no external
display** is attached, LidAwake detects the closed lid and runs `pmset displaysleepnow`
to switch the internal panel off while the Mac keeps working. With an external display
attached it does nothing, so normal clamshell mode (external monitor stays on) is preserved.

The menu bar icon shows the current state at a glance:

- 🌙 `moon.zzz` — sleeps on lid close
- ☕ `cup.and.saucer.fill` — stays awake on lid close

## What you can configure

- **Stay Awake on AC Power** — keep running lid-closed while plugged in.
- **Stay Awake on Battery** — same, but while on battery (an independent toggle).
- **Launch at Login** (`⌘L`) — start hidden in the menu bar at every login.

Each power source has its own policy, so you can — for example — stay awake only while
plugged in and sleep normally on battery. Toggling a source's policy takes effect
immediately if that source is active, otherwise the next time you switch to it. The menu
also shows a live status line (e.g. *“On battery · sleeps on lid close”*) and re-reads the
real system state whenever you open it or the power source changes.

> [!NOTE]
> Keeping a Mac awake with the lid closed inside a bag can get warm and drain the battery.
> Keep it ventilated, and prefer the AC-only policy if you're not sure.

Requires macOS 12 or later.

## Install (from a release)

1. Download `LidAwake.dmg` from the [Releases](../../releases) page and open it.
2. Drag **LidAwake** onto the **Applications** folder.
3. The app is not signed with an Apple Developer ID, so the first launch is blocked
   by Gatekeeper. To allow it:
   - Double-click `/Applications/LidAwake.app`. macOS shows *“Apple could not verify
     LidAwake is free of malware.”* Click **Done** — **not** *Move to Trash*.
   - Open **System Settings → Privacy & Security** and scroll down. A line now reads
     *“LidAwake was blocked…”* with an **Open Anyway** button — click it and confirm.
     (On macOS 15+ this button lives in System Settings, not in the first dialog.)

   Or, from Terminal, clear the quarantine flag in one step — no System Settings trip:

   ```sh
   xattr -dr com.apple.quarantine /Applications/LidAwake.app
   open /Applications/LidAwake.app
   ```

## First launch

On first run LidAwake asks once for admin approval and installs a **scoped** passwordless
rule at `/etc/sudoers.d/lidawake` (limited to `pmset … disablesleep`, validated with
`visudo` before install). After that it changes the setting silently — no more password
prompts, including automatic AC↔battery switching.

If you click **Not Now**, the app still works, but it falls back to asking for your
password each time it needs to change the setting (and won't auto-switch unprompted).

## Launch at login

Use the in-app **Launch at Login** menu item (`⌘L`). The first time, macOS asks to allow
LidAwake to control System Events — approve it. There's no Dock icon (`LSUIElement`), so
it lives only in the menu bar and starts hidden. You can also set it manually:
System Settings → General → Login Items → `+` → `/Applications/LidAwake.app`.

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

## Removing the passwordless rule

```sh
sudo rm /etc/sudoers.d/lidawake
```
