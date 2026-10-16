import XCTest
import Darwin
@testable import LidAwakeCore

final class RecordingRunner: CommandRunning {
    var calls = [(String, [String])]()
    var respond: ([String]) throws -> CommandOutput = { _ in CommandOutput() }
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) throws -> CommandOutput {
        calls.append((executable, arguments))
        return try respond(arguments)
    }
}

final class SystemAdaptersTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testSleepStatusParserRejectsMissingMalformedAndAmbiguousValues() throws {
        XCTAssertTrue(try PMSet.parse("System-wide power settings:\n SleepDisabled\t1\n"))
        XCTAssertFalse(try PMSet.parse(" SleepDisabled   0\n"))
        for output in ["", "pmset failed", "SleepDisabled 10", "NotSleepDisabled 1", "SleepDisabled 1\nSleepDisabled 0"] {
            XCTAssertThrowsError(try PMSet.parse(output), output)
        }
    }

    func testPMSetVerifiesTheActualWriteAndDoesNotUseCachedCredentials() throws {
        let runner = RecordingRunner()
        runner.respond = { args in CommandOutput(stdout: args == ["-g"] ? "SleepDisabled 0" : "") }
        let pmset = PMSet(runner: runner, setup: PrivilegeSetup(runner: runner))
        XCTAssertThrowsError(try pmset.write(true))
        XCTAssertEqual(runner.calls[0].1, ["-n", "-k", "/usr/bin/pmset", "-a", "disablesleep", "1"])
        XCTAssertEqual(runner.calls[1].1, ["-g"])
    }

    /// A runner that behaves like pmset behind sudo: `denied` values fail without changing anything.
    private func pmsetRunner(startingAt value: String, denying denied: Set<String> = [],
                             failingAfterApplying failing: Set<String> = []) -> (RecordingRunner, () -> String) {
        let runner = RecordingRunner()
        var state = value
        runner.respond = { args in
            if args == ["-g"] { return CommandOutput(stdout: "SleepDisabled \(state)") }
            let requested = args.last!
            if denied.contains(requested) { throw ControlError.message("sudo: a password is required") }
            state = requested
            if failing.contains(requested) { throw ControlError.message("timed out") }
            return CommandOutput()
        }
        return (runner, { state })
    }

    private func sudoWrites(_ runner: RecordingRunner) -> [String] {
        runner.calls.filter { $0.0 == "/usr/bin/sudo" }.map { $0.1.last! }
    }

    private func probe(_ runner: RecordingRunner) throws {
        try PMSet(runner: runner, setup: PrivilegeSetup(runner: runner)).probeRule()
    }

    func testPMSetProbeProvesBothDirectionsAndLeavesSleepEnabledWhenItStartedEnabled() throws {
        let (runner, state) = pmsetRunner(startingAt: "0")
        try probe(runner)
        XCTAssertEqual(sudoWrites(runner), ["0", "1", "0"])
        XCTAssertEqual(state(), "0")
        XCTAssertTrue(runner.calls.filter { $0.0 == "/usr/bin/sudo" }.allSatisfy { $0.1.starts(with: ["-n", "-k", "/usr/bin/pmset", "-a", "disablesleep"]) })
    }

    func testPMSetProbeNeverWritesSleepEnabledWhileSomethingHoldsItDisabled() throws {
        let (runner, state) = pmsetRunner(startingAt: "1")
        try probe(runner)
        XCTAssertEqual(sudoWrites(runner), ["1"])
        XCTAssertEqual(state(), "1")
    }

    func testPMSetProbeRejectsARuleThatAllowsOnlyOneDirectionWithoutChangingTheSetting() throws {
        for (denied, start) in [("1", "0"), ("0", "0"), ("1", "1")] {
            let (runner, state) = pmsetRunner(startingAt: start, denying: [denied])
            XCTAssertThrowsError(try probe(runner), "deny \(denied) from \(start)")
            XCTAssertEqual(state(), start)
        }
    }

    func testPMSetProbeRestoresTheSettingWhenTheOppositeWriteFailsAfterApplying() throws {
        let (runner, state) = pmsetRunner(startingAt: "0", failingAfterApplying: ["1"])
        XCTAssertThrowsError(try probe(runner))
        XCTAssertEqual(state(), "0")
    }

    /// PMSet with the setup-file check skipped, so a SleepSession can drive the real probe.
    private final class ProbingPower: PowerSettings {
        let pmset: PMSet
        init(_ runner: RecordingRunner) { pmset = PMSet(runner: runner, setup: PrivilegeSetup(runner: runner)) }
        func read() throws -> Bool { try pmset.read() }
        func requireAutomaticControl() throws { try pmset.probeRule() }
        func write(_ awake: Bool) throws { try pmset.write(awake) }
    }

    func testProbeWritesThatCanLeaveSleepDisabledAreCoveredByTheRecoveryJournal() throws {
        let (runner, state) = pmsetRunner(startingAt: "0")
        let journal = MemoryJournal()
        var journalWhenSleepWasDisabled: Bool?
        var killed = false, survives = false
        let applied = runner.respond
        runner.respond = { args in
            if args == ["-g"] { return try applied(args) }
            if args.last == "1" { journalWhenSleepWasDisabled = journal.pending }
            // Simulated process death right after the 1 was applied: nothing else runs.
            if !survives && (killed || (args.last == "0" && state() == "1")) { killed = true; throw ControlError.message("killed") }
            return try applied(args)
        }
        let session = try SleepSession(settings: ProbingPower(runner), journal: journal)
        XCTAssertThrowsError(try session.setAwake(true))
        XCTAssertEqual(state(), "1")
        XCTAssertEqual(journalWhenSleepWasDisabled, true, "journal must be committed before the probe disables sleep")
        XCTAssertTrue(journal.pending, "sleep is left disabled, so recovery must still be owed")
        // A relaunch (or the worker's stop) restores it from the journal.
        survives = true
        let relaunched = try SleepSession(settings: ProbingPower(runner), journal: journal)
        try relaunched.recover()
        XCTAssertEqual(state(), "0")
        XCTAssertFalse(journal.pending)
    }

    func testRejectedProbeReleasesTheClaimItTookBeforeProbing() throws {
        for (denied, start) in [("1", "0"), ("0", "0"), ("1", "1")] {
            let (runner, state) = pmsetRunner(startingAt: start, denying: [denied])
            let journal = MemoryJournal()
            let session = try SleepSession(settings: ProbingPower(runner), journal: journal)
            XCTAssertThrowsError(try session.setAwake(true), "deny \(denied) from \(start)")
            XCTAssertEqual(state(), start)
            XCTAssertFalse(journal.pending, "nothing was changed, so nothing is owed")
        }
    }

    func testPMSetRequiresTheRuleFileBeforeProbing() {
        let runner = RecordingRunner()
        let pmset = PMSet(runner: runner, setup: PrivilegeSetup(runner: runner, uid: 502, directory: directory.path))
        XCTAssertThrowsError(try pmset.requireAutomaticControl())
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testPMSetReadFallsBackToRootDomainWhenPMSetOmitsSleepDisabled() throws {
        let runner = RecordingRunner()
        runner.respond = { _ in CommandOutput(stdout: "System-wide power settings:\nCurrently in use:\n standby 1\n") }
        XCTAssertFalse(try PMSet(runner: runner, setup: PrivilegeSetup(runner: runner), rootDomainSleepDisabled: { false }).read())
        XCTAssertTrue(try PMSet(runner: runner, setup: PrivilegeSetup(runner: runner), rootDomainSleepDisabled: { true }).read())
    }

    func testPMSetReadThrowsWhenPMSetAndRootDomainBothFail() {
        let runner = RecordingRunner()
        runner.respond = { _ in CommandOutput(stdout: "") }
        XCTAssertThrowsError(try PMSet(runner: runner, setup: PrivilegeSetup(runner: runner), rootDomainSleepDisabled: { nil }).read())
    }

    func testPMSetReadPrefersPMSetWhenItReportsSleepDisabled() throws {
        let runner = RecordingRunner()
        runner.respond = { _ in CommandOutput(stdout: " SleepDisabled 1\n") }
        XCTAssertTrue(try PMSet(runner: runner, setup: PrivilegeSetup(runner: runner), rootDomainSleepDisabled: { false }).read())
    }

    func testPMSetReadPropagatesProcessFailureEvenWithValidLookingOutput() {
        let runner = RecordingRunner()
        runner.respond = { _ in throw ControlError.message("pmset unavailable") }
        XCTAssertThrowsError(try PMSet(runner: runner, setup: PrivilegeSetup(runner: runner)).read())
    }

    func testNewSudoRuleParsesAndContainsOnlyTwoExactCommands() throws {
        let setup = PrivilegeSetup(runner: RecordingRunner(), uid: 501, directory: directory.path)
        let rule = directory.appendingPathComponent("rule")
        try setup.rule.write(to: rule, atomically: true, encoding: .utf8)
        _ = try ProcessCommandRunner().run("/usr/sbin/visudo", ["-cf", rule.path], timeout: 5)
        XCTAssertFalse(setup.rule.contains("*"))
        XCTAssertTrue(setup.rule.hasPrefix("#501 "))
        XCTAssertEqual(setup.rule.components(separatedBy: "/usr/bin/pmset").count, 3)
        XCTAssertFalse(setup.isInstalled) // No rule for this account at its expected path.
    }

    func testInstallerNarrowsLegacyRuleAndPreservesItsAccount() throws {
        let setup = PrivilegeSetup(runner: RecordingRunner(), uid: 502, directory: directory.path)
        let legacy = directory.appendingPathComponent("lidawake")
        try "other_user ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep *, /usr/bin/pmset -b disablesleep *, /usr/bin/pmset -c disablesleep *\n".write(to: legacy, atomically: true, encoding: .utf8)
        // Exercise the real generated script in a temporary directory; omit chown.
        let script = setup.installationScript.replacingOccurrences(of: "-o root -g wheel", with: "")
        _ = try ProcessCommandRunner().run("/bin/sh", ["-c", script], timeout: 10)
        let result = try String(contentsOf: legacy)
        XCTAssertTrue(result.hasPrefix("other_user ALL="))
        XCTAssertFalse(result.contains("*"))
        XCTAssertEqual(try String(contentsOfFile: setup.path), setup.rule)
    }

    func testInstallerPreservesUnknownLegacyContentAndPropagatesValidationFailure() throws {
        let setup = PrivilegeSetup(runner: RecordingRunner(), directory: directory.path)
        let legacy = directory.appendingPathComponent("lidawake")
        let custom = "custom administrator rule\n"
        try custom.write(to: legacy, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try ProcessCommandRunner().run("/bin/sh", ["-c", setup.installationScript], timeout: 5))
        XCTAssertEqual(try String(contentsOf: legacy), custom)
        try FileManager.default.removeItem(at: legacy)
        let badValidation = setup.installationScript.replacingOccurrences(of: "/usr/sbin/visudo", with: "/usr/bin/false")
        XCTAssertThrowsError(try ProcessCommandRunner().run("/bin/sh", ["-c", badValidation], timeout: 5))
        XCTAssertFalse(FileManager.default.fileExists(atPath: setup.path))
    }

    func testInstallerRefusesLegacySymlink() throws {
        let setup = PrivilegeSetup(runner: RecordingRunner(), directory: directory.path)
        let target = directory.appendingPathComponent("untouched")
        try "original".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("lidawake"), withDestinationURL: target)
        XCTAssertThrowsError(try ProcessCommandRunner().run("/bin/sh", ["-c", setup.installationScript], timeout: 5))
        XCTAssertEqual(try String(contentsOf: target), "original")
    }

    func testUninstallerRemovesThisAccountsAndLegacyRulesWithOneAdminPrompt() throws {
        let quoted = directory.appendingPathComponent("it's \"sudoers\"")
        try FileManager.default.createDirectory(at: quoted, withIntermediateDirectories: false)
        let runner = RecordingRunner()
        let setup = PrivilegeSetup(runner: runner, uid: 502, directory: quoted.path)
        XCTAssertEqual(setup.path, quoted.path + "/lidawake-502")
        let legacy = quoted.appendingPathComponent("lidawake")
        let other = quoted.appendingPathComponent("lidawake-503")
        for file in [setup.path, other.path] {
            try "rule\n".write(toFile: file, atomically: true, encoding: .utf8)
        }
        try legacyRule(NSUserName()).write(to: legacy, atomically: true, encoding: .utf8)
        try runUninstallScript(setup)
        XCTAssertFalse(FileManager.default.fileExists(atPath: setup.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path)) // Another account's rule stays.
        try runUninstallScript(setup) // Already removed.

        try setup.uninstall()
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls[0].0, "/usr/bin/osascript")
        XCTAssertEqual(runner.calls[0].1, ["-e",
            "do shell script \(appleScriptString(setup.uninstallationScript)) with administrator privileges"])
    }

    func testUninstallerRefusesSymlinksAndRemovesNothing() throws {
        let setup = PrivilegeSetup(runner: RecordingRunner(), uid: 502, directory: directory.path)
        let target = directory.appendingPathComponent("untouched")
        try "original".write(to: target, atomically: true, encoding: .utf8)
        for link in ["lidawake", "lidawake-502"] {
            let path = directory.appendingPathComponent(link)
            let sibling = directory.appendingPathComponent(link == "lidawake" ? "lidawake-502" : "lidawake")
            try FileManager.default.createSymbolicLink(at: path, withDestinationURL: target)
            try "rule\n".write(to: sibling, atomically: true, encoding: .utf8)
            XCTAssertThrowsError(try runUninstallScript(setup))
            XCTAssertEqual(try String(contentsOf: target), "original")
            XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: path.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: sibling.path))
            try FileManager.default.removeItem(at: path)
            try FileManager.default.removeItem(at: sibling)
        }
    }

    private func legacyRule(_ user: String, old: Bool = false) -> String {
        old ? "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep *, /usr/bin/pmset -b disablesleep *, /usr/bin/pmset -c disablesleep *\n"
            : "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n"
    }

    func testUninstallScriptRemovesTheLegacyRuleOnlyWhenItNamesThisAccount() throws {
        let setup = PrivilegeSetup(runner: RecordingRunner(), uid: 502, directory: directory.path)
        let legacy = directory.appendingPathComponent("lidawake")
        let kept = [legacyRule("someone_else"), legacyRule("someone_else", old: true), legacyRule(NSUserName() + "x"),
                    "rule\n", "", legacyRule(NSUserName()) + legacyRule(NSUserName()), "# " + legacyRule(NSUserName())]
        for content in kept {
            try "rule\n".write(toFile: setup.path, atomically: true, encoding: .utf8)
            try content.write(to: legacy, atomically: true, encoding: .utf8)
            XCTAssertEqual(try runUninstallScript(setup, sleepDisabled: 1).stdout, "kept-legacy\n", content)
            XCTAssertEqual(setup.remainingRules, [legacy.path], content)
            XCTAssertEqual(try String(contentsOf: legacy), content)
        }
        for content in [legacyRule(NSUserName()), legacyRule(NSUserName(), old: true)] {
            try "rule\n".write(toFile: setup.path, atomically: true, encoding: .utf8)
            try content.write(to: legacy, atomically: true, encoding: .utf8)
            XCTAssertEqual(try runUninstallScript(setup).stdout, "", content)
            XCTAssertEqual(setup.remainingRules, [], content)
        }
        XCTAssertEqual(try runUninstallScript(setup).stdout, "") // Nothing left.
    }

    /// Runs the uninstall script with a fake pmset whose SleepDisabled starts at `sleepDisabled`.
    /// A sticky fake ignores writes, like a setting something else keeps re-applying.
    @discardableResult
    private func runUninstallScript(_ setup: PrivilegeSetup, sleepDisabled: Int = 0, sticky: Bool = false) throws -> (sleepDisabled: Int, stdout: String) {
        let state = directory.appendingPathComponent("SleepDisabled")
        let pmset = directory.appendingPathComponent("pmset")
        try "\(sleepDisabled)".write(to: state, atomically: true, encoding: .utf8)
        try """
        #!/bin/sh
        if [ "$1" = -g ]; then printf 'System-wide power settings:\\n SleepDisabled\\t%s\\n' "$(cat '\(state.path)')"
        elif [ "$1 $2" = '-a disablesleep' ]; then \(sticky ? ":" : "printf %s \"$3\" > '\(state.path)'")
        else exit 1; fi
        """.write(to: pmset, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: pmset.path)
        let script = setup.uninstallationScript // Only the pmset calls, not the legacy rule patterns.
            .replacingOccurrences(of: "\n/usr/bin/pmset ", with: "\n\(pmset.path) ")
            .replacingOccurrences(of: "$(/usr/bin/pmset ", with: "$(\(pmset.path) ")
        defer { try? FileManager.default.removeItem(at: pmset) }
        let output = try ProcessCommandRunner().run("/bin/sh", ["-c", script], timeout: 5)
        return (Int(try String(contentsOf: state, encoding: .utf8))!, output.stdout)
    }

    func testUninstallScriptRestoresSleepBeforeRemovingTheRules() throws {
        let setup = PrivilegeSetup(runner: RecordingRunner(), uid: 502, directory: directory.path)
        try "rule\n".write(toFile: setup.path, atomically: true, encoding: .utf8)
        XCTAssertEqual(try runUninstallScript(setup, sleepDisabled: 1).sleepDisabled, 0)
        XCTAssertEqual(setup.remainingRules, [])
    }

    func testUninstallScriptRemovesNothingWhenSleepCannotBeRestored() throws {
        let setup = PrivilegeSetup(runner: RecordingRunner(), uid: 502, directory: directory.path)
        try "rule\n".write(toFile: setup.path, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try runUninstallScript(setup, sleepDisabled: 1, sticky: true))
        XCTAssertEqual(setup.remainingRules, [setup.path])
    }

    func testUninstallScriptChecksBothRulesBeforeRemovingEither() throws {
        let setup = PrivilegeSetup(runner: RecordingRunner(), uid: 502, directory: directory.path)
        try "rule\n".write(toFile: setup.path, atomically: true, encoding: .utf8)
        let legacy = directory.appendingPathComponent("lidawake")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: false) // rm -f cannot remove it.
        XCTAssertThrowsError(try runUninstallScript(setup))
        XCTAssertEqual(setup.remainingRules, [setup.path, legacy.path])
    }

    func testCommandRunnerHandlesLaunchFailureExitFailureAndCancellation() throws {
        let runner = ProcessCommandRunner()
        XCTAssertThrowsError(try runner.run("/missing/lidawake-command", [], timeout: 1))
        XCTAssertThrowsError(try runner.run("/bin/sh", ["-c", "echo deliberate-error >&2; exit 7"], timeout: 2)) {
            XCTAssertTrue($0.localizedDescription.contains("deliberate-error"))
        }
        XCTAssertThrowsError(try runner.run("/bin/sh", ["-c", "echo 'execution error: User canceled. (-128)' >&2; exit 1"], timeout: 2)) {
            XCTAssertEqual($0 as? ControlError, .canceled)
        }
    }

    func testCommandTimeoutAndLargeOutputDoNotHang() throws {
        let runner = ProcessCommandRunner()
        let start = Date()
        XCTAssertThrowsError(try runner.run("/bin/sleep", ["10"], timeout: 0.05))
        XCTAssertLessThan(Date().timeIntervalSince(start), 4)
        let result = try runner.run("/bin/sh", ["-c", "/usr/bin/yes x | /usr/bin/head -c 262144; /usr/bin/yes y | /usr/bin/head -c 262144 >&2"], timeout: 5)
        XCTAssertEqual(result.stdout.utf8.count, 262144)
        XCTAssertEqual(result.stderr.utf8.count, 262144)
    }

    func testAppleScriptEscaping() {
        XCTAssertEqual(appleScriptString("a\\b\"c\nd"), "\"a\\\\b\\\"c\\nd\"")
    }

    func testLoginUsesResolvedBundlePathAsAnArgumentAndVerifiesRegistration() throws {
        let runner = RecordingRunner()
        let bundle = directory.appendingPathComponent("My \"LidAwake\".app")
        let login = LoginItems(runner: runner, bundleURL: bundle)
        var responses = ["", "true"]
        runner.respond = { _ in CommandOutput(stdout: responses.removeFirst()) }
        try login.setEnabled(true)
        XCTAssertEqual(runner.calls.count, 2)
        for call in runner.calls {
            XCTAssertEqual(call.1.last, bundle.path)
            XCTAssertFalse(call.1[1].contains(bundle.path))
        }
    }

    func testLoginFailureAndUnknownStatusAreReported() throws {
        let runner = RecordingRunner()
        let login = LoginItems(runner: runner, bundleURL: directory.appendingPathComponent("LidAwake.app"))
        XCTAssertThrowsError(try login.isEnabled())
        runner.respond = { args in CommandOutput(stdout: args[1].contains("return") ? "false" : "") }
        XCTAssertThrowsError(try login.setEnabled(true))
        runner.respond = { _ in throw ControlError.message("Automation denied") }
        XCTAssertThrowsError(try login.isEnabled())
    }

    func testRecoveryJournalSurvivesReopenAndRefusesSymlinks() throws {
        var journal: FileRecoveryJournal? = try FileRecoveryJournal(directory: directory)
        try journal?.save(true)
        journal = nil
        journal = try FileRecoveryJournal(directory: directory)
        XCTAssertTrue(try journal!.load())
        try journal?.save(false)
        XCTAssertFalse(try journal!.load())
        journal = nil
        let path = directory.appendingPathComponent("restore-sleep")
        try FileManager.default.removeItem(at: path)
        let target = directory.appendingPathComponent("untouched")
        try "data".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: path, withDestinationURL: target)
        XCTAssertThrowsError(try FileRecoveryJournal(directory: directory))
        XCTAssertEqual(try String(contentsOf: target), "data")
    }

    func testOnlyOneSessionCanOwnTheGlobalSetting() throws {
        let path = directory.appendingPathComponent("lock").path
        var first: SessionLock? = try SessionLock(path: path)
        try withExtendedLifetime(first) { XCTAssertThrowsError(try SessionLock(path: path)) }
        first = nil
        _ = try SessionLock(path: path)
    }

    func testWorkerStartupFailureCanQuitWithoutTouchingAnotherSession() throws {
        let script = directory.appendingPathComponent("busy-worker")
        try "#!/bin/sh\necho '{\"error\":\"Another session owns sleep\",\"fatal\":true}'\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let client = SleepWorkerClient(executable: script)
        XCTAssertThrowsError(try client.start())
        XCTAssertNoThrow(try client.stop())
    }

    func testWorkerClientCommunicatesWithoutWaitingForPipeEOF() throws {
        let script = directory.appendingPathComponent("worker")
        try """
        #!/bin/sh
        echo '{"awake":false}'
        while IFS= read -r line; do
            case "$line" in
                *shutdown*) echo '{"awake":false}'; exit 0 ;;
                *) echo '{"awake":true}' ;;
            esac
        done
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let client = SleepWorkerClient(executable: script)
        try client.start()
        try client.setAwake(true)
        XCTAssertTrue(try client.isAwake())
        try client.stop()
    }

    func testStopRetriedAfterExitTimeoutWaitsForTheWorkerToExit() throws {
        let script = directory.appendingPathComponent("slow-exit-worker")
        let exited = directory.appendingPathComponent("exited")
        try """
        #!/bin/sh
        echo '{"awake":false}'
        read -r line
        echo '{"awake":false}'
        sleep 7
        touch '\(exited.path)'
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let client = SleepWorkerClient(executable: script)
        try client.start()
        XCTAssertThrowsError(try client.stop()) // Still holding the session lock after 5 s.
        try client.stop()
        XCTAssertTrue(FileManager.default.fileExists(atPath: exited.path), "stop() succeeded before the worker exited")
    }
}
