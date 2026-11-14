import AppKit
import SwiftUI

/// Docker-Container eines Hosts – laufende oben, gestoppte unten, mit Suchfeld.
struct ContainerListView: View {
    let host: ServerHost
    let snapshot: HostSnapshot

    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Container")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if snapshot.docker == .available {
                    HStack(spacing: 8) {
                        countLabel(running.count, "aktiv", color: .green)
                        if !stopped.isEmpty {
                            countLabel(stopped.count, "gestoppt", color: .secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 2)

            switch snapshot.docker {
            case .available:
                if snapshot.containers.isEmpty {
                    placeholder(symbol: "shippingbox", text: "Keine Container vorhanden")
                } else {
                    SearchField(text: $searchText, prompt: "Container suchen")
                    sections
                }
            case .notInstalled:
                StatusBanner(
                    style: .info,
                    title: "Docker wurde nicht gefunden",
                    message: SSHError.dockerNotFound.recoverySuggestion
                )
            case .permissionDenied(let detail):
                StatusBanner(
                    style: .warning,
                    title: "Keine Berechtigung für Docker",
                    message: "\(detail)\n\(SSHError.dockerPermissionDenied(detail).recoverySuggestion ?? "")"
                )
            case .error(let detail):
                StatusBanner(style: .warning, title: "Docker-Fehler", message: detail)
            }
        }
    }

    // MARK: Teilansichten

    @ViewBuilder
    private var sections: some View {
        let groups = filteredGroups
        let active = groups.filter(\.isRunning)
        let inactive = groups.filter { !$0.isRunning }

        if groups.isEmpty {
            placeholder(symbol: "magnifyingglass", text: "Keine Treffer für „\(searchText)“")
        }
        if !active.isEmpty {
            section(title: "Laufend", groups: active)
        }
        if !inactive.isEmpty {
            section(title: "Gestoppt", groups: inactive)
        }
    }

    private func section(title: String, groups: [ContainerGroup]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
            VStack(spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    if group.isProject {
                        ProjectGroupView(host: host, group: group, forceExpanded: isSearching)
                    } else if let container = group.containers.first {
                        ContainerRowView(host: host, container: container)
                    }
                    if index < groups.count - 1 {
                        Divider()
                            .opacity(0.5)
                            .padding(.leading, 50)
                    }
                }
            }
            .card(padding: 4, cornerRadius: 12)
        }
    }

    private func countLabel(_ count: Int, _ label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            StatusDot(color: color == .secondary ? .gray : color, size: 6)
            Text("\(count) \(label)")
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    private func placeholder(symbol: String, text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: Daten

    private var running: [DockerContainer] { snapshot.containers.filter(\.isRunning) }
    private var stopped: [DockerContainer] { snapshot.containers.filter { !$0.isRunning } }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Gruppen nach Compose-Projekt; bei aktiver Suche nur Container mit Treffer.
    private var filteredGroups: [ContainerGroup] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let groups = ContainerGroup.make(from: snapshot.containers)
        guard !query.isEmpty else { return groups }
        return groups.compactMap { group in
            let projectMatches = group.project?.localizedCaseInsensitiveContains(query) ?? false
            let matches = projectMatches ? group.containers : group.containers.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                    || $0.image.localizedCaseInsensitiveContains(query)
                    || $0.localizedStatus.localizedCaseInsensitiveContains(query)
            }
            guard !matches.isEmpty else { return nil }
            return ContainerGroup(project: group.project, containers: matches)
        }
    }
}

/// Aufklappbare Gruppe für ein Docker-Compose-Projekt.
struct ProjectGroupView: View {
    let host: ServerHost
    let group: ContainerGroup
    var forceExpanded = false

    @Environment(MonitorViewModel.self) private var monitor
    @State private var isHovering = false
    @State private var membersHeight: CGFloat = 0

