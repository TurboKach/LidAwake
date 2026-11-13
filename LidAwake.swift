import Cocoa
import IOKit.ps
import CoreGraphics
import LidAwakeCore

private func L(_ key: String, _ args: CVarArg...) -> String {
    let text = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    return args.isEmpty ? text : String(format: text, arguments: args)
}

private func onACPower() -> Bool {
    let blob = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    return IOPSGetProvidingPowerSourceType(blob).takeUnretainedValue() as String == kIOPSACPowerValue
}

private struct MenuState {
    var policy = SleepPolicy()
    var awake: Bool?
    var onAC = true
    var setupReady = false
    var loginEnabled: Bool?
    var error: String?
    var loginError: String?
}

/// All blocking work and mutable power policy live on AppDelegate.workQueue.
private final class AppRuntime {
    let runner = ProcessCommandRunner()
    private(set) var sleep = SleepWorkerClient(executable: Bundle.main.executableURL!)
    lazy var setup = PrivilegeSetup(
        runner: InProcessAppleScriptRunner(),
        installPrompt: L("LidAwake needs an administrator to install its sleep rule."),
        uninstallPrompt: L("LidAwake needs an administrator to remove its sleep rule."))
    lazy var login = LoginItems(runner: runner, bundleURL: Bundle.main.bundleURL)
    private(set) lazy var controller = makeController(
        policy: SleepPolicy(isEnabled: UserDefaults.standard.bool(forKey: "lidAwakeEnabled"),
                            onAC: UserDefaults.standard.bool(forKey: "awakeOnAC"),
                            onBattery: UserDefaults.standard.bool(forKey: "awakeOnBattery")))
    var loginEnabled: Bool?
    var loginError: String?

    private func makeController(policy: SleepPolicy) -> PolicyController {
        PolicyController(policy: policy, sleep: sleep, onACPower: onACPower, persist: { policy in
            UserDefaults.standard.set(policy.isEnabled, forKey: "lidAwakeEnabled")
            UserDefaults.standard.set(policy.onAC, forKey: "awakeOnAC")
            UserDefaults.standard.set(policy.onBattery, forKey: "awakeOnBattery")
        })
    }

