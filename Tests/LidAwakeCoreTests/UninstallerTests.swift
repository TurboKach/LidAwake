import XCTest
@testable import LidAwakeCore

private final class FakeLogin: Uninstaller.LoginItem {
    var enabled: Bool
    var failsToDisable = false
    init(enabled: Bool) { self.enabled = enabled }
    func isEnabled() throws -> Bool { enabled }
    func setEnabled(_ enabled: Bool) throws {
        if !enabled && failsToDisable { throw ControlError.message("Automation access denied.") }
        self.enabled = enabled
    }
}

final class UninstallerTests: XCTestCase {
    private var directory: URL!
    private var data: URL!
    private var runner: RecordingRunner!
    private var setup: PrivilegeSetup!
    private var stops = 0, resumes = 0, settingsRemoved = false

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        data = directory.appendingPathComponent("support/LidAwake")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        runner = RecordingRunner()
        setup = PrivilegeSetup(runner: runner, uid: 502, directory: directory.path)
        for rule in [setup.path, directory.appendingPathComponent("lidawake").path] {
            try "rule\n".write(toFile: rule, atomically: true, encoding: .utf8)
        }
    }
    override func tearDownWithError() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: data.deletingLastPathComponent().path)
        try FileManager.default.removeItem(at: directory)
    }

    @discardableResult
    private func run(_ login: FakeLogin) throws -> Bool {
        try Uninstaller(login: login, rules: setup, dataDirectory: data).run(
            stopSleep: { stops += 1 }, resumeSleep: { resumes += 1 }, removeSettings: { settingsRemoved = true })
    }
    private var legacy: String { directory.appendingPathComponent("lidawake").path }

    private func assertNothingRemoved(_ error: Error, loginItemOff: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        guard case let Uninstaller.Failure.nothingRemoved(_, off) = error else {
            return XCTFail("Expected nothingRemoved, got \(error)", file: file, line: line)
        }
        XCTAssertEqual(off, loginItemOff, file: file, line: line)
        XCTAssertEqual(setup.remainingRules, [setup.path, legacy], file: file, line: line)
        XCTAssertTrue(FileManager.default.fileExists(atPath: data.path), file: file, line: line)
        XCTAssertFalse(settingsRemoved, file: file, line: line)
    }

    func testLoginItemFailureAbortsBeforeAnythingIsTouched() {
        let login = FakeLogin(enabled: true)
        login.failsToDisable = true
        XCTAssertThrowsError(try run(login)) { assertNothingRemoved($0) }
        XCTAssertEqual(stops, 0)
        XCTAssertTrue(runner.calls.isEmpty && runner.scripts.isEmpty) // No admin prompt.
        XCTAssertTrue(login.enabled)
    }

    func testCanceledAdminPromptRestoresTheLoginItemAndRemovesNothing() {
        let login = FakeLogin(enabled: true)
        runner.respond = { _ in XCTAssertFalse(login.enabled); throw ControlError.canceled }
        XCTAssertThrowsError(try run(login)) { error in
            assertNothingRemoved(error)
            guard case let Uninstaller.Failure.nothingRemoved(cause, _) = error else { return }
            XCTAssertEqual(cause as? ControlError, .canceled)
        }
        XCTAssertTrue(login.enabled)
        XCTAssertEqual(stops, 1)
        XCTAssertEqual(resumes, 1)
    }

    func testAdminScriptThatSucceedsWithoutRemovingTheRulesIsNotReportedAsUninstalled() {
        let login = FakeLogin(enabled: false)
        XCTAssertThrowsError(try run(login)) { assertNothingRemoved($0) }
        XCTAssertEqual(resumes, 1)
    }

    func testPartialRuleRemovalReportsWhatRemains() {
        let login = FakeLogin(enabled: true)
        runner.respond = { [setup] _ in
            try? FileManager.default.removeItem(atPath: setup!.path)
            throw ControlError.message("rm: legacy: Operation not permitted")
        }
        XCTAssertThrowsError(try run(login)) { error in
            guard case let Uninstaller.Failure.incomplete(remaining, _) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(remaining, [self.legacy])
        }
        XCTAssertEqual(resumes, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: data.path))
    }

    func testDataDirectoryThatCannotBeRemovedIsReported() throws {
        runner.respond = { [setup, legacy] _ in
            try? FileManager.default.removeItem(atPath: setup!.path)
            try? FileManager.default.removeItem(atPath: legacy)
            return CommandOutput()
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: data.deletingLastPathComponent().path)
        XCTAssertThrowsError(try run(FakeLogin(enabled: false))) { error in
            guard case let Uninstaller.Failure.incomplete(remaining, _) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(remaining, [self.data.path])
        }
    }

    func testLegacyRuleKeptByTheScriptStillCountsAsUninstalled() throws {
        runner.respond = { [setup] _ in
            try? FileManager.default.removeItem(atPath: setup!.path)
            return CommandOutput(stdout: "kept-legacy\n")
        }
        XCTAssertTrue(try run(FakeLogin(enabled: true)))
        XCTAssertEqual(setup.remainingRules, [legacy])
        XCTAssertFalse(FileManager.default.fileExists(atPath: data.path))
        XCTAssertTrue(settingsRemoved)
    }

    func testLegacyRuleLeftWithoutTheScriptKeepingItIsIncomplete() {
        runner.respond = { [setup] _ in
            try? FileManager.default.removeItem(atPath: setup!.path)
            return CommandOutput()
        }
        XCTAssertThrowsError(try run(FakeLogin(enabled: true))) { error in
            guard case let Uninstaller.Failure.incomplete(remaining, _) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(remaining, [self.legacy])
        }
    }

    func testSuccessfulUninstallRemovesEverythingAndToleratesMissingData() throws {
        runner.respond = { [setup, legacy] _ in
            try? FileManager.default.removeItem(atPath: setup!.path)
            try? FileManager.default.removeItem(atPath: legacy)
            return CommandOutput()
        }
        let login = FakeLogin(enabled: true)
        XCTAssertFalse(try run(login))
        XCTAssertFalse(login.enabled)
        XCTAssertEqual(stops, 1)
        XCTAssertEqual(resumes, 0)
        XCTAssertEqual(setup.remainingRules, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: data.path))
        XCTAssertTrue(settingsRemoved)
        try run(login) // Already uninstalled: nothing left is not a failure.
    }
}
