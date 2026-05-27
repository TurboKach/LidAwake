import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    // true  = lid-close-awake on  (disablesleep 1)
    // false = normal sleep behavior (disablesleep 0)
    var awake = false
    // Cached "is in Login Items?" flag, refreshed only when the menu opens
    // (querying System Events costs a TCC automation check — don't do it at startup).
    var loginEnabled = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu-bar only, no Dock icon
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refresh()
    }

    // Re-read live state right before the menu is shown.
    func menuWillOpen(_ menu: NSMenu) {
        loginEnabled = loginItemExists()
        refresh()
    }

    func shell(_ launchPath: String, _ args: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // Set the menu-bar icon: a coffee cup when staying awake, a sleeping moon otherwise.
    func updateIcon() {
        let symbol = awake ? "cup.and.saucer.fill" : "moon.zzz"
        guard let button = statusItem.button else { return }
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol) {
            img.isTemplate = true // recolors itself for light/dark menu bar
            button.image = img
            button.title = ""
        } else {
            // SF Symbols missing (older macOS): fall back to a unicode glyph.
            button.image = nil
            button.title = awake ? "\u{2615}" : "\u{263E}"
        }
    }

    func rebuildMenu() {
        let menu = statusItem.menu!
        menu.removeAllItems()
        let status = NSMenuItem(
            title: awake ? "Stays awake when lid closed" : "Sleeps when lid closed",
            action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: awake ? "Sleep When Lid Closed" : "Stay Awake When Lid Closed",
            action: #selector(toggle), keyEquivalent: "t"))
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r"))
        menu.addItem(.separator())
        let login = NSMenuItem(
            title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "l")
        login.state = loginEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    // Ask System Events whether our app is registered as a login item.
    func loginItemExists() -> Bool {
        let out = shell("/usr/bin/osascript", ["-e",
            "tell application \"System Events\" to return (exists login item \"LidAwake\")"])
        return out.contains("true")
    }

    @objc func toggleLaunchAtLogin() {
        // Add/remove ourselves via System Events. `hidden:true` launches it without
        // stealing focus. First use prompts once for Automation permission.
        let script = loginEnabled
            ? "tell application \"System Events\" to delete login item \"LidAwake\""
            : "tell application \"System Events\" to make login item at end with properties {path:\"/Applications/LidAwake.app\", hidden:true}"
        _ = shell("/usr/bin/osascript", ["-e", script])
        loginEnabled = loginItemExists()
        rebuildMenu()
    }

    @objc func refresh() {
        // `disablesleep` is a live runtime override: it shows up in `pmset -g`
        // (the active settings) but NOT in `pmset -g custom` (the saved profile).
        // Whitespace-tolerant match of "SleepDisabled" followed by 1.
        let out = shell("/usr/bin/pmset", ["-g"])
        awake = out.range(of: "SleepDisabled\\s+1", options: .regularExpression) != nil
        updateIcon()
        rebuildMenu()
    }

    @objc func toggle() {
        let newValue = awake ? "0" : "1"
        // pmset needs root. We shell out to the Apple-signed /usr/bin/osascript, which
        // reliably shows the admin password dialog — running this same AppleScript
        // in-process (NSAppleScript) from our ad-hoc-signed app fails "Authorization failed".
        // The inner shell command is wrapped in \"...\" — those quotes are escaped for AppleScript.
        let appleScript = "do shell script \"/usr/bin/pmset -c disablesleep \(newValue)\" with administrator privileges"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", appleScript]
        let errPipe = Pipe()
        task.standardError = errPipe
        try? task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            // -128 = user clicked Cancel at the password prompt; ignore silently.
            if msg.contains("-128") || msg.contains("User canceled") { return }
            let alert = NSAlert()
            alert.messageText = "Couldn't change sleep setting"
            alert.informativeText = msg.isEmpty ? "Unknown error" : msg
            alert.runModal()
        }
        refresh() // reflect the new state after toggling
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
