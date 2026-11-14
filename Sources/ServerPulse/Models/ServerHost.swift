import Foundation

/// Ein konfigurierter Linux-/NAS-Host, der per SSH überwacht wird.
struct ServerHost: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var hostname: String
    var port: Int
    var username: String
    var privateKeyPath: String?
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        hostname: String,
        port: Int = 22,
        username: String,
        privateKeyPath: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.port = port
        self.username = username
        self.privateKeyPath = privateKeyPath
        self.isEnabled = isEnabled
    }

    /// Anzeigename mit Fallback auf den Hostnamen.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? hostname : trimmed
    }

    /// SSH-Ziel im Format `user@host`.
    var destination: String {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        return user.isEmpty ? host : "\(user)@\(host)"
    }

    /// Pfad zum privaten Key mit aufgelöster Tilde, `nil` wenn keiner gesetzt ist.
    var expandedKeyPath: String? {
        guard let raw = privateKeyPath?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return (raw as NSString).expandingTildeInPath
    }

    /// Prüft die Eingaben und liefert eine verständliche Fehlermeldung oder `nil`.
    var validationError: String? {
        let host = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.isEmpty { return "Bitte einen Hostnamen oder eine IP-Adresse eingeben." }
        if host.hasPrefix("-") || host.contains(where: { $0.isWhitespace || $0 == "@" }) {
            return "Der Hostname enthält ungültige Zeichen."
        }
        if user.isEmpty { return "Bitte einen SSH-Benutzer eingeben." }
        if user.hasPrefix("-") || user.contains(where: { $0.isWhitespace || $0 == "@" }) {
            return "Der SSH-Benutzer enthält ungültige Zeichen."
        }
        if !(1...65_535).contains(port) { return "Der SSH-Port muss zwischen 1 und 65535 liegen." }
        return nil
    }

    /// Vorlage für einen neu anzulegenden Host.
    static func newDraft() -> ServerHost {
        ServerHost(name: "Neuer Server", hostname: "", port: 22, username: "", privateKeyPath: "~/.ssh/id_ed25519")
    }

    /// Beispiel-Eintrag für den allerersten Start.
    static let example = ServerHost(
        name: "UGREEN NAS",
        hostname: "192.168.1.100",
        port: 22,
        username: "admin",
        privateKeyPath: "~/.ssh/id_ed25519",
        isEnabled: true
    )
}
