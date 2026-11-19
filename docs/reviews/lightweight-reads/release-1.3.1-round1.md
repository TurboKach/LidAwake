# codex challenge — range d8da8efdcae0d9bab62fdbc70a7b0a931a530847..dee2b719deb11cfa36a89eaac2ce6c05dfae322b — checkout /Users/turbokach/Dev/LidAwake — model gpt-6.2-sol/medium — exit 0 — 151s
docs/prompts/lightweight-reads-plan.md:23 — `release.sh` builds the current working tree, so tagging `v1.3.1` and then packaging from a dirty or advanced checkout can publish a DMG that differs from the tag. The checksum still passes because it covers the DMG produced by that build.

docs/prompts/lightweight-reads-plan.md:41 — The lag experiment polls indefinitely if a successful `pmset` command never produces the expected registry value. If the experiment stalls or is interrupted after writing `1`, the final restore is skipped and there is no worker journal to recover it.

docs/prompts/lightweight-reads-plan.md:60 — The proposed Swift expression fails to compile because the throwing right-hand autoclosure makes `??` itself throw. The inner `try read()` leaves the operator call unmarked.

Sources/LidAwakeCore/SleepControl.swift:95 — The 1.3.1 release still verifies each write immediately. On macOS 27, a delayed registry update after a successful write can make the app reject a toggle whose global setting changes moments later, leaving the saved policy to undo it on the next tick.

Sources/LidAwakeCore/SleepControl.swift:156 — The planned settle never runs when the probe’s final `sudo 0` throws. If the probe’s `1` is still pending and the registry fallback reads `0`, `releaseClaim()` clears the journal before the delayed `1` lands, leaving sleep disabled after Quit.

Sources/LidAwakeCore/SleepControl.swift:162 — The planned settle only runs on writes. On macOS 27, quit or relaunch after a timed-out enable while the registry still reads `0` and `stop()` skips the restore and clears the journal. The pending `1` can then land with no recovery marker.

docs/prompts/lightweight-reads-plan.md:66 — Any registry error skips settling. If the registry read fails transiently during a restore and `pmset -g` already reports `0`, the worker can clear the recovery journal and exit while the kernel still has sleep disabled.

LidAwake.swift:232 — The planned registry-first status also controls display blanking. If a lid-close tick sees `pmset -g` report `1` while the registry still reads `0`, reconciliation skips the write and the blanking check skips `displaysleepnow`, leaving the display on until a later tick.

Sources/LidAwakeCore/SleepWorker.swift:172 — The planned first-enable path can add two settle waits without extending the 65-second reply deadline. Eight commands taking about 7.8 seconds each plus two 1.5-second waits disconnect the GUI mid-operation and leave it unable to control sleep until relaunch.

docs/prompts/lightweight-reads-plan.md:96 — The soak check can fail a healthy worker because it compares startup with a warmed process using a roughly 1 MB limit, while the plan’s own passing run grew 1.4 MB during warm-up before levelling off.

docs/prompts/lightweight-reads-plan.md:103 — The one-launch invariant fails on a supported machine whose registry property is unavailable. Every reporting request falls back to `pmset -g`, and the proposed launch-count tests only exercise a working registry.