import Darwin
import Foundation

/// Ergebnis eines externen Prozesses.
struct CommandResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool
}

/// Thread-sicherer Zustand, den Timer und Ausführungs-Thread gemeinsam nutzen.
private final class ProcessState: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private var didTimeOut = false

    /// Markiert einen Timeout, sofern der Prozess noch läuft. Liefert `true`, wenn beendet werden soll.
    func markTimedOutIfRunning() -> Bool {
        lock.withLock {
            guard !finished else { return false }
            didTimeOut = true
            return true
        }
    }

    func markFinished() {
        lock.withLock { finished = true }
    }

    var timedOut: Bool {
        lock.withLock { didTimeOut }
    }
}

/// Puffer für den parallel gelesenen stderr-Stream.
private final class DataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func set(_ data: Data) {
        lock.withLock { storage = data }
    }

    var data: Data {
        lock.withLock { storage }
    }
}

/// Startet externe Prozesse asynchron, ohne den Main-Thread zu blockieren.
enum ProcessRunner {
    static func run(
        executable: String,
        arguments: [String],
        input: String?,
        timeout: TimeInterval
    ) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CommandResult, any Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result {
                    try runBlocking(executable: executable, arguments: arguments, input: input, timeout: timeout)
                })
            }
        }
    }

    private static func runBlocking(
        executable: String,
        arguments: [String],
        input: String?,
        timeout: TimeInterval
    ) throws -> CommandResult {
        // Schreibt die App in eine bereits geschlossene Pipe, darf das nie zum Absturz führen.
        signal(SIGPIPE, SIG_IGN)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        do {
            try process.run()
        } catch {
            throw SSHError.launchFailed(error.localizedDescription)
        }

        let state = ProcessState()
        let pid = process.processIdentifier
        let timer = DispatchWorkItem {
            if state.markTimedOutIfRunning() {
                kill(pid, SIGTERM)
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timer)

        let stdinHandle = stdinPipe.fileHandleForWriting
        if let input {
            try? stdinHandle.write(contentsOf: Data(input.utf8))
        }
        try? stdinHandle.close()

        let stderrBuffer = DataBuffer()
        let stderrHandle = stderrPipe.fileHandleForReading
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrBuffer.set(stderrHandle.readDataToEndOfFile())
            group.leave()
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        state.markFinished()
        timer.cancel()

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrBuffer.data, as: UTF8.self),
            timedOut: state.timedOut
        )
    }
}
