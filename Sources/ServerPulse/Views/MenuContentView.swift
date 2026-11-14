import AppKit
import SwiftUI

/// Hauptansicht im Menüleisten-Fenster.
struct MenuContentView: View {
    @Environment(MonitorViewModel.self) private var monitor
    @Environment(HostStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            if monitor.enabledHosts.count > 1 {
                HostSwitcher()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            Divider().opacity(0.6)

            Group {
                if monitor.enabledHosts.isEmpty {
                    emptyState
                } else if let host = monitor.selectedHost {
                    HostDetailView(host: host)
                        .id(host.id)
                        .transition(.opacity)
                }
            }
            .frame(maxHeight: .infinity)

            Divider().opacity(0.6)
            FooterView()
        }
        .frame(width: 420, height: 640)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            if let message = monitor.actionMessage, !message.isError {
                ToastView(text: message.text)
                    .padding(.bottom, 52)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: monitor.actionMessage)
        .animation(.easeInOut(duration: 0.2), value: monitor.selectedHost?.id)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No active servers", systemImage: "server.rack")
        } description: {
            Text("Add a server in Settings or enable an existing one.")
        } actions: {
            Button("Open Settings") {
                WindowPresenter.shared.showSettings(store: store, monitor: monitor)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Kopfzeile

struct HeaderView: View {
    @Environment(MonitorViewModel.self) private var monitor
    @Environment(HostStore.self) private var store

    var body: some View {
        HStack(spacing: 11) {
            IconTile(
                symbol: monitor.isHealthy ? "server.rack" : "exclamationmark.triangle.fill",
                color: monitor.isHealthy ? .blue : .orange,
                size: 34
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("ServerPulse")
                    .font(.system(size: 15, weight: .semibold))
                HStack(spacing: 5) {
                    StatusDot(color: summaryColor, size: 6)
                    Text(summaryText)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }

            Spacer()

            ZStack {
                CircleIconButton(systemImage: "arrow.clockwise", help: String(localized: "Refresh now (⌘R)")) {
                    Task { await monitor.refreshAll() }
                }
                .opacity(monitor.isRefreshing ? 0 : 1)
                .disabled(monitor.isRefreshing)
                .keyboardShortcut("r")

                if monitor.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.primary.opacity(0.07)))
                }
            }

            CircleIconButton(systemImage: "gearshape.fill", help: String(localized: "Settings (⌘,)")) {
                WindowPresenter.shared.showSettings(store: store, monitor: monitor)
            }
            .keyboardShortcut(",")
        }
    }

    private var summaryColor: Color {
        if monitor.lastRefresh == nil { return .gray }
        return monitor.issueCount == 0 ? .green : .orange
    }

    private var summaryText: String {
        guard let date = monitor.lastRefresh else {
            return monitor.isRefreshing ? String(localized: "Connecting …") : String(localized: "Not refreshed yet")
        }
        let time = date.formatted(date: .omitted, time: .standard)
        let issues = monitor.issueCount
        let state = issues == 0 ? String(localized: "All good") : (issues == 1 ? String(localized: "1 issue") : String(localized: "\(issues) issues"))
        return "\(state) · \(time)"
    }
}

// MARK: - Server-Umschalter

struct HostSwitcher: View {
    @Environment(MonitorViewModel.self) private var monitor
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(monitor.enabledHosts) { host in
                let isSelected = monitor.selectedHost?.id == host.id
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        monitor.selectedHostID = host.id
                    }
                } label: {
                    HStack(spacing: 6) {
                        StatusDot(color: dotColor(for: host), size: 6)
                        Text(host.displayName)
                            .lineLimit(1)
                    }
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.16) : Color.white)
                                .shadow(color: .black.opacity(0.12), radius: 1.5, y: 0.5)
                                .matchedGeometryEffect(id: "selection", in: namespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.07)))
    }

    private func dotColor(for host: ServerHost) -> Color {
        let status = monitor.status(for: host.id)
        if status.snapshot == nil && status.errorMessage == nil { return .gray }
        if status.errorMessage != nil { return .red }
        return monitor.issueCount(for: host.id) == 0 ? .green : .orange
    }
}

// MARK: - Host-Inhalt

struct HostDetailView: View {
    let host: ServerHost
    @Environment(MonitorViewModel.self) private var monitor

    var body: some View {
        let status = monitor.status(for: host.id)
        ScrollView {
            VStack(spacing: 16) {
                if let message = monitor.actionMessage, message.isError {
                    StatusBanner(
                        style: .error,
                        title: String(localized: "Action failed"),
                        message: message.text,
                        onDismiss: { monitor.actionMessage = nil }
                    )
                }

                if let snapshot = status.snapshot {
                    if let error = status.errorMessage {
                        StatusBanner(
                            style: .warning,
                            title: String(localized: "Connection lost"),
                            message: [error, status.errorSuggestion, staleHint(snapshot)]
                                .compactMap { $0 }
                                .joined(separator: "\n"),
                            actionTitle: status.isLoading ? nil : String(localized: "Try again"),
                            action: { Task { await monitor.refresh(host: host) } }
                        )
                    }
                    SystemOverviewView(host: host, stats: snapshot.stats)
                    ContainerListView(host: host, snapshot: snapshot)
                } else if let error = status.errorMessage {
                    ConnectionErrorView(
                        host: host,
                        message: error,
                        suggestion: status.errorSuggestion,
                        isLoading: status.isLoading
                    )
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Connecting to \(host.destination) …")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 150)
                }
            }
            .padding(16)
        }
        .scrollIndicators(.automatic)
    }

    private func staleHint(_ snapshot: HostSnapshot) -> String {
        String(localized: "Showing data from \(snapshot.fetchedAt.formatted(date: .omitted, time: .standard)).")
    }
}

/// Großer Fehlerzustand, wenn noch nie Daten geladen werden konnten.
struct ConnectionErrorView: View {
    let host: ServerHost
    let message: String
    let suggestion: String?
    let isLoading: Bool

    @Environment(MonitorViewModel.self) private var monitor

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(.orange)
                .padding(.bottom, 4)
            Text("\(host.displayName) is not reachable")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            if let suggestion {
                Text(suggestion)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
            Button {
                Task { await monitor.refresh(host: host) }
            } label: {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Try again")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(isLoading)
            .padding(.top, 6)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .card()
        .padding(.top, 40)
    }
}

// MARK: - Fußzeile

struct FooterView: View {
    @Environment(MonitorViewModel.self) private var monitor
    @Environment(HostStore.self) private var store

    var body: some View {
        HStack {
            Text(summary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .keyboardShortcut("q")
            .help("Quit ServerPulse (⌘Q)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private var summary: String {
        let hosts = monitor.enabledHosts.count
        let totals = monitor.containerTotals
        let containers = totals.running + totals.stopped
        let interval = store.refreshInterval.longLabel
        return String(localized: "\(hosts) servers · \(containers) containers · \(interval)")
    }
}
