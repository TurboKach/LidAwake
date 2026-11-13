import Foundation
import Darwin

public final class PrivilegeSetup {
    public let path: String
    private let uid: uid_t
    private let runner: CommandRunning
    private let legacyPath: String
    private let installPrompt: String?
    private let uninstallPrompt: String?

    /// The prompts are the texts of the system's admin password dialogs; nil keeps the system's default.
    public init(runner: CommandRunning, uid: uid_t = getuid(), directory: String = "/etc/sudoers.d",
                installPrompt: String? = nil, uninstallPrompt: String? = nil) {
        self.runner = runner
        self.uid = uid
        self.installPrompt = installPrompt
        self.uninstallPrompt = uninstallPrompt
        path = directory + "/lidawake-\(uid)"
        legacyPath = directory + "/lidawake"
    }

    public var rule: String {
        "#\(uid) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n"
    }

    // A readable exact rule detects old installations and rules for another account.
    // Every actual write still uses sudo -n -k and checks its result and live state.
    public var isInstalled: Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == 0,
              ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o022 == 0,
              (try? String(contentsOfFile: path, encoding: .utf8)) == rule else { return false }
        if FileManager.default.fileExists(atPath: legacyPath) {
            guard let legacy = try? String(contentsOfFile: legacyPath, encoding: .utf8),
                  legacy.range(of: #"^[a-zA-Z0-9._-]+ ALL=\(root\) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n?$"#,
                               options: .regularExpression) != nil else { return false }
        }
        return true
    }

    public func install() throws {
        _ = try runner.run("/usr/bin/osascript", ["-e",
            "do shell script \(appleScriptString(installationScript))\(promptClause(installPrompt)) with administrator privileges"], timeout: 120)
        guard isInstalled else { throw ControlError.message("Sleep setup could not be verified. Try Repair Sleep Setup.") }
    }

    /// This account's and the legacy rule files that still exist, symbolic links included.
    public var remainingRules: [String] {
        [path, legacyPath].filter { (try? FileManager.default.attributesOfItem(atPath: $0)) != nil }
    }

    /// Restores sleep as root, then removes this account's rule and the legacy rule with one
    /// admin prompt; after the rules are gone nothing of this account can restore it. The script
    /// checks both rules before removing either, and the result is verified from the file system.
    /// The legacy rule is removed only if it is a known LidAwake rule naming this account;
    /// otherwise it is left in place and this returns true.
    @discardableResult
    public func uninstall() throws -> Bool {
        let output = try runner.run("/usr/bin/osascript", ["-e",
            "do shell script \(appleScriptString(uninstallationScript))\(promptClause(uninstallPrompt)) with administrator privileges"], timeout: 120)
        let keptLegacy = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "kept-legacy"
        let remaining = remainingRules.filter { !(keptLegacy && $0 == legacyPath) }
        guard remaining.isEmpty else {
            throw ControlError.message("Sleep rules were not removed: " + remaining.joined(separator: ", "))
        }
        return keptLegacy
    }

    private func promptClause(_ prompt: String?) -> String {
        prompt.map { " with prompt \(appleScriptString($0))" } ?? ""
    }

    var uninstallationScript: String {
        """
        set -eu
        for rule in \(shellString(path)) \(shellString(legacyPath)); do
            if [ -L "$rule" ] || { [ -e "$rule" ] && [ ! -f "$rule" ]; }; then
                echo "Refusing to remove $rule: it is not a regular file." >&2
                exit 1
            fi
        done
        legacy=
        if [ -e \(shellString(legacyPath)) ]; then
            legacy=keep
            if [ "$(/usr/bin/awk 'END { print NR }' \(shellString(legacyPath)))" = 1 ] \\
                && { /usr/bin/grep -Eq \(shellString(Self.oldPattern)) \(shellString(legacyPath)) \\
                     || /usr/bin/grep -Eq \(shellString(Self.newPattern)) \(shellString(legacyPath)); } \\
                && [ "$(/usr/bin/awk '{ print $1 }' \(shellString(legacyPath)))" = \(shellString(NSUserName())) ]; then
                legacy=remove
            fi
        fi
        /usr/bin/pmset -a disablesleep 0
        sleep_disabled=
        if status=$(/usr/bin/pmset -g); then
            if printf '%s\n' "$status" | /usr/bin/grep -q SleepDisabled; then
                sleep_disabled=$(printf '%s\n' "$status" | /usr/bin/awk '$1 == "SleepDisabled" { print $2 }')
            else
                # macOS 27 leaves the line out of pmset; IOPMrootDomain still has it (Yes/No).
                sleep_disabled=$(/usr/sbin/ioreg -r -c IOPMrootDomain -d 1 | /usr/bin/awk '$2 == "=" && $1 ~ /^"SleepDisabled"$/ { print ($3 == "No") ? 0 : ($3 == "Yes") ? 1 : "" }')
            fi
        fi
        if [ "$sleep_disabled" != 0 ]; then
            echo 'Sleep could not be restored; the sleep rules were kept.' >&2
            exit 1
        fi
        /bin/rm -f \(shellString(path))
        if [ "$legacy" = remove ]; then
            /bin/rm -f \(shellString(legacyPath))
        elif [ "$legacy" = keep ]; then
            echo kept-legacy
        fi
        """
    }

    // The two historical shapes of the legacy rule, `<username> ALL=(root) NOPASSWD: …`.
    private static let oldPattern = #"^([a-zA-Z0-9._-]+) ALL=\(root\) NOPASSWD: /usr/bin/pmset -a disablesleep \*, /usr/bin/pmset -b disablesleep \*, /usr/bin/pmset -c disablesleep \*$"#
    private static let newPattern = #"^[a-zA-Z0-9._-]+ ALL=\(root\) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1$"#

    var installationScript: String {
        // Preserve a legacy rule's account while narrowing its commands. Refuse unknown
        // content instead of replacing a file that may have been edited by an administrator.
        let oldPattern = Self.oldPattern, newPattern = Self.newPattern
        let replacement = #"\1 ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"#
        return """
        set -eu
        work=$(/usr/bin/mktemp -d)
        trap '/bin/rm -rf "$work"' EXIT
        /bin/mkdir -p \(shellString(URL(fileURLWithPath: path).deletingLastPathComponent().path))
        if [ -L \(shellString(legacyPath)) ] || [ -L \(shellString(path)) ]; then
            echo 'Refusing a symbolic link in sleep setup.' >&2
            exit 1
        fi
        if [ -e \(shellString(legacyPath)) ]; then
            if [ "$(/usr/bin/awk 'END { print NR }' \(shellString(legacyPath)))" != 1 ]; then
                echo 'Legacy sleep rule has unexpected content; ask your administrator to review it.' >&2
                exit 1
            fi
            if /usr/bin/grep -Eq \(shellString(oldPattern)) \(shellString(legacyPath)); then
                /usr/bin/sed -E \(shellString("s|" + oldPattern + "|" + replacement + "|")) \(shellString(legacyPath)) > "$work/legacy"
            elif /usr/bin/grep -Eq \(shellString(newPattern)) \(shellString(legacyPath)); then
                /bin/cp \(shellString(legacyPath)) "$work/legacy"
            else
                echo 'Legacy sleep rule has unexpected content; ask your administrator to review it.' >&2
                exit 1
            fi
            /usr/sbin/visudo -cf "$work/legacy"
            /usr/bin/install -m 0444 -o root -g wheel "$work/legacy" \(shellString(legacyPath))
        fi
        /usr/bin/printf '%s' \(shellString(rule)) > "$work/rule"
        /usr/sbin/visudo -cf "$work/rule"
        /usr/bin/install -m 0444 -o root -g wheel "$work/rule" \(shellString(path))
        """
    }
}
