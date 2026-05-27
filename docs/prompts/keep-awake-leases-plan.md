# Keep-Awake Leases — plan

## Goal / user story

> I run coding CLIs (Claude Code today; codex/aider/etc. later) in a few terminal tabs,
> close the lid, and walk away. While any of them is **actively working**, the Mac stays
> awake. When the **last** one finishes and everything is idle, the Mac is allowed to
> sleep again — so it isn't burning power with the lid closed and no work happening.

LidAwake already keeps the Mac awake on lid close via the global `pmset disablesleep`
parameter, with a per-power-source policy. This feature adds **temporary, auto-expiring
"keep awake" leases** layered on top of that policy.

## Why leases (and why one coordinator)

- Lid-close sleep is governed by `pmset disablesleep` — a single **global boolean**, not a
  ref-counted assertion stack. `caffeinate` does **not** affect it (only idle sleep).
- Therefore "stay awake while ≥1 job is working" needs a coordinator that ref-counts who
  wants to be awake and flips the global boolean only on 0↔1 transitions.
- **LidAwake is the single owner/writer** of `disablesleep` (it already holds the scoped
  passwordless sudoers rule). No other tool ever writes the param — they only acquire/
  release leases. This avoids races and a second writer.

Reconciliation rule, evaluated on the existing 2-second `lidTick`:

```
keepAwake = policyForCurrentSource (awakeOnAC / awakeOnBattery)  ||  activeLeaseCount > 0
```

- 0 → restore the user's policy (typically sleep allowed). If the lid is closed at that
  moment, optionally `pmset sleepnow` so it sleeps immediately instead of waiting for idle.
- The manual per-source policy is the baseline; leases are additive temporary overrides.

## Lease store & format

- Directory: `~/.lidawake/leases/` (user-owned, no root needed by clients).
- One file per lease, named by a unique key. Contents (single line or small JSON):
  - `key` (e.g. Claude `session_id`)
  - `pid` — the resolved owning process (see reaping)
  - `created` / `refreshed` epoch timestamp
  - `source` — which tool created it (e.g. `claude-code`) for the status UI.

## Reaping (must never strand the Mac awake)

A lease is removed when any of:
1. **Clean release** — the tool's "work finished" hook deletes it (Claude `Stop` / `SessionEnd`).
2. **Dead owner** — coordinator checks `kill -0 pid`; if the owning process is gone, reap.
   - Because Claude's hook `$PPID` is **not guaranteed** to be the `claude` process, the
     acquire step resolves the real owner by walking the parent chain (getppid → …) until
     it finds the `claude` process, and stores that PID. (Detail to verify locally.)
3. **Staleness backstop** — if a lease's `refreshed` is older than N minutes and the PID
   check is inconclusive, reap. (Last-resort safety; PID liveness is the primary signal.)

## Acquire / release mechanism — reuse the LidAwake binary (no extra deps)

Make the `LidAwake` binary **dual-mode**:

