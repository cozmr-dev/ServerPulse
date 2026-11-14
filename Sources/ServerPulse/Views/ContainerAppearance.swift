import SwiftUI

/// Wählt anhand von Name und Image ein passendes SF-Symbol und eine Farbe für einen Container.
struct ContainerAppearance {
    let symbol: String
    let color: Color

    private struct Rule {
        let keywords: [String]
        let appearance: ContainerAppearance
    }

    static func resolve(for container: DockerContainer) -> ContainerAppearance {
        match("\(container.name) \(container.image)") ?? fallbackAppearance
    }

    /// Für Projekte: erst den Projektnamen prüfen, sonst das Icon des ersten Containers verwenden.
    static func resolve(key: String, fallback: DockerContainer?) -> ContainerAppearance {
        if let match = match(key) { return match }
        if let fallback { return resolve(for: fallback) }
        return fallbackAppearance
    }

    private static let fallbackAppearance = ContainerAppearance(symbol: "shippingbox.fill", color: .blue)

    private static func match(_ text: String) -> ContainerAppearance? {
        let key = text.lowercased()
        guard !key.isEmpty else { return nil }
        return rules.first { rule in rule.keywords.contains { key.contains($0) } }?.appearance
    }

    // Reihenfolge ist wichtig: Datenbanken, Caches und Worker vor dem eigentlichen App-Namen.
    private static let rules: [Rule] = [
        Rule(keywords: ["machine_learning", "machine-learning"],
             appearance: .init(symbol: "brain", color: .purple)),
        Rule(keywords: ["postgres", "mariadb", "mysql", "mongo", "-db", "_db", "database", "sqlite", "pgvecto"],
             appearance: .init(symbol: "cylinder.split.1x2.fill", color: .indigo)),
        Rule(keywords: ["redis", "valkey", "memcached", "dragonfly", "keydb"],
             appearance: .init(symbol: "bolt.fill", color: .red)),
        Rule(keywords: ["sidekiq", "cron", "worker", "celery", "queue", "scheduler"],
             appearance: .init(symbol: "gearshape.2.fill", color: .gray)),
        Rule(keywords: ["immich", "photoprism", "librephotos", "photo"],
             appearance: .init(symbol: "photo.on.rectangle.angled", color: .pink)),
        Rule(keywords: ["jellyfin", "plex", "emby", "kodi"],
             appearance: .init(symbol: "play.tv.fill", color: .purple)),
        Rule(keywords: ["audiobookshelf", "podcast", "navidrome", "music"],
             appearance: .init(symbol: "headphones", color: .orange)),
        Rule(keywords: ["kavita", "komga", "calibre", "book"],
             appearance: .init(symbol: "books.vertical.fill", color: .brown)),
        Rule(keywords: ["nextcloud", "owncloud", "seafile", "syncthing"],
             appearance: .init(symbol: "cloud.fill", color: .blue)),
        Rule(keywords: ["tailscale", "wireguard", "zerotier", "vpn", "headscale"],
             appearance: .init(symbol: "point.3.connected.trianglepath.dotted", color: .teal)),
        Rule(keywords: ["cloudflared", "dockflare", "tunnel", "ngrok"],
             appearance: .init(symbol: "network", color: .orange)),
        Rule(keywords: ["adguard", "pihole", "pi-hole", "blocky", "technitium"],
             appearance: .init(symbol: "shield.lefthalf.filled", color: .green)),
        Rule(keywords: ["vaultwarden", "bitwarden", "passbolt", "keepass"],
             appearance: .init(symbol: "key.fill", color: .indigo)),
        Rule(keywords: ["pocket-id", "authelia", "authentik", "keycloak", "oauth", "lldap"],
             appearance: .init(symbol: "person.badge.key.fill", color: .cyan)),
        Rule(keywords: ["uptime-kuma", "uptime", "gatus", "healthcheck", "statping"],
             appearance: .init(symbol: "waveform.path.ecg", color: .green)),
        Rule(keywords: ["watchtower", "diun", "whatsupdocker", "wud"],
             appearance: .init(symbol: "arrow.triangle.2.circlepath", color: .teal)),
        Rule(keywords: ["portainer", "dockge", "yacht", "komodo"],
             appearance: .init(symbol: "shippingbox.fill", color: .cyan)),
        Rule(keywords: ["socket-proxy", "traefik", "nginx", "caddy", "haproxy", "proxy"],
             appearance: .init(symbol: "arrow.left.arrow.right", color: .mint)),
        Rule(keywords: ["home-assistant", "homeassistant", "hass", "zigbee", "mosquitto"],
             appearance: .init(symbol: "house.fill", color: .blue)),
        Rule(keywords: ["dawarich", "owntracks", "traccar"],
             appearance: .init(symbol: "map.fill", color: .green)),
        Rule(keywords: ["grafana", "prometheus", "influx", "netdata", "glances"],
             appearance: .init(symbol: "chart.xyaxis.line", color: .orange)),
        Rule(keywords: ["paperless", "docs", "stirling"],
             appearance: .init(symbol: "doc.text.fill", color: .green)),
        Rule(keywords: ["gitea", "forgejo", "gitlab"],
             appearance: .init(symbol: "chevron.left.forwardslash.chevron.right", color: .orange))
    ]
}

/// Container-Icon mit Status-Badge unten rechts.
struct ContainerIconView: View {
    let container: DockerContainer
    var size: CGFloat = 30

    var body: some View {
        let appearance = ContainerAppearance.resolve(for: container)
        IconTile(symbol: appearance.symbol, color: appearance.color, size: size)
            .saturation(container.isRunning ? 1 : 0.15)
            .opacity(container.isRunning ? 1 : 0.75)
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(container.stateColor)
                    .frame(width: size * 0.33, height: size * 0.33)
                    .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                    .offset(x: 3, y: 3)
            }
    }
}

extension DockerContainer {
    /// Grün = läuft, Rot = beendet/defekt, Orange = neustartend/pausiert/unhealthy.
    var stateColor: Color {
        switch state {
        case "running": health == .unhealthy ? .orange : .green
        case "exited", "dead": needsAttention ? .red : Color(nsColor: .systemRed).opacity(0.75)
        case "restarting", "paused": .orange
        default: .gray
        }
    }
}
