import Foundation

/// Fehler bei SSH- und Docker-Aufrufen – mit verständlichen deutschen Meldungen.
enum SSHError: LocalizedError, Sendable, Equatable {
    case invalidConfiguration(String)
    case keyNotFound(String)
    case keyNotReadable(String)
    case launchFailed(String)
    case timeout(TimeInterval)
    case authenticationFailed(user: String)
    case hostKeyMismatch(host: String)
    case connectionRefused(host: String, port: Int)
    case hostUnreachable(host: String)
    case dnsFailure(host: String)
    case connectionFailed(String)
    case unexpectedOutput(String)
    case invalidContainerID(String)
    case dockerNotFound
    case dockerPermissionDenied(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            message
        case .keyNotFound(let path):
            "SSH-Key nicht gefunden: \(path)"
        case .keyNotReadable(let detail):
            "SSH-Key kann nicht verwendet werden: \(detail)"
        case .launchFailed(let detail):
            "/usr/bin/ssh konnte nicht gestartet werden: \(detail)"
        case .timeout(let seconds):
            "Zeitüberschreitung nach \(Int(seconds)) s – der Host antwortet nicht."
        case .authenticationFailed(let user):
            "Anmeldung als „\(user)“ abgelehnt (Permission denied)."
        case .hostKeyMismatch(let host):
            "Der Host-Key von \(host) hat sich geändert."
        case .connectionRefused(let host, let port):
            "Verbindung zu \(host):\(port) abgelehnt."
        case .hostUnreachable(let host):
            "\(host) ist nicht erreichbar."
        case .dnsFailure(let host):
            "Hostname „\(host)“ konnte nicht aufgelöst werden."
        case .connectionFailed(let detail):
            "SSH-Verbindung fehlgeschlagen: \(detail)"
        case .unexpectedOutput(let detail):
            "Unerwartete Antwort vom Host: \(detail)"
        case .invalidContainerID(let id):
            "Ungültige Container-ID: \(id)"
        case .dockerNotFound:
            "Docker wurde auf dem Host nicht gefunden."
        case .dockerPermissionDenied(let detail):
            "Keine Berechtigung für Docker: \(detail)"
        case .commandFailed(let detail):
            "Befehl fehlgeschlagen: \(detail)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .keyNotFound:
            "Pfad in den Einstellungen prüfen oder einen Key erzeugen: ssh-keygen -t ed25519"
        case .keyNotReadable:
            "Rechte prüfen (chmod 600 <key>). Passwortgeschützte Keys vorher mit „ssh-add --apple-use-keychain <key>“ zum ssh-agent hinzufügen."
        case .authenticationFailed:
            "Public Key auf dem Server hinterlegen (ssh-copy-id -i <key>.pub user@host) und prüfen, ob der Benutzer per SSH-Key anmelden darf."
        case .hostKeyMismatch(let host):
            "Falls der Server neu installiert wurde: „ssh-keygen -R \(host)“ ausführen und erneut verbinden."
        case .connectionRefused:
            "Läuft der SSH-Dienst? Bei UGREEN: Systemsteuerung → Terminal → SSH aktivieren. Port prüfen."
        case .hostUnreachable, .timeout:
            "Netzwerkverbindung, IP-Adresse und Firewall prüfen."
        case .dnsFailure:
            "Hostnamen prüfen oder direkt die IP-Adresse eintragen."
        case .dockerNotFound:
            "Docker installieren bzw. prüfen, ob „docker“ unter /usr/bin oder /usr/local/bin liegt."
        case .dockerPermissionDenied:
            "Benutzer zur Gruppe „docker“ hinzufügen: sudo usermod -aG docker <user> (danach neu anmelden)."
        default:
            nil
        }
    }

    /// Ordnet die stderr-Ausgabe von `ssh` (Exit-Code 255) einem konkreten Fehler zu.
    static func classify(stderr: String, host: ServerHost) -> SSHError {
        let text = stderr.lowercased()
        let hostname = host.hostname

        if text.contains("bad permissions") || text.contains("unprotected private key") {
            return .keyNotReadable("Die Dateirechte des Keys sind zu offen.")
        }
        if text.contains("invalid format") || text.contains("load key") {
            return .keyNotReadable("Das Key-Format ist ungültig oder der Key ist passwortgeschützt.")
        }
        if text.contains("no such identity") || (text.contains("identity file") && text.contains("not accessible")) {
            return .keyNotFound(host.expandedKeyPath ?? "–")
        }
        if text.contains("permission denied") {
            return .authenticationFailed(user: host.username)
        }
        if text.contains("host key verification failed") || text.contains("remote host identification has changed") {
            return .hostKeyMismatch(host: hostname)
        }
        if text.contains("connection refused") {
            return .connectionRefused(host: hostname, port: host.port)
        }
        if text.contains("could not resolve hostname") || text.contains("nodename nor servname") {
            return .dnsFailure(host: hostname)
        }
        if text.contains("timed out") {
            return .timeout(5)
        }
        if text.contains("no route to host") || text.contains("network is unreachable") || text.contains("host is down") {
            return .hostUnreachable(host: hostname)
        }

        let detail = stderr
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.lowercased().hasPrefix("warning:") }
        return .connectionFailed(detail ?? "Unbekannter Fehler (Exit-Code 255)")
    }
}
