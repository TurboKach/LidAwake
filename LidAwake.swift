import Cocoa
import IOKit.ps
import CoreGraphics

// LidAwake keeps a per-power-source policy: independently decide whether the Mac
// stays awake on lid close while on AC vs. on battery. `disablesleep` is a single
// GLOBAL live value (not stored per-source and not auto-switched by macOS), so this
// app detects the power source and writes the right value itself on every change.
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let sudoersPath = "/etc/sudoers.d/lidawake"
    var powerSource: CFRunLoopSource?
    var awake = false        // cached live SleepDisabled, for the icon
    var loginEnabled = false // cached "in Login Items?", refreshed when menu opens

    // Per-source policy (default: sleep normally on both).
    var awakeOnAC: Bool {
        get { UserDefaults.standard.bool(forKey: "awakeOnAC") }
        set { UserDefaults.standard.set(newValue, forKey: "awakeOnAC") }
    }
    var awakeOnBattery: Bool {
        get { UserDefaults.standard.bool(forKey: "awakeOnBattery") }
        set { UserDefaults.standard.set(newValue, forKey: "awakeOnBattery") }
    }
    // When staying awake with the lid closed, also turn off an attached external
    // display (fully headless) instead of leaving it on for clamshell. Defaults to on.
    var offExternalOnLidClose: Bool {
        get { UserDefaults.standard.bool(forKey: "offExternalOnLidClose") }
        set { UserDefaults.standard.set(newValue, forKey: "offExternalOnLidClose") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["offExternalOnLidClose": true])
        NSApp.setActivationPolicy(.accessory) // menu-bar only, no Dock icon
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        if !hasPasswordlessSetup { promptSetup() } // ask once, right after install
        startPowerMonitor()
        applyForCurrentSource(auto: true)
        // Poll the lid so we can sleep the internal display on lid close (see lidTick).
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.lidTick() }
    }

    // MARK: - Lid → display off

    // While staying awake with the lid closed, `disablesleep` keeps displays powered.
    // So when the lid is shut, put the screen to sleep ourselves — the Mac stays awake,
    // only the display turns off. The internal panel is always blanked; an external is
    // blanked too unless the user keeps it on for clamshell (offExternalOnLidClose).
    func lidTick() {
        guard lidClosed() else { return }
        let stayAwake = onACPower() ? awakeOnAC : awakeOnBattery
        guard stayAwake else { return }
        if hasExternalDisplay() && !offExternalOnLidClose { return } // clamshell: leave external on
        if CGDisplayIsAsleep(CGMainDisplayID()) == 0 {               // a display still on → sleep it
            shell("/usr/bin/pmset", ["displaysleepnow"])             // no root needed
        }
    }

    // AppleClamshellState on IOPMrootDomain: true == lid closed (verified empirically).
    func lidClosed() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        let p = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        return (p?.takeRetainedValue() as? Bool) ?? false
    }

    // True if any online display is not the built-in panel (i.e. an external is attached).
    func hasExternalDisplay() -> Bool {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        guard count > 0 else { return false }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return ids.contains { CGDisplayIsBuiltin($0) == 0 }
    }

    // MARK: - Power source

    // True when the Mac is running on the wall charger.
    func onACPower() -> Bool {
        let blob = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let type = IOPSGetProvidingPowerSourceType(blob).takeUnretainedValue() as String
        return type == kIOPSACPowerValue
    }

    // Fire applyForCurrentSource() whenever the power source changes (plug/unplug).
    func startPowerMonitor() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let src = IOPSNotificationCreateRunLoopSource({ ctx in
            Unmanaged<AppDelegate>.fromOpaque(ctx!).takeUnretainedValue().applyForCurrentSource(auto: true)
        }, ctx)?.takeRetainedValue() else { return }
        powerSource = src
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .defaultMode)
    }

    // Bring the live setting in line with the current source's policy, then refresh UI.
    // `auto` events (launch, plug/unplug) skip the change when not passwordless, so we
    // never surprise the user with a password dialog they didn't trigger.
    func applyForCurrentSource(auto: Bool) {
        let desired = onACPower() ? awakeOnAC : awakeOnBattery
        if liveAwake() != desired, !(auto && !hasPasswordlessSetup) {
            setDisableSleep(desired)
        }
        updateUI()
    }

    // MARK: - pmset

    func liveAwake() -> Bool {
        // `disablesleep` is a live override shown by `pmset -g` (not `-g custom`).
        shell("/usr/bin/pmset", ["-g"]).range(of: "SleepDisabled\\s+1", options: .regularExpression) != nil
    }

    func setDisableSleep(_ disabled: Bool) {
        let v = disabled ? "1" : "0"
        if hasPasswordlessSetup {
            _ = shell("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", v]) // no prompt
        } else {
            runAdmin("/usr/bin/pmset -a disablesleep \(v)") // prompts for password
        }
    }

    // MARK: - One-time privileged setup

    var hasPasswordlessSetup: Bool { FileManager.default.fileExists(atPath: sudoersPath) }

    func promptSetup() {
        let alert = NSAlert()
        alert.messageText = "Let LidAwake manage sleep automatically?"
        alert.informativeText = "LidAwake can switch lid-close sleep for AC and battery on its own. "
            + "This needs a one-time admin approval so it never asks for your password again."
        alert.addButton(withTitle: "Enable")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn { installSudoersRule() }
    }

    func installSudoersRule() {
        // Scoped NOPASSWD rule: only `pmset … disablesleep`, nothing else.
        let rule = "\(NSUserName()) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep *,"
            + " /usr/bin/pmset -b disablesleep *, /usr/bin/pmset -c disablesleep *"
        // Validate with `visudo -cf` before installing — a malformed file would break sudo.
        // No double quotes in this command, so it embeds cleanly in the AppleScript string.
        let sh = "f=$(mktemp) && echo '\(rule)' > $f && /usr/sbin/visudo -cf $f"
            + " && /usr/bin/install -m 0440 -o root -g wheel $f \(sudoersPath); rm -f $f"
        runAdmin(sh)
    }

    // MARK: - Shell helpers

    @discardableResult
    func shell(_ launchPath: String, _ args: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    // Run a shell command as root via the Apple-signed osascript (reliable from an
    // ad-hoc-signed app, unlike in-process NSAppleScript). Inner quotes are escaped for AppleScript.
    @discardableResult
    func runAdmin(_ shellCmd: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "do shell script \"\(shellCmd)\" with administrator privileges"]
        let errPipe = Pipe()
        task.standardError = errPipe
        try? task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if msg.contains("-128") || msg.contains("User canceled") { return false } // user hit Cancel
            let alert = NSAlert()
            alert.messageText = "LidAwake couldn't change the setting"
            alert.informativeText = msg.isEmpty ? "Unknown error" : msg
            alert.runModal()
            return false
        }
        return true
    }

    // MARK: - UI

    func updateUI() {
        awake = liveAwake()
        updateIcon()
        rebuildMenu()
    }

    // Coffee cup when staying awake, sleeping moon otherwise.
    func updateIcon() {
        let symbol = awake ? "cup.and.saucer.fill" : "moon.zzz"
        guard let button = statusItem.button else { return }
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol) {
            img.isTemplate = true // recolors itself for light/dark menu bar
            button.image = img
            button.title = ""
        } else {
            button.image = nil // SF Symbols missing: fall back to a unicode glyph
            button.title = awake ? "\u{2615}" : "\u{263E}"
        }
    }

    func rebuildMenu() {
        let menu = statusItem.menu!
        menu.removeAllItems()
        let onAC = onACPower()
        let status = NSMenuItem(
            title: "On \(onAC ? "AC power" : "battery") · " + (awake ? "staying awake" : "sleeps on lid close"),
            action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        let ac = NSMenuItem(title: "Stay Awake on AC Power", action: #selector(toggleAC), keyEquivalent: "")
        ac.state = awakeOnAC ? .on : .off
        menu.addItem(ac)
        let bat = NSMenuItem(title: "Stay Awake on Battery", action: #selector(toggleBattery), keyEquivalent: "")
        bat.state = awakeOnBattery ? .on : .off
        menu.addItem(bat)
        let ext = NSMenuItem(title: "Turn Off External Display on Lid Close", action: #selector(toggleExternal), keyEquivalent: "")
        ext.state = offExternalOnLidClose ? .on : .off
        menu.addItem(ext)
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "l")
        login.state = loginEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    func menuWillOpen(_ menu: NSMenu) {
        loginEnabled = loginItemExists()
        updateUI()
    }

    // MARK: - Actions

    @objc func toggleAC() { awakeOnAC.toggle(); applyForCurrentSource(auto: false) }
    @objc func toggleBattery() { awakeOnBattery.toggle(); applyForCurrentSource(auto: false) }
    @objc func toggleExternal() { offExternalOnLidClose.toggle(); rebuildMenu() }

    // MARK: - Login item (via System Events)

    func loginItemExists() -> Bool {
        shell("/usr/bin/osascript", ["-e",
            "tell application \"System Events\" to return (exists login item \"LidAwake\")"]).contains("true")
    }

    @objc func toggleLaunchAtLogin() {
        // `hidden:true` launches without stealing focus. First use prompts once for Automation access.
        let script = loginEnabled
            ? "tell application \"System Events\" to delete login item \"LidAwake\""
            : "tell application \"System Events\" to make login item at end with properties {path:\"/Applications/LidAwake.app\", hidden:true}"
        _ = shell("/usr/bin/osascript", ["-e", script])
        loginEnabled = loginItemExists()
        rebuildMenu()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
