import Foundation

/// Eine Gruppe von Containern desselben Docker-Compose-Projekts – oder ein einzelner Container.
struct ContainerGroup: Identifiable, Sendable {
    let project: String?
    let containers: [DockerContainer]

    var id: String {
        if isProject, let project { return "project:\(project)" }
        return "container:\(containers.first?.id ?? UUID().uuidString)"
    }

    /// Nur Projekte mit mehr als einem Container werden als aufklappbare Gruppe dargestellt.
    var isProject: Bool { project != nil && containers.count > 1 }

    var runningCount: Int { containers.filter(\.isRunning).count }
    var isRunning: Bool { runningCount > 0 }
    var allRunning: Bool { runningCount == containers.count }
    var attentionCount: Int { containers.filter(\.needsAttention).count }
    var needsAttention: Bool { attentionCount > 0 }

    /// Projektname aufbereitet, z. B. `uptime-kuma` → „Uptime Kuma“.
    var displayName: String {
        guard let project else { return containers.first?.name ?? "" }
        return project
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// Fasst Container nach Compose-Projekt zusammen, sortiert nach Auffälligkeit und Name.
    static func make(from containers: [DockerContainer]) -> [ContainerGroup] {
        var byProject: [String: [DockerContainer]] = [:]
        var standalone: [DockerContainer] = []
        for container in containers {
            if let project = container.project {
                byProject[project, default: []].append(container)
            } else {
                standalone.append(container)
            }
        }

        var groups = byProject.map { project, members in
            ContainerGroup(project: project, containers: members.sorted(by: memberOrder))
        }
        groups += standalone.map { ContainerGroup(project: nil, containers: [$0]) }

        return groups.sorted { lhs, rhs in
            if lhs.needsAttention != rhs.needsAttention { return lhs.needsAttention }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    private static func memberOrder(_ lhs: DockerContainer, _ rhs: DockerContainer) -> Bool {
        if lhs.needsAttention != rhs.needsAttention { return lhs.needsAttention }
        if lhs.isRunning != rhs.isRunning { return lhs.isRunning }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
