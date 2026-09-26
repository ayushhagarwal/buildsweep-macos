import SwiftUI

enum BuildSweepTheme {
    static let canvas = Color.srgb(0xF7F9FC)
    static let surface = Color.srgb(0xFFFFFF)
    static let surfaceEmphasized = Color.srgb(0xEAF3FF)
    static let border = Color.srgb(0xDCE5EF)
    static let borderStrong = Color.srgb(0xB8C9DD)
    static let accent = Color.srgb(0x356DB3)
    static let accentSoft = Color.srgb(0xDCEBFF)
    static let hoverFill = Color.srgb(0xEFF4FA)

    static let safe = Color.green
    static let caution = Color.orange
    static let important = Color.red

    static func categoryFill(for category: StorageCategoryID) -> Color {
        switch category {
        case .overview: Color.srgb(0xDCEBFF)
        case .derivedData: Color.srgb(0xA8CBF4)
        case .archives: Color.srgb(0xB5DFEF)
        case .deviceSupport: Color.srgb(0xCCE7F8)
        case .simulators: Color.srgb(0xBDCFF0)
        case .cachesAndLogs: Color.srgb(0x9EBCE5)
        case .aiTools: Color.srgb(0xB9DCE8)
        case .developerCaches: Color.srgb(0xD9C7F2)
        case .history: Color.srgb(0xE8EDF3)
        }
    }

    static func categoryForeground(for category: StorageCategoryID) -> Color {
        category == .history ? Color.secondary : accent
    }

    static var snappy: Animation { .spring(response: 0.42, dampingFraction: 0.86) }
    static var gentle: Animation { .easeInOut(duration: 0.45) }

    static func animation(_ reduceMotion: Bool, _ fallback: Animation = snappy) -> Animation? {
        reduceMotion ? nil : fallback
    }
}

extension Color {
    static func srgb(_ hex: UInt32) -> Color {
        Color(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension View {
    func buildSweepAppearance() -> some View {
        preferredColorScheme(.light)
            .tint(BuildSweepTheme.accent)
    }
}

struct AppBackground: View {
    var body: some View {
        BuildSweepTheme.canvas
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

struct SurfaceCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    var emphasized = false
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(
                emphasized ? BuildSweepTheme.surfaceEmphasized : BuildSweepTheme.surface,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            }
            .shadow(
                color: emphasized ? Color.black.opacity(0.04) : .clear,
                radius: emphasized ? 8 : 0,
                y: emphasized ? 2 : 0
            )
    }

    private var strokeColor: Color {
        if contrast == .increased {
            return emphasized ? Color.primary.opacity(0.45) : Color.primary.opacity(0.28)
        }
        return emphasized ? BuildSweepTheme.borderStrong : BuildSweepTheme.border
    }
}

extension View {
    func surfaceCard(cornerRadius: CGFloat = 16, emphasized: Bool = false) -> some View {
        modifier(SurfaceCardModifier(cornerRadius: cornerRadius, emphasized: emphasized))
    }
}

struct IconTile: View {
    let systemImage: String
    var tint: Color = BuildSweepTheme.accent
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                tint.opacity(0.16),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
    }
}

struct InfoChip: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .surfaceCard(cornerRadius: 20)
    }
}

struct RiskBadge: View {
    let risk: StorageRisk

    private var color: Color {
        switch risk {
        case .regenerates: BuildSweepTheme.safe
        case .redownloads: .blue
        case .reviewFirst: BuildSweepTheme.caution
        case .important: BuildSweepTheme.important
        case .inspectionOnly: .secondary
        }
    }

    var body: some View {
        Text(risk.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityLabel("Risk: \(risk.title)")
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    var emphasized = false
    var tint: Color = BuildSweepTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                IconTile(systemImage: systemImage, tint: tint, size: 32)
                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(emphasized ? BuildSweepTheme.accent : Color.primary)
                .contentTransition(.numericText())
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .surfaceCard(emphasized: emphasized)
    }
}
