import Foundation
import Observation

/// Persistiert die konfigurierten Hosts und Einstellungen in `UserDefaults`.
@MainActor
@Observable
final class HostStore {
    private enum Keys {
        static let hosts = "ServerPulse.hosts.v1"
        static let didSeed = "ServerPulse.didSeedExample"
        static let refreshInterval = "ServerPulse.refreshInterval"
    }

    private(set) var hosts: [ServerHost]
    private(set) var loadError: String?

    var refreshInterval: RefreshInterval {
        didSet { defaults.set(refreshInterval.rawValue, forKey: Keys.refreshInterval) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.object(forKey: Keys.refreshInterval) != nil,
           let interval = RefreshInterval(rawValue: defaults.integer(forKey: Keys.refreshInterval)) {
            refreshInterval = interval
        } else {
            refreshInterval = .default
        }

        var loaded: [ServerHost] = []
        var problem: String?
        if let data = defaults.data(forKey: Keys.hosts) {
            do {
                loaded = try JSONDecoder().decode([ServerHost].self, from: data)
            } catch {
                problem = String(localized: "Saved servers could not be read: \(error.localizedDescription)")
            }
        }
        hosts = loaded
        loadError = problem

        if !defaults.bool(forKey: Keys.didSeed) {
            defaults.set(true, forKey: Keys.didSeed)
            if hosts.isEmpty {
                hosts = [.example]
                save()
            }
        }
    }

    func add(_ host: ServerHost) {
        hosts.append(host)
        save()
    }

    func update(_ host: ServerHost) {
        guard let index = hosts.firstIndex(where: { $0.id == host.id }) else {
            add(host)
            return
        }
        hosts[index] = host
        save()
    }

    func delete(id: UUID) {
        hosts.removeAll { $0.id == id }
        save()
    }

    func host(with id: UUID) -> ServerHost? {
        hosts.first { $0.id == id }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(hosts)
            defaults.set(data, forKey: Keys.hosts)
            loadError = nil
        } catch {
            loadError = String(localized: "Servers could not be saved: \(error.localizedDescription)")
        }
    }
}
