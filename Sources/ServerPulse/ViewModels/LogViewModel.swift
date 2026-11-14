import Foundation
import Observation

/// Lädt die Logs eines Containers für das Log-Fenster.
@MainActor
@Observable
final class LogViewModel {
    let host: ServerHost
    let container: DockerContainer

    var lineCount = 100
    private(set) var text = ""
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var loadedAt: Date?

    @ObservationIgnored private let service: SSHService

    init(host: ServerHost, container: DockerContainer, service: SSHService) {
        self.host = host
        self.container = container
        self.service = service
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let logs = Self.stripANSI(try await service.fetchLogs(container.id, lines: lineCount, on: host))
            text = logs.isEmpty ? String(localized: "(No log output)") : logs
            loadedAt = Date()
        } catch {
            let suggestion = (error as? SSHError)?.recoverySuggestion.map { "\n\($0)" } ?? ""
            errorMessage = error.localizedDescription + suggestion
        }
        isLoading = false
    }

    /// Entfernt ANSI-Farb- und Steuersequenzen (z. B. `ESC[36m`), die viele Container in ihre Logs schreiben.
    nonisolated static func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(
            of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]",
            with: "",
            options: .regularExpression
        )
    }
}
