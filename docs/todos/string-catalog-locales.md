# Move UI strings to a String Catalog

What: replace the inline `L("en", "ru")` pairs in `LidAwake.swift` (55 call sites at release-1.3) with a String Catalog, `Localizable.xcstrings`. It is Apple's current practice and the owner's pick (2026-11-13). Own arc in 1.3.1.

Why: the pairs mix text and locale logic in one file, a language cannot be added without editing code, and nothing checks that a language has every key.

Facts (checked with Xcode 27.2):
- The script build can compile the catalog: `xcrun xcstringstool compile <catalog> --output-directory <dir>` writes `<lang>.lproj/Localizable.strings`.
- `scripts/build-app.sh` would copy those `.lproj` folders into `Contents/Resources`.
- The tool's `extract` and `sync` commands are untried.
- `Info.plist` has no localization keys today (no `CFBundleLocalizations`, no `CFBundleDevelopmentRegion` choice recorded).

Open scope points for that arc's plan:
- Core's English-only error texts (`ControlError` messages) reach alerts untranslated. Decide whether Core gets a catalog of its own or passes keys to the app.
- A check that every language has every key.
- A before/after comparison of all en and ru texts, so the move changes no wording.

Depends: nothing. Effort: medium. Own arc, with its own plan; run the build and a render for en and ru before merging.
