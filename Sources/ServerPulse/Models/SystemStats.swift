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
        case "/": "System (/)"
        case "/volume1": "Speicherpool (/volume1)"
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
            return (gb / 1024).formatted(.number.precision(.fractionLength(2))) + " TB"
        }
        return gb.formatted(.number.precision(.fractionLength(1))) + " GB"
    }

    static func percent(_ fraction: Double) -> String {
        (fraction * 100).formatted(.number.precision(.fractionLength(0))) + " %"
    }

    static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    static func uptime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days) \(days == 1 ? "Tag" : "Tage"), \(hours) Std." }
        if hours > 0 { return "\(hours) Std., \(minutes) Min." }
        return "\(minutes) Min."
    }
}
