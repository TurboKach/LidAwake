# Release 1.3 — Arc C plan: UI strings move to a String Catalog

## Context
`LidAwake.swift` holds 54 inline `L("en", "ru")` pairs (51 different texts; the todo file's "55" is a miscount). Text and locale logic are mixed in one file, a language cannot be added without a code edit, and nothing checks that a language has every text. The owner chose Apple's current practice, a String Catalog, with the locales in their own folder (2026-11-13: "make sure locales are living in corresponding folder so we can easily extend it later", "ok lets do as apple says").

Outcome: the texts live in `Localization/Localizable.xcstrings`; the script build compiles them into `en.lproj` and `ru.lproj` in the app bundle; a check fails the build when a text or a language is missing. **No wording changes**: every English and Russian text is byte-identical before and after.

Branch `release-1.3`, base head `bbaa5d3`. The feature base is the commit that adds this plan. The whole-range review runs on `2f880d8..HEAD` so it joins the last clean gate with no gap. Never push.

## Decisions (owner, 2026-11-13, this session)
- **Core's English-only error texts: "Leave English, defer (Recommended)".** About 40 `ControlError` texts in `Sources/LidAwakeCore`, 4 `echo` lines of the admin shell script and `NSAppleEventsUsageDescription` stay English. One deferred index line.
- **Catalog key: "The English text (Recommended)".** A missing key, or a run outside the bundle, shows English.

## Design
- **Catalog:** `Localization/Localizable.xcstrings`, `sourceLanguage: "en"`. The key is the English text; each of the 51 keys has an explicit `en` string unit (value equal to the key) and a `ru` string unit, both in state `translated`. The `en` units are required: `xcstringstool compile` writes no `en.lproj` for a catalog that has `ru` units only (the plan reviewer's dry run, Xcode 27.2). The folder is added to the `exclude:` list of the app target in `Package.swift` (the target's path is `.`).
- **Values in a text:** an interpolation becomes `%@` in the key and in the Russian value; the call site passes the value as a `String` (`"\(getuid())"` for the uid). Four texts: LA:378 (uid), 455 (`latest`), 456 and 463 (`version`).
- **Fragments stay fragments.** The 5 places that build a message by concatenation (LA:69–72, 74–79, 168–169, 409–410, 440) keep their structure; each fragment is one key, leading and trailing spaces and `\n` included.
- **`L` in `LidAwake.swift`:** `L(_ key: String, _ args: CVarArg...) -> String`. It reads `Bundle.main.localizedString(forKey: key, value: nil, table: nil)`. Invariant: `String(format:)` runs only when `args` is not empty, so a text with a literal `%` and no value is never read as a format. Bound: at most one `%@` per text today; the check script rejects any other specifier and any count mismatch between a key and its Russian value.
- **Language choice:** the old `L` matched the system language list against `["en", "ru"]`. The bundle lookup gives the same result, and also follows a per-app language set in System Settings. `Info.plist` gets `CFBundleDevelopmentRegion = en`, and the bundle must hold `en.lproj`, so any other language falls to English as today.
- **Build:** `scripts/build-app.sh` runs `xcrun xcstringstool compile Localization/Localizable.xcstrings --output-directory LidAwake.app/Contents/Resources` after the icon copy and before `codesign`. `release.sh` copies the whole bundle, so it needs no change.
- **Check script, new `scripts/check-strings.sh`**, a thin wrapper that runs `xcrun swift scripts/check-strings.swift` (Foundation only; no `python3`, no `jq`). Invariants:
  1. Every catalog key has a non-empty `en` and a non-empty `ru` value, both in state `translated`.
  2. The `en` value of a key equals the key.
  3. Every `L(` in `LidAwake.swift`, matched as a whole token (not preceded by a letter, digit or `_`; the definition line excluded), is followed on the same line or the next line by one plain `"…"` string literal, and that literal, unescaped, is a catalog key. The parser knows exactly the escapes `\n`, `\"` and `\\`. Any other escape, an interpolation `\(`, a `"""` literal, a `#"` literal or a non-literal first argument fails the check.
  4. Every catalog key is used by some `L(` call (no orphan).
  5. The `%@` count of a key equals that of its `ru` value; no other format specifier is allowed.
  6. The number of arguments after the key at each call site equals the `%@` count of the key.
  Bound: the script reads one source file and one catalog; today 54 calls and 51 keys.
- **Bundle check:** `scripts/check-build.sh` also requires `Contents/Resources/en.lproj/Localizable.strings` and `ru.lproj/Localizable.strings`, and `plutil -lint` passes on both.
- **CI:** `.github/workflows/ci.yml` runs `./scripts/check-strings.sh`.

Side effect to name in the notes: with `ru.lproj` in the bundle, macOS draws its own parts (a default OK button, the About panel) in Russian for a Russian user.

## Steps
Parallel: none — each step consumes the one before it, and all need the same `.build` and `LidAwake.app`.

### Step 1 — the catalog and the build (`step-executor`, Sonnet)
Files: `Localization/Localizable.xcstrings` (new), `Package.swift`, `Info.plist`, `scripts/build-app.sh`, `scripts/check-build.sh`.
- Build the catalog from the 54 pairs in `LidAwake.swift` at `bbaa5d3` (51 keys; the three status texts at LA:267/268 repeat at 298/299 with the same Russian). Copy every character: typographic quotes and apostrophes, `…`, `•`, `—`, `\n`, leading spaces.
- `LidAwake.swift` is not touched in this step.

Acceptance:
- `swift build` shows no unhandled-file warning for `Localization`.
- `./scripts/build-app.sh universal` then `./scripts/check-build.sh universal` pass; the bundle holds `en.lproj/Localizable.strings` and `ru.lproj/Localizable.strings`, and each holds all 51 entries.
- A throwaway Swift probe in the scratchpad loads the built bundle with `Bundle(path:)` (the app is never launched) and shows:
  - run with `-AppleLanguages '(de)'`: `bundle.localizations` holds `en` and `ru`, and `bundle.preferredLocalizations` is `["en"]`; run with `'(ru)'`: `["ru"]`.
  - a round trip of the hard keys, byte-exact in both languages: one with a leading space (LA:69), one that ends with `\n\n` (LA:77), one with `’` and `%@` (LA:456), the bullet text with `•`, `—` and `%@` (LA:378).
- `swift test`: executed, skipped and failed counts shown; 0 failed.

### Step 2 — the code reads the catalog (`step-executor`, Sonnet)
Files: `LidAwake.swift` only.
- Replace `L` (LA:6–8) per the Design. Change every call site; checklist of the 54 (lines at `bbaa5d3`):
  31, 33, 69, 71, 72, 74, 77, 167, 168, 170, 171, 267 (two), 268, 297 (two), 298 (two), 299, 305, 308, 309, 310, 312, 314 (two), 315, 317, 319, 320 (two), 322, 361, 362, 365, 366, 377, 378, 381, 382, 395, 403, 409, 430, 434, 440, 455, 456, 458, 459, 462, 463, 466, 467.
  The string of 362 and 378 starts on the next line. Values: 378 `getuid()`, 455 `latest`, 456 and 463 `version`.
- No Russian text stays in `LidAwake.swift`.
- The two admin prompts (LA:31–34) still go to `PrivilegeSetup(installPrompt:uninstallPrompt:)` with their exact text; `SystemAdaptersTests.testAdminPromptsAreAddedToTheScriptLinesAndEscaped` stays untouched and green.

Acceptance:
- `grep` finds no Cyrillic character in `LidAwake.swift`, and no two-argument literal pair is left.
- `swift build` and `swift test` (counts shown, 0 failed) pass.

### Step 3 — the check script and CI (`step-executor`, Sonnet)
Files: `scripts/check-strings.sh` (new), `scripts/check-strings.swift` (new), `.github/workflows/ci.yml`.
- The six invariants of the Design. CI runs `./scripts/check-strings.sh` next to the other checks.

Acceptance:
- `./scripts/check-strings.sh` exits 0 and prints the key count (51) and the call-site count (54).
- Each of the six invariants is shown red once with a temporary edit, then reverted; `git status` is clean of those edits at the end.
- `bash -n scripts/*.sh`, `./scripts/build-app.sh universal`, `./scripts/check-build.sh universal` pass.

### Step 4 — the proof and the docs (`step-executor`, Sonnet)
Files: `README.md`, `docs/testing.md`, `docs/prompts/release-1.3-notes-draft.md`; a throwaway comparison tool in the session scratchpad (not in the repo).
- **Before/after comparison (the arc's proof).** The tool extracts the 54 `(en, ru)` pairs from `git show bbaa5d3:LidAwake.swift`, and the 54 `L(` keys from the current file in the same order. For each pair and each language it reads the text from the **built** `LidAwake.app` (`Bundle(path:)`, then the `en.lproj` / `ru.lproj` sub-bundle), fills the values with fixed samples on both sides, and compares bytes. It writes a table to the scratchpad. The app is never launched.
- Docs (new text; today the docs say only "English or Russian"): next to `README.md:63`, one or two sentences: the texts live in `Localization/Localizable.xcstrings`, the app follows the system language or the per-app language setting, and a new language is a new set of values in the catalog. In `docs/testing.md`, next to lines 28 and 65, one manual check: run the app in Russian and in English and read the menu, the setup alert, the Uninstall alert (then Cancel), Check for Updates and the About panel. Add the catalog and the system-drawn Russian parts to the notes draft.
- Full verification on the head: `swift test`, `./scripts/test-recovery.sh`, `./scripts/check-strings.sh`, universal build and check.

Acceptance:
- The table shows 54 of 54 identical for `en` and 54 of 54 identical for `ru`; the report gives the table's path and the counts.
- All verification commands pass, with executed/skipped/failed counts for `swift test` (the opt-in registry test stays skipped; the master asks nothing of the owner's password).

### Close-out (master)
- Stage 5: one codex challenge on `2f880d8..HEAD`, `codex-triage`, and one `spec-reviewer` on this plan, in parallel.
- Docs commit: delete `docs/todos/string-catalog-locales.md` and its line in `docs/tech-debt.md`; add one line and `docs/todos/localize-remaining-english-texts.md` (Core's error texts and the choice "own catalog or keys passed to the app", the 4 shell `echo` lines, `NSAppleEventsUsageDescription`; the texts that quote menu titles must match the Russian menu titles). Tick Arc C in `docs/prompts/release-1.3-next-session.md` and record the state.
- Owner's device pass (the owner runs `./build.sh`): the app in Russian and in English; menu, the setup alert, About, one admin dialog text, the Uninstall alert (then Cancel) and Check for Updates (these two show the texts that carry a value).
- Handoff brief for the next session in the scratchpad.

## Edge cases
- A language that is neither `en` nor `ru` → English (Step 1 probe).
- `swift run` or any run outside the bundle → English keys; a `%@` text is still formatted.
- A text with a typographic apostrophe or quotes as a key (LA:456, 463, 77) → byte-exact in the catalog and in the compiled `.strings`.
- Fragments that start with a space (LA:69, 71) and texts that end with `\n\n` → kept by the catalog and the compile step (the comparison proves it).
- `AppRuntime.setup` is lazy: the two prompts are fixed at first use, as today.
- The sleep worker is the same binary with no UI; it reads no text.
- The intermediate state after Step 1 (bundle with `.lproj`, code still on pairs) is valid and builds.

## Decision on the render (owner, 2026-11-13)
- **"No render (Recommended)".** The todo file asked for a render of the menu in `en` and `ru`. The proof is the byte comparison against the built bundle plus the owner's device pass in both languages.

## Verification (end to end)
1. `./scripts/check-strings.sh` — catalog and code agree.
2. `./scripts/build-app.sh universal` and `./scripts/check-build.sh universal` — the bundle holds both `.lproj` folders.
3. The comparison table: 54/54 for `en`, 54/54 for `ru`, read from the built bundle.
4. `swift test` and `./scripts/test-recovery.sh`.
5. The codex gate on `2f880d8..HEAD` is clean, and the spec check finds no gap.
6. The owner's device pass in Russian and in English. The agent cannot launch the app (the installed copy is live) and cannot capture the screen, so this pass is the only check of the real menu.
