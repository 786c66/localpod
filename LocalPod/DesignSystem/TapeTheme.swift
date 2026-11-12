import SwiftUI
import UIKit

/// Direction C「节拍 / Expressive」design tokens.
///
/// The source spec is `docs/DESIGN-SPEC.md`; the short version is: cream paper,
/// ink outlines, hard offset shadows, acid-lime action surfaces, coral and
/// violet stickers, Space Grotesk display type and IBM Plex Mono numbers.
enum TapeTheme {
    // MARK: - Palette

    static let cream = Color(hex: 0xFFF3DF)
    static let ink = Color(hex: 0x141414)
    static let muted = Color(hex: 0x6E665A)
    static let faint = Color(hex: 0x9B907E)
    static let acid = Color(hex: 0xD8FF3E)
    static let coral = Color(hex: 0xFF5A36)
    static let violet = Color(hex: 0x6C5CE7)
    static let card = Color.white
    static let track = Color(hex: 0xDFD3BF)
    static let coralSoft = Color(hex: 0xFFB6A5)
    static let violetSoft = Color(hex: 0xC7BEFF)
    static let peach = Color(hex: 0xFFD0C3)
    static let stickerInk = Color(hex: 0xFFF6E6)

    // MARK: - Geometry

    static let stroke: CGFloat = 1.5
    static let hairline: CGFloat = 1
    static let radiusCard: CGFloat = 12
    static let radiusSmall: CGFloat = 8
    static let radiusThumb: CGFloat = 6
    static let radiusSticker: CGFloat = 3

    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 20
    static let space6: CGFloat = 24
    static let space8: CGFloat = 32

    static let screenPadding: CGFloat = 16

    // MARK: - Motion

    /// The single primary curve from the design: 260ms spring.
    static let spring = Animation.spring(response: 0.26, dampingFraction: 0.55)
    /// Button press feedback: a short spring so the shadow-collapse reads as
    /// elastic rather than linear — part of the tape button language.
    static let press = Animation.spring(response: 0.22, dampingFraction: 0.6)
    static let pop = Animation.spring(response: 0.34, dampingFraction: 0.5)

    // MARK: - Haptics

    @MainActor
    static func tapHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @MainActor
    static func successHaptic() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    @MainActor
    static func softHaptic() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Space Grotesk for display/UI, IBM Plex Mono for numeric/technical text.
/// Both are bundled (SIL OFL); the Chinese fallback stays PingFang SC.
enum TapeFont {
    static func display(
        _ size: CGFloat,
        weight: Font.Weight = .bold,
        relativeTo style: Font.TextStyle = .body
    ) -> Font {
        .custom(displayName(for: weight), size: size, relativeTo: style)
    }

    static func mono(
        _ size: CGFloat,
        weight: Font.Weight = .medium,
        relativeTo style: Font.TextStyle = .body
    ) -> Font {
        let name: String
        switch weight {
        case .semibold, .bold, .heavy, .black:
            name = "IBMPlexMono-SemiBold"
        case .medium:
            name = "IBMPlexMono-Medium"
        default:
            name = "IBMPlexMono-Regular"
        }
        return .custom(name, size: size, relativeTo: style)
    }

    private static func displayName(for weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black, .semibold:
            "SpaceGrotesk-Bold"
        case .medium:
            "SpaceGrotesk-Medium"
        default:
            "SpaceGrotesk-Regular"
        }
    }
}

/// Typographic roles used across screens. Keep the scale in one place so a new
/// view cannot invent a seventh size by accident.
enum TapeType {
    static let displayXL = TapeFont.display(40, weight: .bold, relativeTo: .largeTitle)
    static let display = TapeFont.display(34, weight: .bold, relativeTo: .largeTitle)
    static let title1 = TapeFont.display(28, weight: .bold, relativeTo: .title)
    static let title2 = TapeFont.display(22, weight: .bold, relativeTo: .title2)
    static let title3 = TapeFont.display(19, weight: .bold, relativeTo: .title3)
    static let headline = TapeFont.display(17, weight: .semibold, relativeTo: .headline)
    static let body = TapeFont.display(15, weight: .regular, relativeTo: .body)
    static let bodySmall = TapeFont.display(14, weight: .regular, relativeTo: .subheadline)
    static let caption = TapeFont.display(13, weight: .regular, relativeTo: .caption)
    static let captionSmall = TapeFont.display(12, weight: .regular, relativeTo: .caption2)
    static let kicker = TapeFont.mono(11, weight: .medium, relativeTo: .caption2)
    static let monoMeta = TapeFont.mono(12, weight: .medium, relativeTo: .caption)
    static let monoTime = TapeFont.mono(12, weight: .medium, relativeTo: .caption)
    static let monoMicro = TapeFont.mono(10.5, weight: .medium, relativeTo: .caption2)
    static let sticker = TapeFont.display(12, weight: .bold, relativeTo: .caption)
    static let tab = TapeFont.display(10, weight: .semibold, relativeTo: .caption2)
    static let button = TapeFont.display(16, weight: .bold, relativeTo: .body)
}
