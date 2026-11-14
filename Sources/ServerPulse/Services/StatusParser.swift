import Foundation

/// Zerlegt die Ausgabe von `RemoteScripts.status` in strukturierte Daten.
enum StatusParser {
    static func parse(_ output: String, fetchedAt: Date = Date()) throws -> HostSnapshot {
        var sections: [String: [String]] = [:]
        var payloads: [String: String] = [:]
        var current: String?

        for rawLine in output.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(rawLine)
            if line.hasPrefix("@@") {
                let parts = line.dropFirst(2).split(separator: " ", maxSplits: 1)
                guard let name = parts.first.map(String.init) else { continue }
                current = name
                sections[name, default: []] = sections[name] ?? []
                if parts.count > 1 { payloads[name] = String(parts[1]) }
                continue
            }
            guard let current, !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            sections[current, default: []].append(line)
        }

        guard sections["MEM"] != nil, sections["UPTIME"] != nil else {
            let preview = output.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)
            throw SSHError.unexpectedOutput(
                preview.isEmpty ? String(localized: "No data received – is this a Linux system?") : String(preview)
            )
        }

        let (memTotal, memUsed) = parseMemory(sections["MEM"] ?? [])
        let load = parseLoad(sections["LOAD"]?.first)

        let stats = SystemStats(
            cpuPercent: parseCPU(sections["CPU"] ?? []),
            cpuCores: sections["NPROC"]?.first.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) },
            load1: load.0,
            load5: load.1,
            load15: load.2,
            memTotalBytes: memTotal,
            memUsedBytes: memUsed,
            disks: parseDisks(sections["DISK"] ?? []),
            uptime: sections["UPTIME"]?.first
                .flatMap { $0.split(separator: " ").first }
                .flatMap { TimeInterval($0) }
        )

        let (containers, docker) = parseDocker(
            lines: sections["DOCKER"] ?? [],
            returnCode: payloads["DOCKERRC"].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) },
            notInstalled: sections["NODOCKER"] != nil
        )

        return HostSnapshot(stats: stats, containers: containers, docker: docker, fetchedAt: fetchedAt)
    }

    /// Berechnet die CPU-Auslastung aus zwei `/proc/stat`-Messungen im Abstand von einer Sekunde.
    static func parseCPU(_ lines: [String]) -> Double? {
        guard lines.count >= 2 else { return nil }
        func sample(_ line: String) -> (idle: Double, total: Double)? {
            let values = line.split(separator: " ").dropFirst().compactMap { Double($0) }
            guard values.count >= 4 else { return nil }
            let relevant = Array(values.prefix(8))
            let idle = relevant[3] + (relevant.count > 4 ? relevant[4] : 0)
            return (idle, relevant.reduce(0, +))
        }
        guard let first = sample(lines[0]), let second = sample(lines[1]) else { return nil }
        let totalDelta = second.total - first.total
        guard totalDelta > 0 else { return nil }
        let idleDelta = second.idle - first.idle
        return max(0, min(100, (1 - idleDelta / totalDelta) * 100))
    }

    static func parseLoad(_ line: String?) -> (Double?, Double?, Double?) {
        guard let parts = line?.split(separator: " ") else { return (nil, nil, nil) }
        func value(_ index: Int) -> Double? { parts.count > index ? Double(parts[index]) : nil }
        return (value(0), value(1), value(2))
    }

    static func parseMemory(_ lines: [String]) -> (total: UInt64, used: UInt64) {
        var values: [String: UInt64] = [:]
        for line in lines {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2, let kilobytes = UInt64(parts[1]) else { continue }
            values[String(parts[0]).replacingOccurrences(of: ":", with: "")] = kilobytes * 1024
        }
        let total = values["MemTotal"] ?? 0
        let available = values["MemAvailable"] ?? 0
        return (total, total > available ? total - available : 0)
    }

    static func parseDisks(_ lines: [String]) -> [DiskUsage] {
        var result: [DiskUsage] = []
        var seenMounts = Set<String>()
        for line in lines where !line.hasPrefix("Filesystem") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 6,
                  let total = UInt64(parts[1]),
                  let used = UInt64(parts[2]),
                  let available = UInt64(parts[3]) else { continue }
            let mount = parts[5...].joined(separator: " ")
            guard seenMounts.insert(mount).inserted else { continue }
            result.append(DiskUsage(
                filesystem: parts[0],
                mountPoint: mount,
                totalBytes: total * 1024,
                usedBytes: used * 1024,
                availableBytes: available * 1024
            ))
        }
        return result
    }

    static func parseDocker(
        lines: [String],
        returnCode: Int?,
        notInstalled: Bool
    ) -> ([DockerContainer], DockerAvailability) {
        if notInstalled { return ([], .notInstalled) }

        guard returnCode == 0 else {
            let message = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = message.isEmpty ? String(localized: "Docker reported exit code \(returnCode.map(String.init) ?? "?").") : message
            if message.localizedCaseInsensitiveContains("permission denied") {
                return ([], .permissionDenied(detail))
            }
            return ([], .error(detail))
        }

        let containers: [DockerContainer] = lines.compactMap { line in
            let fields = line.split(separator: "|", maxSplits: 5, omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 5 else { return nil }
            let project = fields.count > 5 ? fields[5].trimmingCharacters(in: .whitespaces) : ""
            return DockerContainer(
                id: fields[0],
                name: fields[1],
                image: fields[2],
                status: fields[3],
                state: fields[4].trimmingCharacters(in: .whitespaces).lowercased(),
                project: project.isEmpty ? nil : project
            )
        }
        return (containers, .available)
    }
}
