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
            String(localized: "SSH key not found: \(path)")
        case .keyNotReadable(let detail):
            String(localized: "SSH key cannot be used: \(detail)")
        case .launchFailed(let detail):
            String(localized: "/usr/bin/ssh could not be started: \(detail)")
        case .timeout(let seconds):
            String(localized: "Timed out after \(Int(seconds)) s – the host is not responding.")
        case .authenticationFailed(let user):
            String(localized: "Login as “\(user)” was rejected (Permission denied).")
        case .hostKeyMismatch(let host):
            String(localized: "The host key of \(host) has changed.")
        case .connectionRefused(let host, let port):
            String(localized: "Connection to \(host):\(String(port)) refused.")
        case .hostUnreachable(let host):
            String(localized: "\(host) is not reachable.")
        case .dnsFailure(let host):
            String(localized: "Hostname “\(host)” could not be resolved.")
        case .connectionFailed(let detail):
            String(localized: "SSH connection failed: \(detail)")
        case .unexpectedOutput(let detail):
            String(localized: "Unexpected response from host: \(detail)")
        case .invalidContainerID(let id):
            String(localized: "Invalid container ID: \(id)")
        case .dockerNotFound:
            String(localized: "Docker was not found on the host.")
        case .dockerPermissionDenied(let detail):
            String(localized: "No permission for Docker: \(detail)")
        case .commandFailed(let detail):
            String(localized: "Command failed: \(detail)")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .keyNotFound:
            String(localized: "Check the path in Settings or create a key: ssh-keygen -t ed25519")
        case .keyNotReadable:
            String(localized: "Check the permissions (chmod 600 <key>). Add passphrase-protected keys to the ssh-agent first: ssh-add --apple-use-keychain <key>")
        case .authenticationFailed:
            String(localized: "Copy your public key to the server (ssh-copy-id -i <key>.pub user@host) and make sure the user may log in with an SSH key.")
        case .hostKeyMismatch(let host):
            String(localized: "If the server was reinstalled, run “ssh-keygen -R \(host)” and connect again.")
        case .connectionRefused:
            String(localized: "Is the SSH service running? On UGREEN: Control Panel → Terminal → enable SSH. Check the port.")
        case .hostUnreachable, .timeout:
            String(localized: "Check the network connection, IP address and firewall.")
        case .dnsFailure:
            String(localized: "Check the hostname or enter the IP address directly.")
        case .dockerNotFound:
            String(localized: "Install Docker or check that “docker” is in /usr/bin or /usr/local/bin.")
        case .dockerPermissionDenied:
            String(localized: "Add the user to the “docker” group: sudo usermod -aG docker <user> (then log in again).")
        default:
            nil
        }
    }

    /// Ordnet die stderr-Ausgabe von `ssh` (Exit-Code 255) einem konkreten Fehler zu.
    static func classify(stderr: String, host: ServerHost) -> SSHError {
        let text = stderr.lowercased()
        let hostname = host.hostname

        if text.contains("bad permissions") || text.contains("unprotected private key") {
            return .keyNotReadable(String(localized: "The key file permissions are too open."))
        }
        if text.contains("invalid format") || text.contains("load key") {
            return .keyNotReadable(String(localized: "The key format is invalid or the key is passphrase-protected."))
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
        return .connectionFailed(detail ?? String(localized: "Unknown error (exit code 255)"))
    }
}
