import AppKit
import SwiftUI

/// Seiten des Einstellungsfensters.
enum SettingsPane: Hashable {
    case general
    case host(UUID)
    case newHost
}

/// Einstellungen im Stil der macOS-Systemeinstellungen: Seitenleiste links, Formular rechts.
struct SettingsView: View {
    @Environment(HostStore.self) private var store
    @Environment(MonitorViewModel.self) private var monitor

    @State private var pane: SettingsPane? = .general
    @State private var newHostTemplate = ServerHost.newDraft()

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 300)
        } detail: {
            detail
        }
        .frame(minWidth: 780, minHeight: 560)
    }

    // MARK: Seitenleiste

    private var sidebar: some View {
        List(selection: $pane) {
            SidebarRow(title: "Allgemein", symbol: "gearshape.fill", color: .gray)
                .tag(SettingsPane.general)

            Section("Server") {
                ForEach(store.hosts) { host in
                    SidebarRow(
                        title: host.displayName,
                        subtitle: host.destination,
                        symbol: "server.rack",
                        color: host.isEnabled ? .blue : .gray,
                        statusColor: statusColor(for: host)
                    )
                    .tag(SettingsPane.host(host.id))
                }
                if pane == .newHost {
                    SidebarRow(title: "Neuer Server", subtitle: "Nicht gesichert", symbol: "plus", color: .green)
                        .tag(SettingsPane.newHost)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                Button {
                    newHostTemplate = .newDraft()
                    pane = .newHost
                } label: {
                    Label("Server hinzufügen", systemImage: "plus.circle.fill")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func statusColor(for host: ServerHost) -> Color {
        guard host.isEnabled else { return .gray.opacity(0.5) }
        let status = monitor.status(for: host.id)
        if status.errorMessage != nil { return .red }
        if status.snapshot == nil { return .gray }
        return monitor.issueCount(for: host.id) == 0 ? .green : .orange
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch pane {
        case .host(let id):
            if let host = store.host(with: id) {
                HostSettingsPane(
                    original: host,
                    isNew: false,
                    onSaved: { pane = .host($0) },
                    onCancel: {},
                    onDeleted: { pane = store.hosts.first.map { .host($0.id) } ?? .general }
                )
                .id(id)
            } else {
                GeneralSettingsPane()
            }
        case .newHost:
            HostSettingsPane(
                original: newHostTemplate,
                isNew: true,
                onSaved: { pane = .host($0) },
                onCancel: { pane = store.hosts.first.map { .host($0.id) } ?? .general },
                onDeleted: {}
            )
            .id(newHostTemplate.id)
        case .general, nil:
            GeneralSettingsPane()
        }
    }
}

// MARK: - Seitenleisten-Zeile

private struct SidebarRow: View {
    let title: String
    var subtitle: String?
    let symbol: String
    let color: Color
    var statusColor: Color?

    var body: some View {
        HStack(spacing: 9) {
            IconTile(symbol: symbol, color: color, size: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let statusColor {
                StatusDot(color: statusColor, size: 7)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Allgemein

private struct GeneralSettingsPane: View {
    @Environment(HostStore.self) private var store
    @Environment(MonitorViewModel.self) private var monitor

    var body: some View {
        Form {
            Section {
                PaneHeader(
                    symbol: "gearshape.fill",
                    color: .gray,
                    title: "Allgemein",
                    subtitle: "Aktualisierung und Überblick"
                )
            }

            Section {
                Picker("Automatisch aktualisieren", selection: intervalBinding) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.menuLabel).tag(interval)
                    }
                }
            } header: {
                Text("Aktualisierung")
            } footer: {
                Text(intervalFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let loadError = store.loadError {
                Section {
                    StatusBanner(style: .warning, title: loadError)
                }
            }

            Section("Überblick") {
                LabeledContent("Überwachte Server", value: "\(monitor.enabledHosts.count) von \(store.hosts.count)")
                LabeledContent(
                    "Container",
                    value: "\(monitor.containerTotals.running) laufend, \(monitor.containerTotals.stopped) gestoppt"
                )
                LabeledContent("Version", value: appVersion)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Allgemein")
    }

    private var intervalBinding: Binding<RefreshInterval> {
        Binding(
            get: { store.refreshInterval },
            set: { newValue in
                guard newValue != store.refreshInterval else { return }
                store.refreshInterval = newValue
                monitor.startAutoRefresh(refreshImmediately: false)
            }
        )
    }

    private var intervalFooter: String {
        if store.refreshInterval == .manual {
            return "Daten werden nur über ↻ im Menü oder mit ⌘R aktualisiert."
        }
        return "ServerPulse fragt alle aktiven Server \(store.refreshInterval.longLabel) per SSH ab."
    }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }
}

// MARK: - Server

private struct HostSettingsPane: View {
    let isNew: Bool
    let onSaved: (UUID) -> Void
    let onCancel: () -> Void
    let onDeleted: () -> Void

    @Environment(HostStore.self) private var store
    @Environment(MonitorViewModel.self) private var monitor

    @State private var draft: ServerHost
    @State private var testResult: ConnectionTestResult?
    @State private var isTesting = false
    @State private var confirmDelete = false

    init(
        original: ServerHost,
        isNew: Bool,
        onSaved: @escaping (UUID) -> Void,
        onCancel: @escaping () -> Void,
        onDeleted: @escaping () -> Void
    ) {
        _draft = State(initialValue: original)
        self.isNew = isNew
        self.onSaved = onSaved
        self.onCancel = onCancel
        self.onDeleted = onDeleted
    }

    var body: some View {
        Form {
            Section {
                PaneHeader(
                    symbol: "server.rack",
                    color: draft.isEnabled ? .blue : .gray,
                    title: isNew && draft.hostname.isEmpty ? "Neuer Server" : draft.displayName,
                    subtitle: draft.hostname.isEmpty ? "Verbindung per SSH-Key" : "\(draft.destination) · Port \(String(draft.port))"
                ) {
                    if !isNew { connectionPill }
                }
            }

            Section {
                TextField("Name", text: $draft.name, prompt: Text("z. B. UGREEN NAS"))
                TextField("Hostname oder IP", text: $draft.hostname, prompt: Text("192.168.1.100"))
                TextField("SSH-Port", value: $draft.port, format: .number.grouping(.never))
                TextField("Benutzer", text: $draft.username, prompt: Text("admin"))
            } header: {
                Text("Verbindung")
            }

            Section {
                HStack {
                    TextField("Privater Schlüssel", text: keyPathBinding, prompt: Text("~/.ssh/id_ed25519"))
                    Button("Auswählen …", action: chooseKey)
                }
            } header: {
                Text("Authentifizierung")
            } footer: {
                Text("Leer lassen, um ~/.ssh/config und den ssh-agent zu nutzen. Passwort-Login wird nicht unterstützt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Toggle("In der Menüleiste überwachen", isOn: $draft.isEnabled)
            } header: {
                Text("Überwachung")
            }

            Section {
                HStack(spacing: 10) {
                    Button {
                        runTest()
                    } label: {
                        Label("Verbindung testen", systemImage: "bolt.horizontal.circle")
                    }
                    .disabled(isTesting || draft.validationError != nil)
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                        Text("Verbinde …")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if let testResult {
                    TestResultRow(result: testResult)
                }
            } header: {
                Text("Verbindungstest")
            }

            if !isNew {
                Section {
                    Button("Server entfernen …", role: .destructive) {
                        confirmDelete = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(isNew ? "Neuer Server" : draft.displayName)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if hasChanges {
                saveBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: hasChanges)
        .animation(.easeInOut(duration: 0.2), value: testResult)
        .confirmationDialog(
            "„\(draft.displayName)“ entfernen?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Entfernen", role: .destructive, action: delete)
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Der Server wird aus ServerPulse entfernt. Auf dem Server selbst wird nichts verändert.")
        }
    }

    // MARK: Teilansichten

    private var connectionPill: some View {
        let status = monitor.status(for: draft.id)
        if !draft.isEnabled { return StatusPill(text: "Deaktiviert", color: .gray) }
        if status.errorMessage != nil { return StatusPill(text: "Nicht erreichbar", color: .red) }
        if status.snapshot == nil { return StatusPill(text: "Nicht geprüft", color: .gray) }
        let issues = monitor.issueCount(for: draft.id)
        return issues == 0
            ? StatusPill(text: "Verbunden", color: .green)
            : StatusPill(text: issues == 1 ? "1 Hinweis" : "\(issues) Hinweise", color: .orange)
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                if let problem = draft.validationError {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else {
                    Text(isNew ? "Neuer Server – noch nicht gesichert" : "Ungesicherte Änderungen")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(isNew ? "Abbrechen" : "Verwerfen", action: revert)
                Button("Sichern", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.validationError != nil)
            }
            .font(.callout)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(.bar)
    }

    private var keyPathBinding: Binding<String> {
        Binding(
            get: { draft.privateKeyPath ?? "" },
            set: { draft.privateKeyPath = $0.isEmpty ? nil : $0 }
        )
    }

    private var hasChanges: Bool {
        isNew || store.host(with: draft.id) != draft
    }

    // MARK: Aktionen

    private func save() {
        guard draft.validationError == nil else { return }
        var host = draft
        host.name = host.name.trimmingCharacters(in: .whitespacesAndNewlines)
        host.hostname = host.hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        host.username = host.username.trimmingCharacters(in: .whitespacesAndNewlines)
        if let key = host.privateKeyPath?.trimmingCharacters(in: .whitespacesAndNewlines) {
            host.privateKeyPath = key.isEmpty ? nil : key
        }
        if isNew {
            store.add(host)
        } else {
            store.update(host)
        }
        draft = host
        monitor.hostsDidChange(changedHostID: host.id)
        onSaved(host.id)
    }

    private func revert() {
        testResult = nil
        if isNew {
            onCancel()
        } else if let stored = store.host(with: draft.id) {
            draft = stored
        }
    }

    private func delete() {
        store.delete(id: draft.id)
        monitor.hostsDidChange()
        onDeleted()
    }

    private func runTest() {
        isTesting = true
        testResult = nil
        let candidate = draft
        let service = monitor.service
        Task {
            let result = await service.testConnection(candidate)
            testResult = result
            isTesting = false
        }
    }

    private func chooseKey() {
        let panel = NSOpenPanel()
        panel.title = "Privaten SSH-Schlüssel auswählen"
        panel.prompt = "Auswählen"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        draft.privateKeyPath = path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

/// Ergebnis eines Verbindungstests als Formularzeile.
private struct TestResultRow: View {
    let result: ConnectionTestResult

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
                .font(.system(size: 20, weight: .medium))
            VStack(alignment: .leading, spacing: 3) {
                Text(result.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(result.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var symbol: String {
        switch result.level {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failure: "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch result.level {
        case .success: .green
        case .warning: .orange
        case .failure: .red
        }
    }
}
