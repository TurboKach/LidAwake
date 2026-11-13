import Foundation
import Darwin

public enum ControlError: Error, LocalizedError, Equatable {
    case message(String)
    case canceled

    public var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .canceled: return "Authorization was canceled."
        }
    }
}

public struct CommandOutput {
    public let stdout: String
    public let stderr: String
    public init(stdout: String = "", stderr: String = "") {
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol CommandRunning {
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) throws -> CommandOutput
}

/// Blocking by design: callers use the worker process or a serial background queue.
/// Files drain both output streams without pipe-buffer deadlocks.
public final class ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 10) throws -> CommandOutput {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let outURL = directory.appendingPathComponent("stdout")
        let errURL = directory.appendingPathComponent("stderr")
        for url in [outURL, errURL] {
            guard FileManager.default.createFile(atPath: url.path, contents: nil,
                                                  attributes: [.posixPermissions: 0o600]) else {
                throw ControlError.message("Cannot capture command output.")
            }
        }
        let out = try FileHandle(forWritingTo: outURL)
        let err = try FileHandle(forWritingTo: errURL)
        defer { try? out.close(); try? err.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = out
        process.standardError = err
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch {
            throw ControlError.message("Could not launch \(executable): \(error.localizedDescription)")
        }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 2)
            }
            throw ControlError.message("\(URL(fileURLWithPath: executable).lastPathComponent) timed out.")
        }
        let output = CommandOutput(stdout: (try? String(contentsOf: outURL, encoding: .utf8)) ?? "",
                                   stderr: (try? String(contentsOf: errURL, encoding: .utf8)) ?? "")
        guard process.terminationReason == .exit && process.terminationStatus == 0 else {
            if output.stderr.contains("(-128)") { throw ControlError.canceled }
            let detail = (output.stderr + "\n" + output.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
            throw ControlError.message(detail.isEmpty ? "\(executable) failed (\(process.terminationStatus))." : detail)
        }
        return output
    }
}

/// Runs one AppleScript source text in the current process and returns its result as text.
public protocol AppleScriptRunning {
    func run(_ source: String) throws -> String
}

/// Runs the script with NSAppleScript inside this process, so the system's admin password
/// dialog is titled with this app's name instead of "osascript". Blocking, with no timeout:
/// a script ends when the user answers its dialog.
public final class InProcessAppleScriptRunner: AppleScriptRunning {
    public init() {}

    public func run(_ source: String) throws -> String {
        var failure: NSDictionary?
        // The Swift annotation says non-optional; a failed script returns nil.
        let result: NSAppleEventDescriptor? = NSAppleScript(source: source)?.executeAndReturnError(&failure)
        if let failure {
            let number = (failure[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
            if number == -128 { throw ControlError.canceled }
            let message = ((failure[NSAppleScript.errorMessage] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ControlError.message(message.isEmpty ? "The admin script failed (\(number))." : message)
        }
        guard let result else { throw ControlError.message("The admin script could not be run.") }
        return result.stringValue ?? ""
    }
}

public func appleScriptString(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\r", with: "\\r")
        .replacingOccurrences(of: "\n", with: "\\n") + "\""
}

func shellString(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
