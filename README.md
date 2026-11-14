# ServerPulse

Native macOS-Menüleisten-App (macOS 14+, Swift 6, SwiftUI, keine Abhängigkeiten) zur Überwachung von Linux-/UGREEN-NAS-Systemen und ihren Docker-Containern per SSH.

## Bauen & Starten

```bash
./build.sh                    # Release-Build + build/ServerPulse.app (ad-hoc signiert)
open build/ServerPulse.app
```

Zum Entwickeln: `swift run` (Info.plist mit `LSUIElement` ist ins Binary eingebettet, daher auch dann kein Dock-Icon).

## Voraussetzungen auf dem Server

- SSH-Login per Key (Passwort-Login wird bewusst nicht unterstützt, `BatchMode=yes`):
  `ssh-copy-id -i ~/.ssh/id_ed25519.pub user@nas`
- Passwortgeschützte Keys einmalig in den Agent laden: `ssh-add --apple-use-keychain ~/.ssh/id_ed25519`
- Für Docker ohne `sudo`: `sudo usermod -aG docker <user>` (danach neu anmelden)

## Struktur

```
Sources/ServerPulse/
  App/         ServerPulseApp (MenuBarExtra, .window-Style)
  Models/      ServerHost, RefreshInterval, SystemStats, DockerContainer, HostSnapshot
  Services/    HostStore (UserDefaults/JSON), SSHService, ProcessRunner, RemoteScripts, StatusParser, SSHError
  ViewModels/  MonitorViewModel (Auto-Refresh, Aktionen), LogViewModel
  Views/       Popover, System-Kacheln, Container-Liste, Log-Fenster, Einstellungen
```
