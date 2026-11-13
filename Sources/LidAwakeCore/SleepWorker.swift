import Foundation
import Darwin

struct WorkerRequest: Codable {
    enum Operation: String, Codable { case status, set, shutdown }
    var operation: Operation
    var awake: Bool?
}
struct WorkerReply: Codable {
    var awake: Bool?
    var error: String?
    var fatal: Bool?
}

/// Line-oriented pipe transport. The app's pipe is the worker's lifetime: EOF
/// after a GUI crash goes through exactly the same restoration path as Quit.
public enum SleepWorker {
    public static func run() -> Int32 {
        signal(SIGPIPE, SIG_IGN) // A dead GUI must not kill recovery while replying.
        do {
            let lock = try SessionLock(path: "/private/tmp/local.lidawake-session.lock")
            return try withExtendedLifetime(lock) {
                let directory = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support/LidAwake", isDirectory: true)
                let runner = ProcessCommandRunner()
                let session = try SleepSession(settings: PMSet(runner: runner, setup: PrivilegeSetup(runner: InProcessAppleScriptRunner())),
                                               journal: FileRecoveryJournal(directory: directory))
                return serve(session: session, receive: { readLine() }, reply: send)
            }
        } catch {
            send(WorkerReply(awake: nil, error: error.localizedDescription, fatal: true))
            return 1
        }
    }

    static func serve(session: SleepSession, receive: () -> String?, reply: (WorkerReply) -> Void) -> Int32 {
        func respond(_ operation: () throws -> Void) -> Bool {
            do {
                try operation()
                reply(WorkerReply(awake: try session.isAwake(), error: nil))
                return true
            } catch {
                reply(WorkerReply(awake: try? session.isAwake(), error: error.localizedDescription))
                return false
            }
        }
        _ = respond { try session.recover() }
        while let line = receive() {
            guard line.utf8.count < 1024,
                  let request = try? JSONDecoder().decode(WorkerRequest.self, from: Data(line.utf8)) else {
                reply(WorkerReply(awake: nil, error: "Invalid sleep request."))
                continue
            }
            switch request.operation {
            case .status:
                _ = respond { try session.recover() }
            case .set:
                _ = respond {
                    guard let value = request.awake else { throw ControlError.message("Missing sleep setting.") }
                    try session.setAwake(value)
                }
            case .shutdown:
                if respond({ try session.stop() }) { return 0 }
            }
        }
        // No GUI remains to repair permissions. Try briefly, then leave the journal
        // for the next launch if the system no longer permits restoration.
        for attempt in 0..<3 {
            do { try session.stop(); return 0 } catch {
                if attempt == 2 {
                    fputs("LidAwake could not restore sleep: \(error.localizedDescription)\n", stderr)
                } else { Thread.sleep(forTimeInterval: 1) }
            }
        }
        return 1
    }

    private static func send(_ reply: WorkerReply) {
        if let data = try? JSONEncoder().encode(reply) {
            try? FileHandle.standardOutput.write(contentsOf: data + Data([10]))
        }
    }
}

/// Used only from the app's serial background queue. Requests and responses stay
/// ordered; all actual power-setting writes live in the child process.
public final class SleepWorkerClient: SleepControlling {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()
    private var started = false
    private var closed = false
    private let executable: URL

    public init(executable: URL) { self.executable = executable }

    public func start() throws {
        guard !started else { return }
        process.executableURL = executable
        process.arguments = ["--sleep-worker"]
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        started = true
        try input.fileHandleForReading.close()
        try output.fileHandleForWriting.close()
        let response = try receiveOrDisconnect()
        if response.fatal == true { disconnect() }
        if let error = response.error { throw ControlError.message(error) }
    }

    public func isAwake() throws -> Bool {
        let response = try request(WorkerRequest(operation: .status))
        guard let awake = response.awake else { throw ControlError.message("Sleep status is unavailable.") }
        return awake
    }
    public func setAwake(_ awake: Bool) throws {
        _ = try request(WorkerRequest(operation: .set, awake: awake))
    }
    public func stop() throws {
        guard started else { return }
        if !closed {
            _ = try request(WorkerRequest(operation: .shutdown))
            closed = true
            try input.fileHandleForWriting.close()
        }
        // The worker holds the session lock until it exits, so a replacement
        // started right after stop() must not race that exit. A retry after a
        // timeout (or after a disconnect) waits again instead of reporting success.
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning {
            guard Date() < deadline else {
                throw ControlError.message("Sleep recovery is still shutting down. Try again in a moment.")
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    private func request(_ request: WorkerRequest) throws -> WorkerReply {
        guard started, !closed, process.isRunning else {
            throw ControlError.message("Sleep recovery is not running. Quit and reopen LidAwake.")
        }
        do { try input.fileHandleForWriting.write(contentsOf: JSONEncoder().encode(request) + Data([10])) }
        catch { disconnect(); throw error }
        let response = try receiveOrDisconnect()
        if let error = response.error { throw ControlError.message(error) }
        return response
    }

    private func disconnect() {
        closed = true
        try? input.fileHandleForWriting.close()
    }

    private func receiveOrDisconnect() throws -> WorkerReply {
        do { return try readReply() }
        catch {
            // Never pair a late reply with the next request. EOF also starts recovery.
            disconnect()
            throw error
        }
    }

    private func readReply() throws -> WorkerReply {
        let deadline = Date().addingTimeInterval(65)
        while true {
            if let newline = buffer.firstIndex(of: 10) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                return try JSONDecoder().decode(WorkerReply.self, from: line)
            }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw ControlError.message("Sleep recovery is not responding. Quit and reopen LidAwake.") }
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor,
                                    events: Int16(POLLIN | POLLHUP), revents: 0)
            let result = poll(&descriptor, 1, Int32(remaining * 1000))
            if result < 0 && errno == EINTR { continue }
            guard result > 0 else { throw ControlError.message("Sleep recovery response timed out.") }
            var bytes = [UInt8](repeating: 0, count: 4096)
            let count = Darwin.read(output.fileHandleForReading.fileDescriptor, &bytes, bytes.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else {
                throw ControlError.message("Sleep recovery stopped. Quit and reopen LidAwake.")
            }
            buffer.append(contentsOf: bytes.prefix(count))
            guard buffer.count < 65536 else { throw ControlError.message("Invalid sleep recovery response.") }
        }
    }

    deinit {
        // Do not terminate the child: EOF lets it restore sleep, including when a
        // request failed halfway through. It owns the recovery journal and lock.
        try? input.fileHandleForWriting.close()
    }
}
