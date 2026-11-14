import AppKit
import SwiftUI

/// Öffnet eigenständige Fenster (Einstellungen, Logs) aus der Menüleisten-App heraus.
@MainActor
final class WindowPresenter: NSObject, NSWindowDelegate {
    static let shared = WindowPresenter()

    private var settingsWindow: NSWindow?
    private var logWindows: [String: NSWindow] = [:]

    func showSettings(store: HostStore, monitor: MonitorViewModel) {
        if let settingsWindow {
            bringToFront(settingsWindow)
            return
        }
        let content = SettingsView()
            .environment(store)
            .environment(monitor)
        let window = makeWindow(
            title: "ServerPulse",
            size: NSSize(width: 840, height: 640),
            content: content,
            unifiedToolbar: true
        )
        window.setFrameAutosaveName("ServerPulse.Settings")
        settingsWindow = window
        bringToFront(window)
    }

    func showLogs(for container: DockerContainer, on host: ServerHost, service: SSHService) {
        let key = "\(host.id.uuidString)/\(container.id)"
        if let window = logWindows[key] {
            bringToFront(window)
            return
        }
        let model = LogViewModel(host: host, container: container, service: service)
        let window = makeWindow(
            title: "\(container.name) – \(host.displayName)",
            size: NSSize(width: 900, height: 600),
            content: LogView(model: model),
            unifiedToolbar: false
        )
        logWindows[key] = window
        bringToFront(window)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindow {
            settingsWindow = nil
        }
        logWindows = logWindows.filter { $0.value !== window }
    }

    private func makeWindow<Content: View>(
        title: String,
        size: NSSize,
        content: Content,
        unifiedToolbar: Bool
    ) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        if unifiedToolbar { style.insert(.fullSizeContentView) }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false

        let hosting = NSHostingController(rootView: content)
        if unifiedToolbar {
            // Übernimmt Navigationstitel und Seitenleisten-Button von SwiftUI in die Fenster-Toolbar,
            // wie in den Systemeinstellungen.
            hosting.sceneBridgingOptions = [.toolbars, .title]
            window.toolbarStyle = .unified
            window.titlebarSeparatorStyle = .automatic
        }
        window.contentViewController = hosting
        window.setContentSize(size)
        window.delegate = self
        window.center()
        return window
    }

    private func bringToFront(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
