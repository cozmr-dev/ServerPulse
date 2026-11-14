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

            SearchField(text: $filter, prompt: String(localized: "Filter logs"))
                .frame(width: 180)

            Picker("Lines", selection: $model.lineCount) {
                ForEach(Self.lineOptions, id: \.self) { count in
                    Text("\(count)").tag(count)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Number of lines to load")
            .onChange(of: model.lineCount) {
                Task { await model.load() }
            }

            CircleIconButton(systemImage: "arrow.clockwise", help: String(localized: "Reload (⌘R)")) {
                Task { await model.load() }
            }
            .disabled(model.isLoading)
            .keyboardShortcut("r")

            CircleIconButton(
                systemImage: didCopy ? "checkmark" : "doc.on.doc",
                help: String(localized: "Copy to clipboard"),
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
                    title: String(localized: "Logs could not be loaded"),
                    message: error,
                    actionTitle: String(localized: "Try again"),
                    action: { Task { await model.load() } }
                )
                .padding(16)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.text.isEmpty && model.isLoading {
            ProgressView("Loading logs …")
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
                Text("As of \(loadedAt.formatted(date: .omitted, time: .standard))")
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
        return matches.isEmpty ? String(localized: "No lines contain “\(query)”.") : matches.joined(separator: "\n")
    }

    private var lineSummary: String {
        let total = model.text.isEmpty ? 0 : model.text.split(separator: "\n").count
        let query = filter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return String(localized: "\(total) lines") }
        let shown = model.text.split(separator: "\n").filter { $0.localizedCaseInsensitiveContains(query) }.count
        return String(localized: "\(shown) of \(total) lines")
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
