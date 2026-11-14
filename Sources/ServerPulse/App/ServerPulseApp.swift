import Darwin
import SwiftUI

@main
struct ServerPulseApp: App {
    @State private var store: HostStore
    @State private var monitor: MonitorViewModel

    init() {
        // Ein abgebrochener SSH-Prozess darf die App nie per SIGPIPE beenden.
        signal(SIGPIPE, SIG_IGN)

        let store = HostStore()
        let monitor = MonitorViewModel(store: store)
        _store = State(initialValue: store)
        _monitor = State(initialValue: monitor)
        monitor.startAutoRefresh()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environment(store)
                .environment(monitor)
        } label: {
            MenuBarIcon(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}
