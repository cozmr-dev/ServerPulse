import Foundation

/// Auswählbare Intervalle für die automatische Aktualisierung.
enum RefreshInterval: Int, CaseIterable, Identifiable, Codable, Sendable {
    case manual = 0
    case fiveSeconds = 5
    case fifteenSeconds = 15
    case thirtySeconds = 30
    case sixtySeconds = 60

    static let `default`: RefreshInterval = .fifteenSeconds

    var id: Int { rawValue }

    /// Intervall in Sekunden, `nil` bei manueller Aktualisierung.
    var seconds: Int? { self == .manual ? nil : rawValue }

    var label: String {
        switch self {
        case .manual: String(localized: "Manual")
        default: String(localized: "\(rawValue) s")
        }
    }

    var menuLabel: String {
        switch self {
        case .manual: String(localized: "Manual")
        case .sixtySeconds: String(localized: "Every minute")
        default: String(localized: "Every \(rawValue) seconds")
        }
    }

    var longLabel: String {
        switch self {
        case .manual: String(localized: "manual")
        default: String(localized: "every \(rawValue) s")
        }
    }
}
