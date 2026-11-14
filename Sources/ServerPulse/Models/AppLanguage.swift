import Foundation

/// Sprache, in der die App gerade läuft (richtet sich nach den Systemeinstellungen).
/// Quelltexte sind Englisch, Übersetzungen liegen in `Resources/<sprache>.lproj/Localizable.strings`.
enum AppLanguage {
    static var code: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    static var isGerman: Bool {
        code.hasPrefix("de")
    }

    /// App-Sprache kombiniert mit der Region des Systems: Wörter folgen der App-Sprache,
    /// Zahlen- und Datumsformate der Region (wie in allen Mac-Apps).
    static var locale: Locale {
        guard let region = Locale.current.region?.identifier else { return Locale(identifier: code) }
        return Locale(identifier: "\(code)_\(region)")
    }
}
