import Foundation

/// Systemkennzahlen eines Hosts.
struct SystemStats: Sendable, Equatable {
    var cpuPercent: Double?
    var cpuCores: Int?
    var load1: Double?
    var load5: Double?
    var load15: Double?
    var memTotalBytes: UInt64
    var memUsedBytes: UInt64
    var disks: [DiskUsage]
    var uptime: TimeInterval?

    var memFraction: Double {
        guard memTotalBytes > 0 else { return 0 }
        return min(1, Double(memUsedBytes) / Double(memTotalBytes))
    }

    /// CPU-Auslastung als Anteil 0…1. Fällt auf Load/Kerne zurück, falls keine Messung vorliegt.
    var cpuFraction: Double? {
        if let cpuPercent { return min(1, max(0, cpuPercent / 100)) }
        if let load1, let cpuCores, cpuCores > 0 { return min(1, load1 / Double(cpuCores)) }
        return nil
    }
}

/// Belegung eines Dateisystems laut `df`.
struct DiskUsage: Identifiable, Sendable, Equatable {
    var filesystem: String
    var mountPoint: String
    var totalBytes: UInt64
    var usedBytes: UInt64
    var availableBytes: UInt64

    var id: String { mountPoint }

    /// Wie `df` selbst: belegt / (belegt + verfügbar), reservierte Blöcke ausgenommen.
    var fraction: Double {
        let base = usedBytes + availableBytes
        guard base > 0 else { return 0 }
        return min(1, Double(usedBytes) / Double(base))
    }

    var displayName: String {
        switch mountPoint {
        case "/": String(localized: "System (/)")
        case "/volume1": String(localized: "Storage pool (/volume1)")
        default: mountPoint
        }
    }
}

/// Formatierungshelfer für Größen, Prozente und Laufzeiten.
enum Format {
    private static let gibibyte = 1_073_741_824.0

    static func storage(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / gibibyte
        if gb >= 1024 {
            return (gb / 1024).formatted(.number.precision(.fractionLength(2)).locale(AppLanguage.locale)) + " TB"
        }
        return gb.formatted(.number.precision(.fractionLength(1)).locale(AppLanguage.locale)) + " GB"
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)).locale(AppLanguage.locale))
    }

    static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)).locale(AppLanguage.locale))
    }

    /// Laufzeit in der App-Sprache, z. B. „9 days, 3 hours“ bzw. „9 Tage, 3 Stunden“.
    static func uptime(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = AppLanguage.locale
        formatter.calendar = calendar
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2
        formatter.allowedUnits = seconds >= 86_400 ? [.day, .hour] : [.hour, .minute]
        return formatter.string(from: max(60, seconds)) ?? ""
    }
}
