# Projekt: ServerPulse (Native macOS Menüleisten-App für NAS & Docker)

## Ziel & Architektur
- **App-Typ:** Reine macOS Menüleisten-App (`MenuBarExtra` mit `.window` Style), kein Dock-Icon (`LSUIElement = true`).
- **Sprache & Frameworks:** Swift 6 (Strict Concurrency aktiv beachten: `Sendable`, `@MainActor`, `async/await`), SwiftUI (Ziel: macOS 14.0+ Sonoma/Sequoia).
- **Zero Dependencies:** Nutze ausschließlich native Apple-Frameworks (`SwiftUI`, `Foundation`, `Observation` mit `@Observable`). Keine externen Swift Packages.
- **Architektur:** Saubere Trennung in `Models/`, `Services/`, `ViewModels/` und `Views/`.

## Technische Leitplanken
- **SSH-Ausführung:** Nutze `/usr/bin/ssh` über `Process` (asynchron, non-blocking). Immer mit `-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new`, damit der Prozess niemals auf interaktive Passwort-Prompts wartet und einfriert.
- **Fehlerbehandlung:** Verbindungsabbrüche, Timeouts oder fehlende Docker-Berechtigungen dürfen die App niemals zum Absturz bringen, sondern müssen als sauberer Status-Banner in der UI erscheinen.
- **Build-Verifikation:** Nach jeder Code-Änderung musst du das Projekt selbstständig per Terminal (`swift build` oder `xcodebuild`) kompilieren und alle Compiler-Warnings sowie Fehler restlos beheben, bevor du dich zurückmeldest.
