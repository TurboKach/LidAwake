# Validation

`swift test` exercises the real control modules with simulated system settings. Tests
cover restoration on Quit and parent EOF, retry after a denied restore, recovery after
relaunch, journal failures, canceled toggles, master enable/disable and saved source
choices, power-source transitions, stable menu updates, command failures
and timeouts, exact sudo rules and legacy migration, login paths, and update comparisons.
`./scripts/test-recovery.sh` additionally kills a simulated GUI, including during an
in-flight write, and checks restoration by the real child-process transport.
No test changes the host's power settings, sudoers files, or login items.

`./scripts/build-app.sh universal` builds and signs the app for arm64 and x86_64.
`./scripts/check-build.sh universal` checks the signature, plist, and both macOS 12
Mach-O deployment targets. GitHub Actions runs tests and these bundle checks.

## Manual checks before publishing

Use a ventilated MacBook. Record the original `pmset -g` state and quit any old LidAwake
copy first. These checks deliberately change sleep settings and require interactive
admin/Automation approval; they are not part of the automated tests. On macOS 27,
`pmset -g` no longer prints `SleepDisabled`: wherever a check says `SleepDisabled` or
`pmset -g`, read the value with `ioreg -r -c IOPMrootDomain -d 1 | grep SleepDisabled`
(`Yes` = sleep disabled, `No` = sleep allowed).

1. Build/open `LidAwake.app`. Choose Not Now, then try enabling keep-awake. Confirm setup
   is offered again and canceling leaves the preference unchanged. Complete setup and
   verify its two exact commands using `sudo -l`. The password dialog must show LidAwake's
   own text in English and Russian, not "osascript wants to make changes". A legacy installation should preserve
   the old account while removing every wildcard from its rule.
2. Enable AC and disable battery. Plug/unplug with the lid open, closed, and the menu
   left open. Check actual `SleepDisabled` state, icon, and menu. Battery must restore
   sleep; a permission failure must be visible. Check both Apple Silicon and Intel when
   hardware is available, including the oldest supported macOS version.
   Turn the **LidAwake** switch off while awake: sleep must be restored and the AC, battery,
   and external-display controls must dim, the two condition switches keeping their
   positions and the external-display row its checkmark. Keep the
   menu open through several polls, switch power sources, and relaunch: the master
   must stay off. Enable it on battery: AC-only settings must still allow sleep until
   plugged in. Setup, login, and update actions must remain usable while disabled.
   Check the native switch with mouse, VoiceOver, and `⌘E` while the menu is open,
   including canceling setup and a failed change. Check the **Connected to Power** and
   **On Battery** switches with mouse and VoiceOver: a click on the switch or the title
   toggles once and the menu stays open until you click outside it. Verify the appearance
   of all three switches in light and dark mode and that neither the switches nor the menu
   blink during background polls.
3. Close/open the lid with no external display, with an external display, and with the
   external-display toggle in both states. Confirm internal blanking and external-display
   behavior. Verify hotplugging a display and unlocking the Mac afterward.
4. Enable keep-awake and Quit: `SleepDisabled` must return to 0. Repeat by force-quitting
   only the GUI PID, leaving its `--sleep-worker` child alive. The child should restore
   sleep within a few seconds after any in-flight command completes, then exit.
5. On a test machine, kill both GUI and worker while awake. Relaunch and confirm journal
   recovery restores the old override before applying the current saved policy. For a
   visible final 0, save both source policies off before the recovery launch. Also test
   revoked sudo permission: Quit must report failure and retain the marker until repair.
6. Open two app copies: only one worker may manage the setting. The second must report
   that another session is active and must not clear the first one's override on exit.
7. Put the app in a folder with spaces and quotes. Enable Launch at Login, log out/in,
   and confirm that exact copy launches. Deny Automation access and confirm a useful
   error without an unresponsive menu. Move the app, enable the item again, and confirm
   the previous LidAwake entry is replaced.
8. Open About and check TurboKach's credit, version, and GitHub link in English/Russian.
   Check updates while online/offline. Verify a newer stable release opens the correct
   release page only after confirmation. There must be no update request at startup.
9. Switch rule, with Sleep Setup complete, on a test machine after quitting LidAwake and
   running `defaults delete local.lidawake`: the first launch must show the switch off and
   both **Keep awake when** conditions on. Turn the switch on: it must stay on. Switch one
   condition off: the switch stays on. Switch off the last: the switch turns off, sleep is restored,
   and both condition switches are off and dimmed, also after a relaunch. Turn the switch on again:
   both conditions must be on. With one condition on, turn the switch off and on:
   the conditions must not change. Switching off the last condition for the power source that
   is not in use must turn the switch off without changing `SleepDisabled`. To check an
   upgrade, quit LidAwake, run `defaults delete local.lidawake`, then
   `defaults write local.lidawake awakeOnAC -bool true` and
   `defaults write local.lidawake awakeOnBattery -bool false` (1.2.0 saves nothing
   until the switch or a condition is first changed): the first launch must show the switch
   on with AC only on. Finally quit, set `awakeOnAC` and `awakeOnBattery` to `-bool false`
   and `lidAwakeEnabled` to `-bool true`: the next launch must show the switch off with both
   conditions on.

After testing, quit the app and verify sleep is enabled. If both processes were killed
and recovery cannot run, use `sudo pmset -a disablesleep 0` to restore sleep manually.
