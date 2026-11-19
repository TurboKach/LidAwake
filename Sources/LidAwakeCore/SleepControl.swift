import Foundation
import IOKit

public protocol SleepControlling {
    func isAwake() throws -> Bool
    func setAwake(_ awake: Bool) throws
    func stop() throws
}

protocol PowerSettings {
    func read() throws -> Bool
    func currentState() throws -> Bool
    func requireAutomaticControl() throws
    func write(_ awake: Bool) throws
}

extension PowerSettings {
    func currentState() throws -> Bool { try read() }
}

final class PMSet: PowerSettings {
    let runner: CommandRunning
    let setup: PrivilegeSetup
    private let registryState: () throws -> Bool
    private let settleTimeout: TimeInterval

    init(runner: CommandRunning, setup: PrivilegeSetup,
         registryState: @escaping () throws -> Bool = PMSet.registrySleepDisabled,
         settleTimeout: TimeInterval = 2) {
        self.runner = runner
        self.setup = setup
        self.registryState = registryState
        self.settleTimeout = settleTimeout
    }

    /// Two reads, two jobs. `read()` is the decision read: `pmset -g` is what every write is
    /// checked against, and what setAwake, stop and the probe act on. macOS 27 stopped printing
    /// `SleepDisabled` there at all, so when the key is absent the value comes from IOPMrootDomain,
    /// which still carries it. Output that does mention the key but cannot be parsed stays an
    /// error — a failed read must never be reported as sleep enabled. `currentState()` is the
    /// reporting read: the registry, with no process launched, and `pmset -g` only when the
    /// registry has no value.
    func read() throws -> Bool {
        let output = try runner.run("/usr/bin/pmset", ["-g"], timeout: 10).stdout
        do { return try Self.parse(output) }
        catch {
            guard !output.contains("SleepDisabled") else { throw error }
            return try registryState()
        }
    }

    func currentState() throws -> Bool { try (try? registryState()) ?? read() }

