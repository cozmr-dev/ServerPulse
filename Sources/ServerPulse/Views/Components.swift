import AppKit
import SwiftUI

// MARK: - Farben

/// Ampelfarbe je nach Auslastung: grün < 70 %, gelb/orange < 90 %, sonst rot.
func usageColor(_ fraction: Double) -> Color {
    switch fraction {
    case ..<0.7: .green
    case ..<0.9: .orange
    default: .red
    }
}

// MARK: - Karten

private struct CardModifier: ViewModifier {
    var padding: CGFloat
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
            )
    }
}

extension View {
    /// Dezente, abgerundete Karte im Stil der macOS-Widgets.
    func card(padding: CGFloat = 14, cornerRadius: CGFloat = 14) -> some View {
        modifier(CardModifier(padding: padding, cornerRadius: cornerRadius))
    }
}

// MARK: - Icons

/// Farbige, abgerundete Symbol-Kachel wie in den Systemeinstellungen.
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 28

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(shape.fill(color.gradient))
            .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
            .shadow(color: color.opacity(0.25), radius: 1.5, y: 1)
    }
}

/// Farbiger Statuspunkt.
struct StatusDot: View {
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color.gradient)
            .frame(width: size, height: size)
    }
}

/// Kleine Kapsel mit Statuspunkt und Text.
struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            StatusDot(color: color, size: 6)
            Text(text)
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
    }
}

/// Runder Icon-Button wie im Kontrollzentrum.
struct CircleIconButton: View {
    let systemImage: String
    let help: String
    var size: CGFloat = 26
    var tint: Color = .primary
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.primary.opacity(isHovering ? 0.14 : 0.07)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(help)
    }
}

// MARK: - Auslastung

/// Ring-Anzeige für eine Auslastung mit Prozentwert in der Mitte.
struct UsageRing: View {
    let fraction: Double?
    var lineWidth: CGFloat = 7

    var body: some View {
        let value = min(1, max(0, fraction ?? 0))
        let color = usageColor(value)
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction == nil ? 0 : max(0.005, value))
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.7), color],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * max(0.01, value))
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text(fraction.map { Format.percent($0) } ?? "–")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: value))
        }
        .animation(.spring(duration: 0.6), value: value)
        .accessibilityElement(children: .combine)
    }
}

/// Schlanker Fortschrittsbalken mit Ampelfarbe.
struct UsageBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(usageColor(fraction).gradient)
                    .frame(width: max(5, proxy.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 5)
        .animation(.spring(duration: 0.5), value: fraction)
        .accessibilityValue(Format.percent(fraction))
    }
}

// MARK: - Eingaben & Hinweise

/// Suchfeld im macOS-Stil.
struct SearchField: View {
    @Binding var text: String
    var prompt: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12, weight: .medium))
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Suche zurücksetzen")
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}

/// Hinweis-/Fehlerbanner.
struct StatusBanner: View {
    enum Style {
        case error
        case warning
        case info
        case success

        var color: Color {
            switch self {
            case .error: .red
            case .warning: .orange
            case .info: .blue
            case .success: .green
            }
        }

        var symbol: String {
            switch self {
            case .error: "xmark.octagon.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .info: "info.circle.fill"
            case .success: "checkmark.circle.fill"
            }
        }
    }

    let style: Style
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: style.symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(style.color)
                .font(.system(size: 16, weight: .semibold))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .controlSize(.small)
                        .padding(.top, 3)
                }
            }
            Spacer(minLength: 0)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.primary.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .help("Ausblenden")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(style.color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style.color.opacity(0.22), lineWidth: 0.5)
        )
    }
}

/// Schwebende Bestätigung im HUD-Stil.
struct ToastView: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)
                .font(.system(size: 15, weight: .semibold))
            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }
}

/// Kopfbereich einer Einstellungsseite mit großer Symbol-Kachel.
struct PaneHeader<Accessory: View>: View {
    let symbol: String
    let color: Color
    let title: String
    let subtitle: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: symbol, color: color, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 19, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            accessory
        }
        .padding(.vertical, 6)
    }
}

extension PaneHeader where Accessory == EmptyView {
    init(symbol: String, color: Color, title: String, subtitle: String) {
        self.init(symbol: symbol, color: color, title: title, subtitle: subtitle) { EmptyView() }
    }
}
