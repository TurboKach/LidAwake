# LidAwake — Ideas / TODO

## Auto-off when watched processes finish

Let LidAwake stay awake only as long as specific work is running, then turn
itself off automatically.

**Behavior:**
- Keep a user-defined list of apps/processes to watch (e.g. `ffmpeg`, `Xcode`,
  a backup job, a long-running script).
- When at least one watched process is running, ensure `disablesleep 1`.
- Once **all** watched processes have finished, toggle `disablesleep 0` so the
  Mac can sleep normally again.

**Open design questions:**
- *How does a process "explicitly tell" it's finished?* Options:
  - Poll by process name / PID (`pgrep`) — simple, no cooperation needed, but
    can't distinguish "idle but open" (e.g. Xcode left open) from "working".
  - Explicit signal: processes opt in via a small file/socket/notification
    ("I'm starting" / "I'm done"). More precise, but requires the watched tool
    to cooperate.
  - Hybrid: poll by name for non-cooperating apps, accept explicit signals for
    cooperating ones.
- How is the watch list configured? Menu UI vs. a config file (e.g.
  `~/.config/lidawake/watch.json`).
- What if the user manually toggles off mid-watch — does auto-management pause?
- Should it only re-enable sleep, or also notify ("All jobs done — sleep
  re-enabled")?

**Sketch (polling approach):**
- Add a `Timer` that periodically runs `pgrep -x <name>` for each watched item.
- Track transition from "≥1 running" → "0 running" and trigger the off-toggle
  on that edge only (avoid repeatedly toggling).
- Surface watched processes + live status in the menu.

## ✅ Per-power-source behavior (AC vs. battery) — DONE

Implemented: independent AC/battery policies in the menu, IOKit power-source
monitoring with automatic switching, and a one-time passwordless setup so it
applies silently. Notes below kept for context.

Let the lid-close-awake behavior differ depending on whether the Mac is on
charger or on battery, so e.g. it stays awake when plugged in but always
sleeps on battery (to protect battery life / avoid a hot bag).

**Behavior:**
- Independent settings for AC and battery, e.g. each can be:
  *stay awake on lid close* / *sleep normally* / *follow the other* .
- React to power-source changes at runtime: when the user unplugs/plugs in,
  apply that source's configured policy automatically.
- Reflect the active source + its policy in the menu.

**Implementation notes:**
- `pmset` already separates sources: `-c` = AC/charger, `-b` = battery,
  `-a` = all. Today the app only writes `-c disablesleep`, so battery is
  untouched. To honor a battery policy, write `-b disablesleep <0|1>` too.
- Detect the current source and live changes via `IOPSNotificationCreateRunLoopSource`
  / `IOPSCopyPowerSourcesInfo` (IOKit), or poll `pmset -g batt`.
- Read state per source from `pmset -g` accordingly (note: `SleepDisabled` is a
  single live value, not per-source — the per-source config is what *we* store
  and apply, then push to `pmset` on source change).

**Open questions:**
- Where to persist config (a small JSON in `~/.config/lidawake/`, or
  `UserDefaults`).
- On battery, should an in-progress "stay awake" (e.g. from the watched-process
  feature above) win, or should battery policy always force sleep?
