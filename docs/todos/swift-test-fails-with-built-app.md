# `swift test` fails while the built app bundle is in the repo root

**What:** with `LidAwake.app` present in the repo root (left by `./build.sh --no-install`, `./scripts/build-app.sh` or `./release.sh`), `swift test` exits 1 before it compiles anything:

    error: 'lidawake': manifest property 'defaultLocalization' not set; it is required in the presence of localized resources

With the bundle moved away, the same tree passes: 114 tests, 1 skipped (the opt-in real-registry test), 0 failures. Seen on 2026-11-19 at `dee2b71`, Swift on macOS 26.6.2.

**Why it matters:** `Package.swift` lists `LidAwake.app` in the executable target's `exclude` (filtered by `FileManager.default.fileExists`), so the bundle's `.lproj` resources should not be scanned. Something lets them through. A build followed by a test run fails in a way that looks like a manifest bug, and an agent can lose time on it.

**Workaround:** move or delete `LidAwake.app` before `swift test`, or run the tests before building.

**Context:** not investigated further. Candidates: how SwiftPM applies `exclude` to a directory with a bundle extension, or the manifest's `fileExists` running with a different working directory. Related: `docs/todos/swiftpm-unhandled-files-warning.md`.

Depends: nothing. Effort: small.
