import AppKit
import SwiftUI

/// Scrollbares Log-Fenster mit Filter, Zeilenauswahl und Kopier-Button.
struct LogView: View {
    @State var model: LogViewModel
    @State private var filter = ""
    @State private var didCopy = false

    private static let lineOptions = [100, 500, 1000]
    private static let bottomID = "log-bottom"

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            statusBar
        }
        .frame(minWidth: 600, minHeight: 380)
        .task { await model.load() }
    }

    // MARK: Kopfbereich

    private var header: some View {
        HStack(spacing: 12) {
            ContainerIconView(container: model.container, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.container.name)
                    .font(.system(size: 14, weight: .semibold))
                Text("\(model.host.displayName) · \(model.container.localizedStatus)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            SearchField(text: $filter, prompt: "Logs filtern")
                .frame(width: 180)

            Picker("Zeilen", selection: $model.lineCount) {
                ForEach(Self.lineOptions, id: \.self) { count in
                    Text("\(count)").tag(count)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Anzahl der geladenen Zeilen")
            .onChange(of: model.lineCount) {
                Task { await model.load() }
            }

            CircleIconButton(systemImage: "arrow.clockwise", help: "Neu laden (⌘R)") {
                Task { await model.load() }
            }
            .disabled(model.isLoading)
            .keyboardShortcut("r")

            CircleIconButton(
                systemImage: didCopy ? "checkmark" : "doc.on.doc",
                help: "In die Zwischenablage kopieren",
                tint: didCopy ? .green : .primary
            ) {
                copyLogs()
            }
            .disabled(model.text.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: Inhalt

    @ViewBuilder
    private var content: some View {
        if let error = model.errorMessage {
            VStack {
                StatusBanner(
                    style: .error,
                    title: "Logs konnten nicht geladen werden",
                    message: error,
                    actionTitle: "Erneut versuchen",
                    action: { Task { await model.load() } }
                )
                .padding(16)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.text.isEmpty && model.isLoading {
            ProgressView("Lade Logs …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(displayedText)
                            .font(.system(size: 11.5, design: .monospaced))
                            .lineSpacing(2.5)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: true, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomID)
                    }
                    .padding(16)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(alignment: .topTrailing) {
                    if model.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(12)
                    }
                }
                .onAppear { proxy.scrollTo(Self.bottomID, anchor: .bottomLeading) }
                .onChange(of: model.text) {
                    proxy.scrollTo(Self.bottomID, anchor: .bottomLeading)
                }
            }
        }
    }

    private var statusBar: some View {
        HStack {
            Text(lineSummary)
            Spacer()
            if let loadedAt = model.loadedAt {
                Text("Stand \(loadedAt.formatted(date: .omitted, time: .standard))")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: Daten

    private var displayedText: String {
        let query = filter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.text }
        let matches = model.text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.localizedCaseInsensitiveContains(query) }
        return matches.isEmpty ? "Keine Zeilen enthalten „\(query)“." : matches.joined(separator: "\n")
    }

    private var lineSummary: String {
        let total = model.text.isEmpty ? 0 : model.text.split(separator: "\n").count
        let query = filter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return "\(total) Zeilen" }
        let shown = model.text.split(separator: "\n").filter { $0.localizedCaseInsensitiveContains(query) }.count
        return "\(shown) von \(total) Zeilen"
    }

    private func copyLogs() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(displayedText, forType: .string)
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }
}
