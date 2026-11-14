import SwiftUI

/// Übersichtskarte eines Hosts: Name, Uptime und Ring-Anzeigen für CPU, RAM und Speicher.
struct SystemOverviewView: View {
    let host: ServerHost
    let stats: SystemStats

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(host.displayName)
                        .font(.system(size: 16, weight: .semibold))
                    Text("\(host.destination) · Port \(String(host.port))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let uptime = stats.uptime {
                    Label(Format.uptime(uptime), systemImage: "clock")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                        .help("Uptime")
                }
            }

            HStack(alignment: .top, spacing: 0) {
                MetricGauge(
                    title: "CPU",
                    symbol: "cpu",
                    fraction: stats.cpuFraction,
                    detail: cpuDetail
                )
                MetricGauge(
                    title: "RAM",
                    symbol: "memorychip",
                    fraction: stats.memTotalBytes > 0 ? stats.memFraction : nil,
                    detail: "\(Format.storage(stats.memUsedBytes)) / \(Format.storage(stats.memTotalBytes))"
                )
                MetricGauge(
                    title: primaryDisk.map { $0.mountPoint == "/" ? "System" : "Speicher" } ?? "Speicher",
                    symbol: "internaldrive",
                    fraction: primaryDisk?.fraction,
                    detail: primaryDisk.map { "\(Format.storage($0.usedBytes)) / \(Format.storage($0.totalBytes))" } ?? "–"
                )
                .help(primaryDisk.map { "\($0.mountPoint) · \($0.filesystem)" } ?? "")
            }

            if !secondaryDisks.isEmpty {
                VStack(spacing: 10) {
                    ForEach(secondaryDisks) { disk in
                        DiskRow(disk: disk)
                    }
                }
            }
        }
        .card(padding: 16)
    }

    /// Größtes Volume (bei UGREEN meist `/volume1`) als Hauptanzeige.
    private var primaryDisk: DiskUsage? {
        stats.disks.max { $0.totalBytes < $1.totalBytes }
    }

    private var secondaryDisks: [DiskUsage] {
        stats.disks.filter { $0.id != primaryDisk?.id }
    }

    private var cpuDetail: String {
        var parts: [String] = []
        if let cores = stats.cpuCores { parts.append("\(cores) Kerne") }
        if let load = stats.load1 { parts.append("Load \(Format.decimal(load))") }
        return parts.isEmpty ? "–" : parts.joined(separator: " · ")
    }
}

private struct MetricGauge: View {
    let title: String
    let symbol: String
    let fraction: Double?
    let detail: String

    var body: some View {
        VStack(spacing: 9) {
            UsageRing(fraction: fraction)
                .frame(width: 66, height: 66)
            VStack(spacing: 2) {
                Label(title, systemImage: symbol)
                    .font(.system(size: 11.5, weight: .semibold))
                    .labelStyle(.titleAndIcon)
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DiskRow: View {
    let disk: DiskUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(disk.displayName, systemImage: "internaldrive")
                    .font(.system(size: 11.5, weight: .medium))
                Spacer()
                Text("\(Format.storage(disk.usedBytes)) von \(Format.storage(disk.totalBytes)) · \(Format.percent(disk.fraction))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            UsageBar(fraction: disk.fraction)
        }
        .help(disk.filesystem)
    }
}
