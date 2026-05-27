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