- No args → the GUI menu-bar app (today's behavior, also the coordinator).
- `LidAwake lease acquire` / `LidAwake lease release` → CLI mode: read the hook's JSON from
  stdin, parse `session_id` (Swift `JSONDecoder`), resolve the owning PID, write/remove the
  lease file, **always exit 0**, never launch the GUI.

Why: single artifact, no `jq`/`python` dependency, full JSON parsing + PID resolution in
Swift, and the hook just points at the installed binary's absolute path.

## Claude Code integration (v1) — via global hooks

Installed into `~/.claude/settings.json` (user-global; applies to all sessions; reloads
live, no restart). Confirmed against current docs:

- `UserPromptSubmit` → `acquire` (a turn started). **30s timeout, blocks the turn** → keep it instant.
- `Stop` → `release` (turn finished, idle at prompt — the exact "work done" signal).
- `SessionEnd` → `release` (cleanup if the CLI closes mid-turn).

Hook entry shape (command points at the installed app binary):

```json
{
  "hooks": {
    "UserPromptSubmit": [{ "matcher": "", "hooks": [{ "type": "command",
      "command": "/Applications/LidAwake.app/Contents/MacOS/LidAwake lease acquire" }]}],
    "Stop":             [{ "matcher": "", "hooks": [{ "type": "command",
      "command": "/Applications/LidAwake.app/Contents/MacOS/LidAwake lease release" }]}],
    "SessionEnd":       [{ "matcher": "", "hooks": [{ "type": "command",
      "command": "/Applications/LidAwake.app/Contents/MacOS/LidAwake lease release" }]}]
  }
}
```

Lease keyed by `session_id` so acquire/release match within a session.

## The wizard / explicit consent (required)

Never touch `~/.claude/settings.json` silently. Flow:

- A menu entry, e.g. **"Integrations…"** → **"Set Up Claude Code…"** (auto-shown/enabled
  only when `~/.claude` exists).
- Opens a small window/alert that:
  - explains what it does (keep awake while Claude works; sleep when idle),
  - shows **exactly the JSON that will be added** (preview/diff),
  - has **Install** and **Cancel**, and once installed, **Remove**.
- Install = **idempotent safe merge** into the existing `hooks` object (never clobber the
  user's other hooks; detect already-installed to drive the toggle state). Resolve the
  running app's absolute path for the command (don't hardcode if not in /Applications).
- Remove = pull out only our entries, leave everything else intact.
- Reflect status in the menu (installed / not installed).

## Extensibility (Claude now, more later) — keep it light

Model integrations as a small list, not a plugin system:

```
struct Integration { name; detect()->Bool; isInstalled()->Bool; install(); remove() }
let integrations = [claudeCode]   // add codex, aider, … later
```

The **coordinator + lease store + `LidAwake lease` CLI are already tool-agnostic.** Per-tool
work is only: detection + how to install its hooks (or a `lidawake-keep`-style wrapper for
tools without hooks). The "Integrations" submenu iterates this list. Shells / `claude -p` /
builds can use a documented one-line `trap` snippet or a wrapper later.

## Menu / UI changes

- Status line includes active lease count, e.g. *"On AC · staying awake · 2 active jobs"*.
- Icon already flips moon↔cup based on live `disablesleep`; leases drive that automatically.
- New "Integrations" submenu with the Claude Code install/remove toggle.

## MVP scope (this feature) vs later

**MVP (build now):**
1. Coordinator: watch `~/.lidawake/leases/`, reap (dead PID + staleness), reconcile on the 2s tick.
2. `LidAwake lease acquire|release` CLI mode (stdin JSON → lease file, PID resolution, exit 0).
3. Claude Code hook installer wizard (merge/remove in `~/.claude/settings.json`, with preview + consent).
4. Status-line lease count.

**Later:**
- Additional tools (codex/aider) + generic `lidawake-keep` wrapper + shell `trap` snippet.
- Manual "keep awake until I stop" lease (menu/CLI) for multi-turn holds.
- `pmset sleepnow` on last-release-while-lid-closed (decide; see open questions).

## Open questions / to confirm

1. **PID resolution** — verify locally that walking getppid() from the hook reliably reaches
   the `claude` process; pick the staleness timeout (e.g. 5 min) as backstop.
2. **Sleep immediately vs. let it idle** — on last release with the lid closed, do we
   `pmset sleepnow`, or just set `disablesleep 0` and let macOS sleep on its own? (Leaning
   "let it sleep naturally" for v1; simpler, less surprising.)
3. **App path in hooks** — require /Applications, or write the resolved running path and
   re-point on move? (Re-point on next launch if the stored path is stale.)
4. **Interaction with manual policy** — if user policy already = always awake on this
   source, leases are no-ops (already awake). Confirmed fine; just don't sleep on release
   while policy says stay awake.

## Testing plan

- Unit-ish: acquire then release a lease by hand → `disablesleep` flips 1→…→0; icon/status update.
- Crash: acquire a lease, `kill -9` the owner → coordinator reaps within a couple ticks → sleeps.
- Real Claude: install hooks, run an interactive turn with lid closed → stays awake during
  the turn (incl. thinking), sleeps shortly after `Stop`. Two tabs → sleeps only after both finish.
- Wizard: install → verify `~/.claude/settings.json` merged without disturbing existing keys;
  remove → verify only our entries gone.