    var body: some View {
        let expanded = forceExpanded || monitor.isExpanded(group, on: host)

        VStack(spacing: 0) {
            header(expanded: expanded)
                .zIndex(1)

            // Schubladen-Animation: Die Zeilen bleiben im Layout, nur die sichtbare Höhe
            // wird animiert und abgeschnitten – so überlappt nichts mit den Nachbarzeilen.
            members
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: MembersHeightKey.self, value: proxy.size.height)
                    }
                )
                .frame(height: expanded ? membersHeight : 0, alignment: .top)
                .clipped()
                .opacity(expanded ? 1 : 0)
                .allowsHitTesting(expanded)
                .accessibilityHidden(!expanded)
        }
        .onPreferenceChange(MembersHeightKey.self) { height in
            membersHeight = height
        }
    }

    private var members: some View {
        VStack(spacing: 0) {
            ForEach(group.containers) { container in
                ContainerRowView(host: host, container: container, isNested: true)
            }
        }
        .padding(.leading, 20)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(Color.primary.opacity(0.1))
                .frame(width: 2)
                .padding(.leading, 16)
                .padding(.vertical, 6)
        }
    }

    private func header(expanded: Bool) -> some View {
        let appearance = ContainerAppearance.resolve(key: group.project ?? "", fallback: group.containers.first)
        let isBusy = group.containers.contains { monitor.isBusy($0, on: host) }

        return HStack(spacing: 11) {
            IconTile(symbol: appearance.symbol, color: appearance.color, size: 30)
                .saturation(group.isRunning ? 1 : 0.15)
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                        .offset(x: 3, y: 3)
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(group.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text("\(group.containers.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(summaryStyle)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 24, height: 24)
            } else if isHovering {
                groupMenu
                    .transition(.opacity)
            } else if !expanded {
                memberIcons
                    .transition(.opacity)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .frame(width: 12)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isHovering ? Color.primary.opacity(0.06) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onTapGesture {
            guard !forceExpanded else { return }
            withAnimation(.spring(duration: 0.3)) {
                monitor.toggleExpansion(group, on: host)
            }
        }
        .contextMenu { groupMenuItems }
        .help(expanded ? "Zuklappen" : "Aufklappen")
        .accessibilityAddTraits(.isButton)
    }

    /// Überlappende Mini-Icons der enthaltenen Container.
    private var memberIcons: some View {
        HStack(spacing: -6) {
            ForEach(group.containers.prefix(4)) { container in
                let appearance = ContainerAppearance.resolve(for: container)
                IconTile(symbol: appearance.symbol, color: appearance.color, size: 18)
                    .saturation(container.isRunning ? 1 : 0.1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18 * 0.26, style: .continuous)
                            .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5)
                    )
            }
        }
    }

    private var groupMenu: some View {
        Menu {
            groupMenuItems
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .bold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(0.08)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Aktionen für das ganze Projekt")
    }

    @ViewBuilder
    private var groupMenuItems: some View {
        Button("Alle neu starten", systemImage: "arrow.clockwise") {
            monitor.perform(.restart, on: group, host: host)
        }
        if group.runningCount < group.containers.count {
            Button("Alle starten", systemImage: "play.fill") {
                monitor.perform(.start, on: group, host: host)
            }
        }
        if group.isRunning {
            Button("Alle stoppen", systemImage: "stop.fill") {
                monitor.perform(.stop, on: group, host: host)
            }
        }
    }

    private var statusColor: Color {
        if group.needsAttention { return .red }
        if group.allRunning {
            return group.containers.contains { $0.health == .unhealthy } ? .orange : .green
        }
        return group.isRunning ? .orange : .gray
    }

    private var summary: String {
        let total = group.containers.count
        if group.needsAttention {
            return group.attentionCount == 1 ? "1 Container mit Problem" : "\(group.attentionCount) Container mit Problemen"
        }
        if group.allRunning { return "\(total) Container · alle laufen" }
        if group.isRunning { return "\(group.runningCount) von \(total) laufen" }
        return "\(total) Container · gestoppt"
    }

    private var summaryStyle: AnyShapeStyle {
        if group.needsAttention { return AnyShapeStyle(.red) }
        if group.isRunning && !group.allRunning { return AnyShapeStyle(.orange) }
        return AnyShapeStyle(.secondary)
    }
}

/// Eine Container-Zeile; Aktionen erscheinen beim Hover bzw. per Rechtsklick.
struct ContainerRowView: View {
    let host: ServerHost
    let container: DockerContainer
    var isNested = false

    @Environment(MonitorViewModel.self) private var monitor
    @State private var isHovering = false

    var body: some View {
        let isBusy = monitor.isBusy(container, on: host)

        HStack(spacing: 11) {
            ContainerIconView(container: container, size: isNested ? 24 : 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(container.name)
                    .font(.system(size: isNested ? 12.5 : 13, weight: .medium))
                    .lineLimit(1)
                (
                    Text(container.localizedStatus)
                        .foregroundStyle(container.needsAttention ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    + Text("  ·  \(container.shortImage)")
                        .foregroundStyle(.tertiary)
                )
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.tail)
            }

            Spacer(minLength: 6)

            ZStack(alignment: .trailing) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 24, height: 24)
                } else if isHovering {
                    actionButtons
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
                } else {
                    healthBadge
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: isHovering)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, isNested ? 5 : 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isHovering ? Color.primary.opacity(0.06) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu { contextMenuItems }
        .help(container.image)
    }

    @ViewBuilder
    private var healthBadge: some View {
        if container.needsAttention && !container.isRunning {
            StatusPill(text: "Fehler", color: .red)
        } else {
            switch container.health {
            case .unhealthy:
                StatusPill(text: "Unhealthy", color: .orange)
            case .starting:
                StatusPill(text: "Startet", color: .blue)
            case .healthy:
                Image(systemName: "heart.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green.opacity(0.75))
                    .help("Health-Check: gesund")
            case .none:
                EmptyView()
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 5) {
            CircleIconButton(systemImage: "arrow.clockwise", help: "Neu starten", size: 24) {
                monitor.perform(.restart, on: container, host: host)
            }
            if container.isRunning {
                CircleIconButton(systemImage: "stop.fill", help: "Stoppen", size: 24) {
                    monitor.perform(.stop, on: container, host: host)
                }
            } else {
                CircleIconButton(systemImage: "play.fill", help: "Starten", size: 24, tint: .green) {
                    monitor.perform(.start, on: container, host: host)
                }
            }
            CircleIconButton(systemImage: "text.alignleft", help: "Logs anzeigen", size: 24) {
                showLogs()
            }
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Neu starten", systemImage: "arrow.clockwise") {
            monitor.perform(.restart, on: container, host: host)
        }
        if container.isRunning {
            Button("Stoppen", systemImage: "stop.fill") {
                monitor.perform(.stop, on: container, host: host)
            }
        } else {
            Button("Starten", systemImage: "play.fill") {
                monitor.perform(.start, on: container, host: host)
            }
        }
        Divider()
        Button("Logs anzeigen", systemImage: "text.alignleft") {
            showLogs()
        }
        Button("Container-ID kopieren", systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(container.id, forType: .string)
        }
    }

    private func showLogs() {
        WindowPresenter.shared.showLogs(for: container, on: host, service: monitor.service)
    }
}

/// Misst die natürliche Höhe der Projekt-Mitglieder für die Aufklapp-Animation.
private struct MembersHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
