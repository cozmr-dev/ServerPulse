import Foundation

/// Ein Docker-Container laut `docker ps -a`.
struct DockerContainer: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let image: String
    let status: String
    let state: String
    /// Docker-Compose-Projekt (Label `com.docker.compose.project`), sofern vorhanden.
    var project: String? = nil

    var isRunning: Bool { state == "running" }

    var isUnhealthy: Bool { status.localizedCaseInsensitiveContains("(unhealthy)") }

    /// Exit-Code aus einem Status wie `Exited (137) 2 hours ago`.
    var exitCode: Int? {
        guard let open = status.firstIndex(of: "("),
              let close = status[open...].firstIndex(of: ")") else { return nil }
        return Int(status[status.index(after: open)..<close])
    }

    /// Exit-Codes, die auf ein reguläres Beenden hindeuten
    /// (0 = sauber, 130 = SIGINT, 137 = SIGKILL nach `docker stop`-Timeout, 143 = SIGTERM).
    private static let cleanExitCodes: Set<Int> = [0, 130, 137, 143]

    /// `true`, wenn der Container Aufmerksamkeit braucht (abgestürzt, neustartend, unhealthy).
    var needsAttention: Bool {
        switch state {
        case "running": isUnhealthy
        case "restarting", "dead": true
        case "exited": !Self.cleanExitCodes.contains(exitCode ?? 0)
        default: false
        }
    }

    /// Datenbanken und Caches, von denen andere Container eines Projekts abhängen.
    var isDependency: Bool {
        let key = "\(name) \(image)".lowercased()
        let markers = ["postgres", "mariadb", "mysql", "mongo", "redis", "valkey", "memcached", "-db", "_db", "database", "pgvecto"]
        return markers.contains { key.contains($0) }
    }

    /// Prüft, ob die ID sicher an die Remote-Shell übergeben werden kann.
    static func isValidIdentifier(_ value: String) -> Bool {
        guard let first = value.first, first.isLetter || first.isNumber else { return false }
        return value.allSatisfy { char in
            char.isASCII && (char.isLetter || char.isNumber || char == "_" || char == "." || char == "-")
        }
    }
}

/// Aktionen, die auf einen Container angewendet werden können.
enum ContainerAction: String, Sendable {
    case start
    case stop
    case restart

    /// Erfolgsmeldung für einen einzelnen Container.
    func successMessage(for name: String) -> String {
        switch self {
        case .start: String(localized: "“\(name)” was started.")
        case .stop: String(localized: "“\(name)” was stopped.")
        case .restart: String(localized: "“\(name)” was restarted.")
        }
    }

    /// Erfolgsmeldung für ein ganzes Compose-Projekt.
    func successMessage(forProject name: String, count: Int) -> String {
        switch self {
        case .start: String(localized: "“\(name)” was started (\(count) containers).")
        case .stop: String(localized: "“\(name)” was stopped (\(count) containers).")
        case .restart: String(localized: "“\(name)” was restarted (\(count) containers).")
        }
    }
}

/// Ergebnis des Docker-Health-Checks.
enum ContainerHealth: Sendable {
    case none
    case healthy
    case unhealthy
    case starting
}

extension DockerContainer {
    var health: ContainerHealth {
        let lower = status.lowercased()
        if lower.contains("(unhealthy)") { return .unhealthy }
        if lower.contains("(healthy)") { return .healthy }
        if lower.contains("health: starting") { return .starting }
        return .none
    }

    /// Image ohne Registry-Pfad, z. B. `immich-server:release`.
    var shortImage: String {
        let withoutDigest = image.split(separator: "@").first.map(String.init) ?? image
        return withoutDigest.split(separator: "/").last.map(String.init) ?? withoutDigest
    }

    /// Docker-Status in der App-Sprache, z. B. „Running for 3 days“ bzw. „Läuft seit 3 Tagen“.
    var localizedStatus: String {
        if state == "paused" { return String(localized: "Paused") }
        var text = status
        for marker in ["(healthy)", "(unhealthy)", "(health: starting)", "(Paused)"] {
            text = text.replacingOccurrences(of: marker, with: "")
        }
        text = text.trimmingCharacters(in: .whitespaces)

        if text.hasPrefix("Up ") {
            let duration = Self.localizedDuration(String(text.dropFirst(3)))
            return String(localized: "Running for \(duration)")
        }
        if text.hasPrefix("Exited") {
            var rest = text
            if let close = text.firstIndex(of: ")") {
                rest = String(text[text.index(after: close)...])
            }
            rest = rest.trimmingCharacters(in: .whitespaces)
            if rest.hasSuffix(" ago") { rest = String(rest.dropLast(4)) }
            let duration = Self.localizedDuration(rest)
            let exited = String(localized: "Exited \(duration) ago")
            guard let code = exitCode else { return exited }
            return exited + String(localized: " · code \(code)")
        }
        if text.hasPrefix("Restarting") { return String(localized: "Restarting …") }
        if text.hasPrefix("Created") { return String(localized: "Created, never started") }
        if text.hasPrefix("Removal") { return String(localized: "Being removed") }
        if text.hasPrefix("Dead") { return String(localized: "Dead") }
        return text
    }

    /// Docker-Zeitangabe (go-units HumanDuration, z. B. „About an hour“) in der App-Sprache.
    static func localizedDuration(_ english: String) -> String {
        if AppLanguage.isGerman { return germanDuration(english) }
        let trimmed = english.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return trimmed }
        return first.lowercased() + trimmed.dropFirst()
    }

    /// Übersetzt Docker-Zeitangaben (go-units HumanDuration) in den deutschen Dativ.
    static func germanDuration(_ english: String) -> String {
        let trimmed = english.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        let phrases = [
            "less than a second": "weniger als einer Sekunde",
            "about a minute": "etwa einer Minute",
            "about an hour": "etwa einer Stunde",
            "a minute": "einer Minute",
            "an hour": "einer Stunde"
        ]
        if let phrase = phrases[lower] { return phrase }

        let parts = lower.split(separator: " ")
        guard parts.count == 2, let count = Int(parts[0]) else { return trimmed }
        let rawUnit = String(parts[1])
        let unit = rawUnit.hasSuffix("s") ? String(rawUnit.dropLast()) : rawUnit
        let units: [String: (singular: String, plural: String, feminine: Bool)] = [
            "second": ("Sekunde", "Sekunden", true),
            "minute": ("Minute", "Minuten", true),
            "hour": ("Stunde", "Stunden", true),
            "day": ("Tag", "Tagen", false),
            "week": ("Woche", "Wochen", true),
            "month": ("Monat", "Monaten", false),
            "year": ("Jahr", "Jahren", false)
        ]
        guard let match = units[unit] else { return trimmed }
        if count == 1 { return (match.feminine ? "einer " : "einem ") + match.singular }
        return "\(count) \(match.plural)"
    }
}
