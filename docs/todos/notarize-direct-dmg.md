# Notarize the direct DMG

What: sign the direct build with a Developer ID Application certificate and a hardened runtime, then notarize and staple the DMG in `release.sh`.

Why: the app is ad-hoc signed today (`codesign --force --sign -` in `scripts/build-app.sh`), so macOS 15 and later make the user approve it in System Settings (Privacy & Security) before the first launch.

Context: owner decision 2026-11-13: release 1.3.0 stays ad-hoc signed; notarization follows in 1.3.1. The release notes for 1.3.0 say so.

Depends: a notary credential (Apple ID app-specific password or an App Store Connect API key) and the Developer ID certificate, both from the owner. Check that the hardened runtime does not break the `sudo -n pmset` helper path or the worker process.

Effort: medium. Own arc, with its own plan.

Update 2026-11-13: the owner later chose one release with everything. This item is built before the 1.3.0 release, not in a 1.3.1; see `docs/prompts/release-1.3-next-session.md`.

Update 2026-11-13 (later session): no notary credential is stored, and the owner chose "Ship 1.3.0 without notarization". 1.3.0 stays ad-hoc signed; this item follows in a later release. The Mac has a Developer ID Application certificate. When this is built, check two things under the hardened runtime with the owner and a real password: the in-app admin script (`do shell script … with administrator privileges` through `NSAppleScript`), and that the signed bundle still holds and reads `en.lproj` and `ru.lproj` (signing must follow the catalog compile step in `scripts/build-app.sh`).
