import Foundation

/// Fragt Hosts per `/usr/bin/ssh` ab und steuert Docker-Container.
struct SSHService: Sendable {
    static let sshPath = "/usr/bin/ssh"

    private let statusTimeout: TimeInterval = 25
    private let actionTimeout: TimeInterval = 60
    private let logsTimeout: TimeInterval = 30

    // MARK: Monitoring

    func fetchStatus(for host: ServerHost) async throws -> HostSnapshot {
        let result = try await execute(script: RemoteScripts.status, on: host, timeout: statusTimeout)
        return try StatusParser.parse(result.stdout)
    }

    // MARK: Container-Aktionen

    func restartContainer(_ containerID: String, on host: ServerHost) async throws {
        try await runContainerAction(.restart, containerID: containerID, on: host)
    }

    func startContainer(_ containerID: String, on host: ServerHost) async throws {
        try await runContainerAction(.start, containerID: containerID, on: host)
    }

    func stopContainer(_ containerID: String, on host: ServerHost) async throws {
        try await runContainerAction(.stop, containerID: containerID, on: host)
    }

    func perform(_ action: ContainerAction, containerID: String, on host: ServerHost) async throws {
        switch action {
        case .start: try await startContainer(containerID, on: host)
        case .stop: try await stopContainer(containerID, on: host)
        case .restart: try await restartContainer(containerID, on: host)
        }
    }

    /// Führt eine Aktion für mehrere Container in einem einzigen Docker-Aufruf aus (in der übergebenen Reihenfolge).
    func perform(_ action: ContainerAction, containerIDs: [String], on host: ServerHost) async throws {
        guard !containerIDs.isEmpty else { return }
        try await runContainerAction(action, containerIDs: containerIDs, on: host)
    }

    func fetchLogs(_ containerID: String, lines: Int = 100, on host: ServerHost) async throws -> String {
        guard DockerContainer.isValidIdentifier(containerID) else {
            throw SSHError.invalidContainerID(containerID)
        }
        let count = max(1, min(lines, 10_000))
        let script = RemoteScripts.docker("logs --tail \(count) '\(containerID)' 2>&1")
        let result = try await execute(script: script, on: host, timeout: logsTimeout)
        try checkDockerResult(result)
        return result.stdout
    }

    // MARK: Verbindungstest

    func testConnection(_ host: ServerHost) async -> ConnectionTestResult {
        do {
            let snapshot = try await fetchStatus(for: host)
            let uptime = snapshot.stats.uptime.map { " · Uptime \(Format.uptime($0))" } ?? ""
            let base = "Verbunden mit \(host.destination)\(uptime)."
            switch snapshot.docker {
            case .available:
                return ConnectionTestResult(
                    level: .success,
                    title: "Verbindung erfolgreich",
                    detail: "\(base) Docker verfügbar – \(snapshot.containers.count) Container gefunden."
                )
            case .notInstalled:
                return ConnectionTestResult(
                    level: .warning,
                    title: "Verbunden – Docker nicht gefunden",
                    detail: "\(base) Docker liegt weder im PATH noch unter /usr/bin oder /usr/local/bin."
                )
            case .permissionDenied(let detail):
                return ConnectionTestResult(
                    level: .warning,
                    title: "Verbunden – keine Docker-Rechte",
                    detail: "\(base) \(detail)\n\(SSHError.dockerPermissionDenied(detail).recoverySuggestion ?? "")"
                )
            case .error(let detail):
                return ConnectionTestResult(
                    level: .warning,
                    title: "Verbunden – Docker-Fehler",
                    detail: "\(base) \(detail)"
                )
            }
        } catch {
            let sshError = error as? SSHError
            let suggestion = sshError?.recoverySuggestion.map { "\n\($0)" } ?? ""
            return ConnectionTestResult(
                level: .failure,
                title: "Verbindung fehlgeschlagen",
                detail: error.localizedDescription + suggestion
            )
        }
    }

    // MARK: Intern

    private func runContainerAction(_ action: ContainerAction, containerID: String, on host: ServerHost) async throws {
        try await runContainerAction(action, containerIDs: [containerID], on: host)
    }

    private func runContainerAction(_ action: ContainerAction, containerIDs: [String], on host: ServerHost) async throws {
        if let invalid = containerIDs.first(where: { !DockerContainer.isValidIdentifier($0) }) {
            throw SSHError.invalidContainerID(invalid)
        }
        let arguments = containerIDs.map { "'\($0)'" }.joined(separator: " ")
        let script = RemoteScripts.docker("\(action.rawValue) \(arguments)")
        let timeout = actionTimeout + TimeInterval(max(0, containerIDs.count - 1)) * 20
        let result = try await execute(script: script, on: host, timeout: timeout)
        try checkDockerResult(result)
    }

    private func checkDockerResult(_ result: CommandResult) throws {
        guard result.exitCode != 0 else { return }
        let output = [result.stderr, result.stdout]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Exit-Code \(result.exitCode)"
        if result.exitCode == 127 { throw SSHError.dockerNotFound }
        if output.localizedCaseInsensitiveContains("permission denied") {
            throw SSHError.dockerPermissionDenied(output)
        }
        throw SSHError.commandFailed(output)
    }

    private func execute(script: String, on host: ServerHost, timeout: TimeInterval) async throws -> CommandResult {
        let arguments = try sshArguments(for: host)
        let result = try await ProcessRunner.run(
            executable: Self.sshPath,
            arguments: arguments,
            input: script,
            timeout: timeout
        )
        if result.timedOut { throw SSHError.timeout(timeout) }
        if result.exitCode == 255 { throw SSHError.classify(stderr: result.stderr, host: host) }
        return result
    }

    private func sshArguments(for host: ServerHost) throws -> [String] {
        if let problem = host.validationError {
            throw SSHError.invalidConfiguration(problem)
        }

        var arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ServerAliveInterval=5",
            "-o", "ServerAliveCountMax=2",
            "-o", "LogLevel=ERROR",
            "-p", String(host.port)
        ]

        if let keyPath = host.expandedKeyPath {
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: keyPath) else {
                throw SSHError.keyNotFound(keyPath)
            }
            guard fileManager.isReadableFile(atPath: keyPath) else {
                throw SSHError.keyNotReadable("Keine Leserechte für \(keyPath).")
            }
            arguments += ["-i", keyPath, "-o", "IdentitiesOnly=yes"]
        }

        arguments += ["--", host.destination, "sh -s"]
        return arguments
    }
}
