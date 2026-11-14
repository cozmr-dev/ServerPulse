import Foundation
import Observation

/// Kurze Rückmeldung nach einer Container-Aktion.
struct ActionMessage: Identifiable, Equatable, Sendable {
    let id = UUID()
    let isError: Bool
    let text: String
}

/// Zentrale Steuerung: Auto-Refresh, Host-Status und Container-Aktionen.
@MainActor
@Observable
final class MonitorViewModel {
    let store: HostStore
    let service = SSHService()

    private(set) var statuses: [UUID: HostStatus] = [:]
    private(set) var lastRefresh: Date?
    private(set) var isRefreshing = false
    private(set) var busyContainers: Set<String> = []
    private(set) var expandedGroups: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: MonitorViewModel.expandedGroupsKey) ?? [])
    var selectedHostID: UUID?
    var actionMessage: ActionMessage?

    @ObservationIgnored private var refreshLoop: Task<Void, Never>?
    private static let expandedGroupsKey = "ServerPulse.expandedGroups"

    init(store: HostStore) {
        self.store = store
        self.selectedHostID = store.hosts.first(where: \.isEnabled)?.id
    }

    // MARK: Abgeleitete Werte

    var enabledHosts: [ServerHost] {
        store.hosts.filter(\.isEnabled)
    }

    var selectedHost: ServerHost? {
        let hosts = enabledHosts
        return hosts.first { $0.id == selectedHostID } ?? hosts.first
    }

    func status(for hostID: UUID) -> HostStatus {
        statuses[hostID] ?? HostStatus()
    }

    /// `true`, wenn alle aktiven Hosts erreichbar und alle Container unauffällig sind.
    var isHealthy: Bool {
        enabledHosts.allSatisfy { status(for: $0.id).isHealthy }
    }

    /// Anzahl der Probleme eines Hosts (Verbindung, Docker-Rechte, auffällige Container).
    func issueCount(for hostID: UUID) -> Int {
        let status = status(for: hostID)
        var count = status.errorMessage == nil ? 0 : 1
        if let snapshot = status.snapshot {
            if snapshot.docker.isProblem { count += 1 }
            count += snapshot.containers.filter(\.needsAttention).count
        }
        return count
    }

    var issueCount: Int {
        enabledHosts.reduce(0) { $0 + issueCount(for: $1.id) }
    }

    /// Laufende und gestoppte Container über alle aktiven Hosts.
    var containerTotals: (running: Int, stopped: Int) {
        enabledHosts.reduce(into: (running: 0, stopped: 0)) { totals, host in
            guard let containers = statuses[host.id]?.snapshot?.containers else { return }
            let running = containers.filter(\.isRunning).count
            totals.running += running
            totals.stopped += containers.count - running
        }
    }

    func isBusy(_ container: DockerContainer, on host: ServerHost) -> Bool {
        busyContainers.contains(busyKey(container.id, host.id))
    }

    // MARK: Aktualisierung

    /// Startet (bzw. ersetzt) die Auto-Refresh-Schleife gemäß dem eingestellten Intervall.
    func startAutoRefresh(refreshImmediately: Bool = true) {
        refreshLoop?.cancel()
        let interval = store.refreshInterval
        refreshLoop = Task { [weak self] in
            if refreshImmediately {
                await self?.refreshAll()
            }
            guard let seconds = interval.seconds else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, let self else { return }
                await self.refreshAll()
            }
        }
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        await refresh(hosts: enabledHosts)
        pruneStatuses()
        lastRefresh = Date()
        isRefreshing = false
    }

    func refresh(host: ServerHost) async {
        await refresh(hosts: [host])
        lastRefresh = Date()
    }

    /// Nach Änderungen in den Einstellungen aufrufen.
    func hostsDidChange(changedHostID: UUID? = nil) {
        pruneStatuses()
        if let changedHostID {
            statuses[changedHostID] = nil
        }
        if selectedHost?.id != selectedHostID {
            selectedHostID = selectedHost?.id
        }
        if let changedHostID, let host = enabledHosts.first(where: { $0.id == changedHostID }) {
            Task { await refresh(host: host) }
        }
    }

    private func refresh(hosts: [ServerHost]) async {
        guard !hosts.isEmpty else { return }
        for host in hosts {
            statuses[host.id, default: HostStatus()].isLoading = true
        }

        let service = self.service
        await withTaskGroup(of: (UUID, Result<HostSnapshot, any Error>).self) { group in
            for host in hosts {
                group.addTask {
                    do {
                        return (host.id, .success(try await service.fetchStatus(for: host)))
                    } catch {
                        return (host.id, .failure(error))
                    }
                }
            }
            for await (hostID, result) in group {
                apply(result, to: hostID)
            }
        }
    }

    private func apply(_ result: Result<HostSnapshot, any Error>, to hostID: UUID) {
        var status = statuses[hostID] ?? HostStatus()
        status.isLoading = false
        switch result {
        case .success(let snapshot):
            status.snapshot = snapshot
            status.errorMessage = nil
            status.errorSuggestion = nil
        case .failure(let error):
            status.errorMessage = error.localizedDescription
            status.errorSuggestion = (error as? SSHError)?.recoverySuggestion
        }
        statuses[hostID] = status
    }

    private func pruneStatuses() {
        let activeIDs = Set(enabledHosts.map(\.id))
        statuses = statuses.filter { activeIDs.contains($0.key) }
    }

    // MARK: Container-Aktionen

    func perform(_ action: ContainerAction, on container: DockerContainer, host: ServerHost) {
        let key = busyKey(container.id, host.id)
        guard !busyContainers.contains(key) else { return }
        busyContainers.insert(key)

        let service = self.service
        Task {
            do {
                try await service.perform(action, containerID: container.id, on: host)
                show(ActionMessage(isError: false, text: action.successMessage(for: container.name)))
            } catch {
                let suggestion = (error as? SSHError)?.recoverySuggestion.map { " \($0)" } ?? ""
                show(ActionMessage(
                    isError: true,
                    text: "“\(container.name)”: \(error.localizedDescription)\(suggestion)"
                ))
            }
            busyContainers.remove(key)
            await refresh(host: host)
        }
    }

    /// Führt eine Aktion für alle passenden Container eines Compose-Projekts aus.
    /// Beim Starten kommen Datenbanken und Caches zuerst, beim Stoppen zuletzt.
    func perform(_ action: ContainerAction, on group: ContainerGroup, host: ServerHost) {
        let targets: [DockerContainer]
        switch action {
        case .start: targets = group.containers.filter { !$0.isRunning }
        case .stop: targets = group.containers.filter(\.isRunning)
        case .restart: targets = group.containers
        }
        let ordered = targets.sorted { lhs, rhs in
            let left = lhs.isDependency, right = rhs.isDependency
            guard left != right else { return false }
            return action == .stop ? !left : left
        }
        let keys = ordered.map { busyKey($0.id, host.id) }
        guard !ordered.isEmpty, keys.allSatisfy({ !busyContainers.contains($0) }) else { return }
        busyContainers.formUnion(keys)

        let service = self.service
        let ids = ordered.map(\.id)
        let name = group.displayName
        Task {
            do {
                try await service.perform(action, containerIDs: ids, on: host)
                show(ActionMessage(isError: false, text: action.successMessage(forProject: name, count: ids.count)))
            } catch {
                let suggestion = (error as? SSHError)?.recoverySuggestion.map { " \($0)" } ?? ""
                show(ActionMessage(isError: true, text: "“\(name)”: \(error.localizedDescription)\(suggestion)"))
            }
            busyContainers.subtract(keys)
            await refresh(host: host)
        }
    }

    // MARK: Aufgeklappte Gruppen

    func isExpanded(_ group: ContainerGroup, on host: ServerHost) -> Bool {
        expandedGroups.contains(expansionKey(group, host))
    }

    func toggleExpansion(_ group: ContainerGroup, on host: ServerHost) {
        let key = expansionKey(group, host)
        if expandedGroups.contains(key) {
            expandedGroups.remove(key)
        } else {
            expandedGroups.insert(key)
        }
        UserDefaults.standard.set(Array(expandedGroups), forKey: Self.expandedGroupsKey)
    }

    private func expansionKey(_ group: ContainerGroup, _ host: ServerHost) -> String {
        "\(host.id.uuidString)/\(group.id)"
    }

    private func show(_ message: ActionMessage) {
        actionMessage = message
        guard !message.isError else { return }
        Task {
            try? await Task.sleep(for: .seconds(4))
            if actionMessage?.id == message.id {
                actionMessage = nil
            }
        }
    }

    #if DEBUG
    /// Nur für Vorschauen und Screenshots: setzt Messwerte ohne SSH-Abfrage.
    func injectPreview(_ snapshot: HostSnapshot, for hostID: UUID) {
        statuses[hostID] = HostStatus(snapshot: snapshot)
        lastRefresh = snapshot.fetchedAt
    }
    #endif

    private func busyKey(_ containerID: String, _ hostID: UUID) -> String {
        "\(hostID.uuidString)/\(containerID)"
    }
}
