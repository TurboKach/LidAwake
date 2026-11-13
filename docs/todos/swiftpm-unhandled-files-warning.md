# `swift build` warns about unhandled files in the repo root

Seen on 2026-11-13 while building release 1.3.0.

`swift build` prints a warning that two files are unhandled and should be declared as resources or excluded from the target. It names `CLAUDE.md` and `CLAUDE.local.md`.

**Cause:** the executable target in `Package.swift` uses the repo root as its path (`path: "."`) with an explicit `exclude` list. Any root file that is not in the list and is not a source is reported. `CLAUDE.md` was added after the list was written; `CLAUDE.local.md` is a local, untracked file that exists only on some machines.

**Effect:** a warning only. The build, the tests and the app bundle are not affected.

**Fix when picked up:** add both names to the `exclude` list. The list is already filtered by `FileManager.default.fileExists`, so a name that is absent on a machine does no harm.