    /// Turns off the login item, stops the worker, then restores sleep and removes the sudoers
    /// rules with one admin prompt. Failures report what was actually removed; while any rule
    /// remains a new worker takes over. Returns true when the legacy rule was left in place.
    func uninstallApp() throws -> Bool {
        let uninstaller = Uninstaller(login: login, rules: setup, dataDirectory: FileManager.default
            .homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/LidAwake", isDirectory: true))
        do {
            return try uninstaller.run(stopSleep: { try controller.stop() }, resumeSleep: {
                // The stopped worker has exited, so the new one can take the session lock.
                let worker = SleepWorkerClient(executable: Bundle.main.executableURL!)
                try worker.start()
                sleep = worker
                controller = makeController(policy: controller.policy)
            }, removeSettings: {
                if let domain = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: domain) }
            })
        } catch Uninstaller.Failure.nothingRemoved(let cause, let loginItemOff) {
            if cause as? ControlError == .canceled && !loginItemOff { throw cause }
            let login = loginItemOff ? L(" Nothing else was removed, but Launch at Login is now off; turn it back on from the menu.")
                                     : L(" Nothing was removed.")
            throw ControlError.message(L("LidAwake was not uninstalled.") + login + "\n\n" + cause.localizedDescription)
        } catch Uninstaller.Failure.incomplete(let remaining, let cause) {
            throw ControlError.message(L("LidAwake was only partly uninstalled. These items remain:\n")
                + remaining.joined(separator: "\n")
                + L("\n\nRemove them manually (for files in /etc/sudoers.d, run “sudo rm <path>” in Terminal), or fix the cause and choose Uninstall LidAwake… again.\n\n")
                + cause.localizedDescription)
        }
    }

    func refreshLogin() {
        do { loginEnabled = try login.isEnabled(); loginError = nil }
        catch { loginEnabled = nil; loginError = error.localizedDescription }
    }

    func snapshot(error: Error? = nil) -> MenuState {
        var result = MenuState(policy: controller.policy, onAC: onACPower(), setupReady: setup.isInstalled,
                               loginEnabled: loginEnabled, error: error?.localizedDescription, loginError: loginError)
        do { result.awake = try sleep.isAwake() }
        catch { result.awake = nil; result.error = result.error ?? error.localizedDescription }
        return result
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let workQueue = DispatchQueue(label: "local.lidawake.control", qos: .utility)
    private let runtime = AppRuntime()
    private var state = MenuState()
    private var busy = false
    private var pendingOperations = 0
    private var pendingUserOperations = 0
    private var menuRenderer: StableMenu?
    private var displayedSymbol: String?
    private var displayedIconDescription: String?
    private var refreshPending = false
    private var gate = TerminationGate()
    private var terminating: Bool { gate.terminating }
    private var checkingUpdates = false
    private var powerSource: CFRunLoopSource?
    private var timer: Timer?
    private var offExternal: Bool {
        get { UserDefaults.standard.bool(forKey: "offExternalOnLidClose") }
        set { UserDefaults.standard.set(newValue, forKey: "offExternalOnLidClose") }
    }
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Existing installations keep applying their saved AC/battery choices.
        UserDefaults.standard.register(defaults: ["offExternalOnLidClose": true, "lidAwakeEnabled": true])
        NSApp.setActivationPolicy(.accessory)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        menuRenderer = StableMenu(menu: menu)
        updateUI()
        startPowerMonitor()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        perform({ runtime in
            try runtime.sleep.start()
            try runtime.controller.reconcile()
        }, completion: { [weak self] _ in
            guard let self = self else { return }
            if !self.state.setupReady && !UserDefaults.standard.bool(forKey: "sleepSetupOfferedV2") {
                UserDefaults.standard.set(true, forKey: "sleepSetupOfferedV2")
                self.promptSetup()
            }
        })
    }

    // Quit waits for verified restoration. A crash instead closes the worker's
    // input pipe, which invokes the same cleanup independently of AppKit.
    // A quit during an uninstall waits for the uninstall's outcome (see uninstallApp);
    // the quit after a successful uninstall has nothing to restore and terminates at once.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        switch gate.requestQuit() {
        case .terminateNow: return .terminateNow  // after a successful uninstall: nothing left to restore
        case .start: restoreSleepThenReply(sender); return .terminateLater
        case .alreadyTerminating, .afterUninstall: return .terminateLater
        }
    }

    private func restoreSleepThenReply(_ sender: NSApplication) {
        busy = true
        updateUI()
        workQueue.async {
            var failure: Error?
            do { try self.runtime.controller.stop() } catch { failure = error }
            DispatchQueue.main.async {
                if let failure = failure {
                    let alert = NSAlert()
                    alert.messageText = L("Sleep could not be restored")
                    alert.informativeText = L("The Mac may remain awake. Stay open to repair Sleep Setup and try again.\n\n") + failure.localizedDescription
                    alert.addButton(withTitle: L("Stay Open"))
                    alert.addButton(withTitle: L("Quit Anyway"))
                    let quit = alert.runModal() == .alertSecondButtonReturn
                    if !quit { self.gate.cancelQuit() }
                    self.busy = quit
                    sender.reply(toApplicationShouldTerminate: quit)
                    if !quit { self.updateUI() }
                } else { sender.reply(toApplicationShouldTerminate: true) }
            }
        }
    }

    private func perform(_ work: @escaping (AppRuntime) throws -> Void,
                         showFailure: Bool = false, affectsSleep: Bool = true,
                         completion: ((Error?) -> Void)? = nil) {
        guard !terminating else { return }
        // Polls coalesce; an explicit action (including an admin alert response)
        // must remain queued if a timer fired while the alert was open.
        guard !busy || showFailure else { refreshPending = true; return }
        pendingOperations += 1
        busy = true
        if showFailure {
            pendingUserOperations += 1
            updateUI()
        }
        workQueue.async {
            var failure: Error?
            do { try work(self.runtime) } catch { failure = error }
            let snapshot = self.runtime.snapshot(error: affectsSleep ? failure : nil)
            DispatchQueue.main.async {
                self.pendingOperations -= 1
                if showFailure { self.pendingUserOperations -= 1 }
                guard !self.terminating else { return }
                self.state = snapshot
                self.busy = self.pendingOperations > 0
                self.updateUI()
                if showFailure, let failure = failure, failure as? ControlError != .canceled {
                    self.showError(failure.localizedDescription)
                }
                completion?(failure)
                if self.refreshPending && !self.busy {
                    self.refreshPending = false
                    self.tick()
                }
            }
        }
    }

    private func startPowerMonitor() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context = context else { return }
            Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue().tick()
        }, context)?.takeRetainedValue() else {
            // The two-second reconciliation timer also detects source changes.
            return
        }
        powerSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    private func tick() {
        let blankDisplay = shouldBlankDisplay()
        perform { runtime in
            var failure: Error?
            do { try runtime.controller.reconcile() } catch { failure = error }
            // Blanking still matters if a failed restore left the machine awake.
            if runtime.controller.policy.isEnabled && blankDisplay, try runtime.sleep.isAwake() {
                _ = try runtime.runner.run("/usr/bin/pmset", ["displaysleepnow"], timeout: 10)
            }
            if let failure = failure { throw failure }
        }
    }

    private func shouldBlankDisplay() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        let property = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        guard property?.takeRetainedValue() as? Bool == true else { return false }
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return false }
        let online = displays.prefix(Int(count))
        if !offExternal && online.contains(where: { CGDisplayIsBuiltin($0) == 0 }) { return false }
        return online.contains { CGDisplayIsAsleep($0) == 0 }
    }

    private var sleepSymbol: String {
        state.awake == nil || state.error != nil ? "exclamationmark.triangle"
            : (state.awake == true ? "cup.and.saucer.fill" : "moon.zzz")
    }

    private func updateUI() {
        let unavailable = state.awake == nil || state.error != nil
        let symbol = sleepSymbol
        let description = state.awake.map { $0 ? L("Staying awake") : L("Sleep enabled") }
            ?? L("Sleep status unavailable")
        if let button = statusItem.button {
            if displayedSymbol != symbol || displayedIconDescription != description {
                let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
                image?.isTemplate = true
                button.image = image
                button.title = image == nil ? (unavailable ? "⚠" : (state.awake == true ? "☕" : "☾")) : ""
                displayedSymbol = symbol
                displayedIconDescription = description
            }
            let tooltip = state.error ?? description
            if button.toolTip != tooltip { button.toolTip = tooltip }
        }
        updateMenu()
    }

    private func updateMenu() {
        var entries = [MenuEntry]()
        // A running user operation never dims a row: each action refuses to start while one runs
        // (`pendingUserOperations`), and `operationInFlight` only holds a clicked switch in place.
        let controlsEnabled = !gate.locksMenuActions
        let awakeControlsEnabled = controlsEnabled && state.policy.isEnabled
        func item(_ id: String, _ title: String, _ action: Selector? = nil, key: String = "",
                  checked: Bool? = false, enabled: Bool = true, indent: Int = 0, symbol: String? = nil,
                  style: MenuEntry.Style = .standard) {
            let checkState: NSControl.StateValue = checked.map { $0 ? .on : .off } ?? .mixed
            entries.append(MenuEntry(id: id, title: title, action: action, keyEquivalent: key,
                                     state: checkState, enabled: enabled, indentationLevel: indent, style: style, symbol: symbol))
        }
        let source = state.onAC ? L("AC power") : L("Battery")
        let status = state.awake.map { $0 ? L("Staying awake") : L("Sleep enabled") }
            ?? L("Sleep status unavailable")
        entries.append(MenuEntry(id: "enabled", title: "LidAwake", action: #selector(toggleEnabled),
                                 keyEquivalent: "e", state: state.policy.isEnabled ? .on : .off,
                                 enabled: controlsEnabled, style: .toggle,
                                 subtitle: "\(status) · \(source)", symbol: sleepSymbol))
        if state.error != nil {
            item("error", L("Sleep setting needs attention…"), #selector(showSleepError))
        }
        entries.append(.separator("power-separator"))
        item("power-heading", L("Keep awake when:"))
        item("ac", L("Connected to Power"), #selector(toggleAC), checked: state.policy.onAC, enabled: awakeControlsEnabled, indent: 1, symbol: "powerplug.fill", style: .compactToggle)
        item("battery", L("On Battery"), #selector(toggleBattery), checked: state.policy.onBattery, enabled: awakeControlsEnabled, indent: 1, symbol: "battery.100", style: .compactToggle)
        entries.append(.separator("display-separator"))
        item("external", L("Turn Off External Display on Lid Close"), #selector(toggleExternal), checked: offExternal, enabled: awakeControlsEnabled)
        entries.append(.separator("setup-separator"))
        item("setup", state.setupReady ? L("Repair Sleep Setup…") : L("Enable Automatic Sleep Control…"), #selector(setupSleep), enabled: controlsEnabled)
        item("uninstall-app", L("Uninstall LidAwake…"), #selector(uninstallApp), enabled: controlsEnabled)
        entries.append(.separator("login-separator"))
        item("login", L("Launch at Login"), #selector(toggleLogin), key: "l", checked: state.loginEnabled, enabled: controlsEnabled)
        entries.append(.separator("about-separator"))
        item("about", L("About LidAwake"), #selector(showAbout))
        item("updates", checkingUpdates ? L("Checking for Updates…") : L("Check for Updates…"), #selector(checkForUpdates), enabled: !checkingUpdates)
        entries.append(.separator("quit-separator"))
        item("quit", L("Quit"), #selector(quitApp), key: "q", enabled: !terminating)
        menuRenderer?.update(entries, target: self, operationInFlight: pendingUserOperations > 0)
    }

    @objc private func quitApp() { NSApp.terminate(nil) }

    func menuWillOpen(_ menu: NSMenu) {
        perform { $0.refreshLogin() }
    }

    @objc private func toggleEnabled() {
        guard pendingUserOperations == 0 && !terminating else { return }
        if !state.policy.isEnabled && !state.setupReady {
            promptSetup { [weak self] in self?.toggleEnabled() }
        } else {
            perform({ try $0.controller.setEnabled(!$0.controller.policy.isEnabled) }, showFailure: true)
        }
    }
    @objc private func toggleAC() { toggle(onAC: true) }
    @objc private func toggleBattery() { toggle(onAC: false) }
    private func toggle(onAC: Bool) {
        guard state.policy.isEnabled && pendingUserOperations == 0 && !terminating else { return }
        let enabling = !(onAC ? state.policy.onAC : state.policy.onBattery)
        if enabling && !state.setupReady {
            promptSetup { [weak self] in self?.toggle(onAC: onAC) }
        } else { perform({ try $0.controller.toggle(onAC: onAC) }, showFailure: true) }
    }
    @objc private func toggleExternal() {
        guard state.policy.isEnabled && pendingUserOperations == 0 && !terminating else { return }
        offExternal.toggle()
        updateUI()
    }
    @objc private func setupSleep() {
        guard pendingUserOperations == 0 else { return }
        promptSetup()
    }
    private func promptSetup(afterSuccess: (() -> Void)? = nil) {
        statusItem.menu?.cancelTracking()
        let alert = NSAlert()
        alert.messageText = L("Let LidAwake manage sleep automatically?")
        alert.informativeText = L(
            "One admin approval lets LidAwake switch sleep on AC and battery and restore sleep when you quit or the menu app crashes. Only the two sleep-toggle commands are allowed without a password. Existing LidAwake rules will be narrowed to those commands.")
        alert.addButton(withTitle: L("Enable"))
        alert.addButton(withTitle: L("Not Now"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform({ runtime in
            try runtime.setup.install()
            try runtime.controller.reconcile()
        }, showFailure: true, completion: { error in if error == nil { afterSuccess?() } })
    }
    @objc private func uninstallApp() {
        guard pendingUserOperations == 0 else { return }
        statusItem.menu?.cancelTracking()
        let alert = NSAlert()
        alert.messageText = L("Uninstall LidAwake?")
        alert.informativeText = L(
            "LidAwake restores normal sleep, then removes:\n• its sleep rules /etc/sudoers.d/lidawake-%@ and, if it names this account, /etc/sudoers.d/lidawake (macOS asks for an administrator password)\n• its login item\n• its settings and ~/Library/Application Support/LidAwake\n• the app itself, moved to the Trash\n\nThen LidAwake quits.", "\(getuid())")
        alert.addButton(withTitle: L("Uninstall"))
        alert.addButton(withTitle: L("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn, gate.beginUninstall() else { return }
        var keptLegacyRule = false
        perform({ runtime in
            do { keptLegacyRule = try runtime.uninstallApp() } catch {
                // The new worker applies the policy again; its failure shows in the menu status,
                // never in place of what the uninstall actually did.
                try? runtime.controller.reconcile()
                throw error
            }
        }, showFailure: true, completion: { [weak self] error in
            guard let self = self else { return }
            if error as? ControlError == .canceled {
                self.showError(L("Uninstall was canceled. Nothing was removed."))
            }
            guard error == nil else {
                // Sleep control was handed back to a new worker; a quit requested meanwhile runs now.
                if self.gate.endUninstall() { self.restoreSleepThenReply(NSApp) } else { self.updateUI() }
                return
            }
            if keptLegacyRule {
                self.showError(L("LidAwake was uninstalled. Left /etc/sudoers.d/lidawake in place because it belongs to another account or has content LidAwake does not recognize."))
            }
            NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self.showError(L("LidAwake was uninstalled, but the app could not be moved to the Trash. Move it to the Trash yourself.\n\n") + error.localizedDescription)
                    }
                    // Sleep is already restored and the worker stopped by the uninstall.
                    if self.gate.endUninstall(succeeded: true) { NSApp.reply(toApplicationShouldTerminate: true) } else { NSApp.terminate(nil) }
                }
            }
        })
    }
    @objc private func toggleLogin() {
        guard pendingUserOperations == 0 else { return }
        perform({ runtime in
            do {
                try runtime.login.setEnabled(!runtime.login.isEnabled())
                runtime.refreshLogin()
            } catch {
                runtime.refreshLogin()
                throw error
            }
        }, showFailure: true, affectsSleep: false)
    }
    @objc private func showSleepError() { showError(state.error ?? L("Unknown error")) }
    private func showError(_ message: String) {
        statusItem.menu?.cancelTracking()
        let alert = NSAlert()
        alert.messageText = L("LidAwake needs attention")
        alert.informativeText = message
        alert.runModal()
    }
    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSMutableAttributedString(string: L("Developed by ") + ProjectInfo.developer + "\n")
        credits.append(NSAttributedString(string: ProjectInfo.repository.absoluteString,
                                          attributes: [.link: ProjectInfo.repository]))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits, .applicationVersion: version])
    }
    @objc private func checkForUpdates() {
        checkingUpdates = true
        updateMenu()
        Task { @MainActor in
            defer { checkingUpdates = false; updateMenu() }
            do {
                let result = try await GitHubUpdates().check(currentVersion: version)
                let alert = NSAlert()
                switch result {
                case .available(let latest, let url):
                    alert.messageText = L("LidAwake %@ is available", latest)
                    alert.informativeText = L("You’re running %@. Open the release page to download the update.", version)
                    alert.addButton(withTitle: L("Open Release"))
                    alert.addButton(withTitle: L("Later"))
                    if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(url) }
                case .current:
                    alert.messageText = L("LidAwake is up to date")
                    alert.informativeText = L("You’re running version %@.", version)
                    alert.runModal()
                case .noReleases:
                    alert.messageText = L("No releases available yet")
                    alert.informativeText = L("There are no public releases on GitHub yet.")
                    alert.runModal()
                }
            } catch { showError(error.localizedDescription) }
        }
    }
}

@main
struct LidAwakeMain {
    static func main() {
        signal(SIGPIPE, SIG_IGN)
        if CommandLine.arguments.dropFirst() == ["--sleep-worker"] { exit(SleepWorker.run()) }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