    /// The live kernel value, readable without root. An absent property is an error, not a default.
    static func registrySleepDisabled() throws -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { throw ControlError.message("Could not read the current sleep setting.") }
        defer { IOObjectRelease(root) }
        let property = IORegistryEntryCreateCFProperty(root, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)
        guard let value = property?.takeRetainedValue() as? Bool else {
            throw ControlError.message("Could not read the current sleep setting.")
        }
        return value
    }

    static func parse(_ output: String) throws -> Bool {
        let matches = output.split(separator: "\n").compactMap { line -> Bool? in
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard fields.count == 2, fields[0] == "SleepDisabled" else { return nil }
            return fields[1] == "1" ? true : (fields[1] == "0" ? false : nil)
        }
        guard matches.count == 1 else { throw ControlError.message("Could not read the current sleep setting.") }
        return matches[0]
    }

    func requireAutomaticControl() throws {
        guard setup.isInstalled else {
            throw ControlError.message("Enable or repair Sleep Setup before turning on keep-awake.")
        }
        try probeRule()
    }

    /// `sudo -l` succeeds for any command once an admin account has any NOPASSWD rule,
    /// so prove the rule by running the commands. Both directions are needed: the rule must also
    /// allow the restore. Writing the current value changes nothing; the opposite value is
    /// written only when that is sleep-preventing (0 -> 1 -> 0), because writing 0 could put the
    /// Mac to sleep while something else holds it awake. Starting from 0 the order also leaves
    /// the setting unchanged when the rule is one-sided: a denied 1 changes nothing, and a
    /// restore to 0 is only attempted after 0 was proven.
    func probeRule() throws {
        let current = try read()
        try sudoWrite(current)
        guard !current else { return }
        do { try sudoWrite(true) } catch {
            _ = try? sudoWrite(false)
            throw error
        }
        try write(false)
    }

    private func sudoWrite(_ awake: Bool) throws {
        // -k ignores cached admin authentication; recovery must work without it.
        _ = try runner.run("/usr/bin/sudo", ["-n", "-k", "/usr/bin/pmset", "-a", "disablesleep", awake ? "1" : "0"], timeout: 10)
    }

    /// configd hands the value to the kernel after `pmset` returns, so the registry can lag.
    /// Wait until it shows `awake`; with no registry value there is nothing to wait for.
    private func settle(_ awake: Bool) throws {
        let deadline = Date().addingTimeInterval(settleTimeout)
        while let state = try? registryState(), state != awake {
            guard Date() < deadline else { throw Self.notApplied }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    private static let notApplied = ControlError.message("macOS did not apply the sleep setting. Try Repair Sleep Setup.")

    func write(_ awake: Bool) throws {
        try sudoWrite(awake)
        try settle(awake)
        guard try read() == awake else { throw Self.notApplied }
    }
}

protocol RecoveryJournal {
    func load() throws -> Bool
    func save(_ pending: Bool) throws
}

/// Sole writer for a running app. Its journal is committed before any write that can leave
/// sleep disabled (the permission probe and the enable), so even a crash during the
/// command leaves a recoverable obligation.
final class SleepSession: SleepControlling {
    private let settings: PowerSettings
    private let journal: RecoveryJournal
    private var ownsOverride: Bool
    private var needsRecovery: Bool

    init(settings: PowerSettings, journal: RecoveryJournal) throws {
        self.settings = settings
        self.journal = journal
        ownsOverride = try journal.load()
        needsRecovery = ownsOverride
    }

    func recover() throws {
        if needsRecovery {
            try stop()
            needsRecovery = false
        }
    }

    func isAwake() throws -> Bool { try settings.currentState() }

    func setAwake(_ awake: Bool) throws {
        try recover()
        let current = try settings.read()
        if awake {
            // Check both directions before accepting ownership, even if already awake.
            if !ownsOverride {
                // The probe can leave sleep disabled (0 -> 1 -> 0), so commit the journal first.
                try journal.save(true)
                do { try settings.requireAutomaticControl() } catch {
                    releaseClaim(startedAwake: current)
                    throw error
                }
                ownsOverride = true
            }
            if !current { try settings.write(true) }
        } else {
            if current { try settings.write(false) }
            if ownsOverride { try journal.save(false) }
            ownsOverride = false
        }
    }

    /// A rejected probe hands the claim back. Keep it only if the probe left sleep disabled
    /// from a 0 start (or that cannot be told), because restoring that is now owed.
    private func releaseClaim(startedAwake: Bool) {
        if !startedAwake, (try? settings.read()) != false { ownsOverride = true; return }
        if (try? journal.save(false)) == nil { ownsOverride = true }
    }

    func stop() throws {
        guard ownsOverride else { return }
        if try settings.read() { try settings.write(false) }
        try journal.save(false)
        ownsOverride = false
        needsRecovery = false
    }
}

public struct SleepPolicy: Codable, Equatable {
    public var isEnabled: Bool
    public var onAC: Bool
    public var onBattery: Bool
    public init(isEnabled: Bool = false, onAC: Bool = true, onBattery: Bool = true) {
        self.isEnabled = isEnabled
        self.onAC = onAC
        self.onBattery = onBattery
    }
    public func desired(onACPower: Bool) -> Bool { isEnabled && (onACPower ? onAC : onBattery) }
    /// The switch is ON only while a condition is checked; a state that breaks this is the fresh-install state.
    public var normalized: SleepPolicy { isEnabled && !onAC && !onBattery ? SleepPolicy() : self }
}

/// Policy preferences commit only after a successful change for the active source.
/// Inactive-source edits never touch the current global setting.
public final class PolicyController {
    public private(set) var policy: SleepPolicy
    private let sleep: SleepControlling
    private let onACPower: () -> Bool
    private let persist: (SleepPolicy) -> Void

    public init(policy: SleepPolicy, sleep: SleepControlling, onACPower: @escaping () -> Bool,
                persist: @escaping (SleepPolicy) -> Void) {
        self.policy = policy.normalized
        self.sleep = sleep
        self.onACPower = onACPower
        self.persist = persist
    }

    public func reconcile() throws { try sleep.setAwake(policy.desired(onACPower: onACPower())) }

    public func setEnabled(_ enabled: Bool) throws {
        var candidate = policy
        candidate.isEnabled = enabled
        if enabled && !candidate.onAC && !candidate.onBattery { candidate.onAC = true; candidate.onBattery = true }
        try sleep.setAwake(candidate.desired(onACPower: onACPower()))
        policy = candidate
        persist(candidate)
    }

    public func toggle(onAC: Bool) throws {
        var candidate = policy
        if onAC { candidate.onAC.toggle() } else { candidate.onBattery.toggle() }
        let wasEnabled = candidate.isEnabled
        if !candidate.onAC && !candidate.onBattery { candidate.isEnabled = false }
        if wasEnabled && onACPower() == onAC {
            try sleep.setAwake(candidate.desired(onACPower: onAC))
        }
        policy = candidate
        persist(candidate)
    }

    public func stop() throws { try sleep.stop() }
}
