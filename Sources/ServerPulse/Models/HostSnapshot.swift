import Foundation

/// Verfügbarkeit von Docker auf einem Host.
enum DockerAvailability: Sendable, Equatable {
    case available
    case notInstalled
    case permissionDenied(String)
    case error(String)

    var isProblem: Bool {
        switch self {
        case .available, .notInstalled: false
        case .permissionDenied, .error: true
        }
    }
}

/// Ein vollständiger Messwert-Satz eines Hosts.
struct HostSnapshot: Sendable, Equatable {
    var stats: SystemStats
    var containers: [DockerContainer]
    var docker: DockerAvailability
    var fetchedAt: Date
}

/// Laufzeitstatus eines Hosts in der UI.
struct HostStatus: Sendable, Equatable {
    var snapshot: HostSnapshot?
    var errorMessage: String?
    var errorSuggestion: String?
    var isLoading = false

    var isHealthy: Bool {
        if errorMessage != nil { return false }
        guard let snapshot else { return true }
        if snapshot.docker.isProblem { return false }
        return !snapshot.containers.contains(where: \.needsAttention)
    }
}

/// Ergebnis eines „Verbindung testen“-Aufrufs.
struct ConnectionTestResult: Sendable, Equatable {
    enum Level: Sendable {
        case success
        case warning
        case failure
    }

    var level: Level
    var title: String
    var detail: String
}
