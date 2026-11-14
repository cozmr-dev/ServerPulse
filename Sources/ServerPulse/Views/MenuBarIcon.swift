import SwiftUI

/// Menüleisten-Symbol: `server.rack` im Normalfall, Warndreieck bei Problemen.
struct MenuBarIcon: View {
    let monitor: MonitorViewModel

    var body: some View {
        Image(systemName: monitor.isHealthy ? "server.rack" : "exclamationmark.triangle.fill")
            .accessibilityLabel(monitor.isHealthy ? "ServerPulse – alles in Ordnung" : "ServerPulse – Warnung")
    }
}
