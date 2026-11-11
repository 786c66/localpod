import SwiftUI

// MARK: - Paper background

/// Cream paper with a sparse ink dot grid. Kept deliberately quiet so the
/// cards and stickers carry the personality.
struct TapeScreenBackground: View {
    var body: some View {
        ZStack {
            TapeTheme.cream
            Canvas { context, size in
                let step: CGFloat = 28
                let dot = Path(ellipseIn: CGRect(x: 0, y: 0, width: 2, height: 2))
                var x: CGFloat = 14
                while x < size.width {
                    var y: CGFloat = 14
                    while y < size.height {
                        context.fill(
                            dot.offsetBy(dx: x, dy: y),
                            with: .color(TapeTheme.ink.opacity(0.055))
                        )
                        y += step
                    }
                    x += step
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Cards

struct TapeCard<Content: View>: View {
    var fill: Color = TapeTheme.card
    var rotation: Double = 0
    var padding: CGFloat = TapeTheme.space4
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                fill,
                in: RoundedRectangle(cornerRadius: TapeTheme.radiusCard, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: TapeTheme.radiusCard, style: .continuous)
                    .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
            }
            .shadow(color: TapeTheme.ink, radius: 0, x: 4, y: 4)
            .rotationEffect(.degrees(rotation))
    }
}

/// A dashed card for empty states and "add something" affordances.
struct TapeDashedCard<Content: View>: View {
    var padding: CGFloat = TapeTheme.space5
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity)
            .background(
                TapeTheme.cream.opacity(0.6),
                in: RoundedRectangle(cornerRadius: TapeTheme.radiusCard, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: TapeTheme.radiusCard, style: .continuous)
                    .strokeBorder(
                        TapeTheme.ink.opacity(0.55),
                        style: StrokeStyle(lineWidth: TapeTheme.stroke, dash: [6, 4])
                    )
            }
    }
}

// MARK: - Buttons

/// Primary action: acid block, ink text, hard shadow, physical press.
struct TapePrimaryButtonStyle: ButtonStyle {
    var fill: Color = TapeTheme.acid
    var foreground: Color = TapeTheme.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TapeType.button)
            .foregroundStyle(foreground)
            .multilineTextAlignment(.center)
            .padding(.horizontal, TapeTheme.space4)
            .padding(.vertical, TapeTheme.space3)
            .frame(minHeight: 44)
            .background(fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
            }
            .shadow(
                color: TapeTheme.ink,
                radius: 0,
                x: configuration.isPressed ? 1 : 4,
                y: configuration.isPressed ? 1 : 4
            )
            .offset(
                x: configuration.isPressed ? 3 : 0,
                y: configuration.isPressed ? 3 : 0
            )
            .animation(TapeTheme.press, value: configuration.isPressed)
    }
}

struct TapeSecondaryButtonStyle: ButtonStyle {
    var fill: Color = TapeTheme.card
    var foreground: Color = TapeTheme.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TapeType.button)
            .foregroundStyle(foreground)
            .multilineTextAlignment(.center)
            .padding(.horizontal, TapeTheme.space4)
            .padding(.vertical, TapeTheme.space3)
            .frame(minHeight: 44)
            .background(fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
            }
            .shadow(
                color: TapeTheme.ink,
                radius: 0,
                x: configuration.isPressed ? 1 : 2,
                y: configuration.isPressed ? 1 : 2
            )
            .offset(
                x: configuration.isPressed ? 1 : 0,
                y: configuration.isPressed ? 1 : 0
            )
            .animation(TapeTheme.press, value: configuration.isPressed)
    }
}

struct TapeDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TapeType.button)
            .foregroundStyle(TapeTheme.stickerInk)
            .multilineTextAlignment(.center)
            .padding(.horizontal, TapeTheme.space4)
            .padding(.vertical, TapeTheme.space3)
            .frame(minHeight: 44)
            .background(TapeTheme.coral, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
            }
            .shadow(
                color: TapeTheme.ink,
                radius: 0,
                x: configuration.isPressed ? 1 : 3,
                y: configuration.isPressed ? 1 : 3
            )
            .offset(
                x: configuration.isPressed ? 2 : 0,
                y: configuration.isPressed ? 2 : 0
            )
            .animation(TapeTheme.press, value: configuration.isPressed)
    }
}

/// Round icon control used for transport, trailing row actions and toolbars.
struct TapeIconButtonStyle: ButtonStyle {
    var diameter: CGFloat = 36
    var fill: Color = TapeTheme.card
    var foreground: Color = TapeTheme.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: diameter * 0.42, weight: .bold))
            .foregroundStyle(foreground)
            .frame(width: diameter, height: diameter)
            .background(fill, in: Circle())
            .overlay { Circle().strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke) }
            .shadow(
                color: TapeTheme.ink,
                radius: 0,
                x: configuration.isPressed ? 0.5 : 2,
                y: configuration.isPressed ? 0.5 : 2
            )
            .offset(
                x: configuration.isPressed ? 1.5 : 0,
                y: configuration.isPressed ? 1.5 : 0
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(TapeTheme.press, value: configuration.isPressed)
    }
}

/// For rows/tiles whose surface is drawn by the content itself: only the
/// physical press feel is added here.
struct TapePlainPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(TapeTheme.press, value: configuration.isPressed)
    }
}

// MARK: - Stickers and chips

struct TapeSticker: View {
    let text: String
    var fill: Color = TapeTheme.coral
    var foreground: Color = TapeTheme.stickerInk
    var angle: Double = 6

    var body: some View {
        Text(text)
            .font(TapeType.sticker)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(fill, in: RoundedRectangle(cornerRadius: TapeTheme.radiusSticker))
            .overlay {
                RoundedRectangle(cornerRadius: TapeTheme.radiusSticker)
                    .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
            }
            .shadow(color: TapeTheme.ink, radius: 0, x: 2, y: 2)
            .rotationEffect(.degrees(angle))
    }
}

/// Sticker with the "pop and wobble" reward motion. It animates once on
/// appearance and again when `pulse` changes.
struct TapeRewardSticker: View {
    let text: String
    var fill: Color = TapeTheme.acid
    var foreground: Color = TapeTheme.ink
    var pulse: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        TapeSticker(text: text, fill: fill, foreground: foreground)
            .scaleEffect(appeared ? 1 : 0.6)
            .rotationEffect(.degrees(appeared ? 0 : -8))
            .onAppear {
                guard !reduceMotion else {
                    appeared = true
                    return
                }
                withAnimation(TapeTheme.pop) { appeared = true }
            }
            .onChange(of: pulse) { _, _ in
                guard !reduceMotion else { return }
                withAnimation(TapeTheme.pop) { appeared = false }
                withAnimation(TapeTheme.pop.delay(0.05)) { appeared = true }
            }
    }
}

struct TapeChip: View {
    let text: String
    var isSelected = false
    var fill: Color = TapeTheme.cream
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button {
                    TapeTheme.tapHaptic()
                    action()
                } label: {
                    label
                }
                .buttonStyle(TapePlainPressStyle())
                .accessibilityAddTraits(isSelected ? .isSelected : AccessibilityTraits())
            } else {
                label
            }
        }
    }

    private var label: some View {
        Text(text)
            .font(TapeFont.display(13, weight: .semibold, relativeTo: .caption))
            .foregroundStyle(TapeTheme.ink)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(minHeight: 32)
            .background(
                isSelected ? TapeTheme.acid : fill,
                in: Capsule()
            )
            .overlay { Capsule().strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke) }
            .shadow(
                color: TapeTheme.ink,
                radius: 0,
                x: isSelected ? 2 : 0,
                y: isSelected ? 2 : 0
            )
    }
}

/// Two-state chip used where the old UI had a segmented picker. The labels are
/// plain buttons so existing UI tests can keep tapping "条目"/"合集".
struct TapeSegmentOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var id: Value { value }
}

struct TapeSegmentedChips<Value: Hashable>: View {
    let options: [TapeSegmentOption<Value>]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: TapeTheme.space2) {
            ForEach(options) { option in
                TapeChip(text: option.title, isSelected: selection == option.value) {
                    withAnimation(TapeTheme.spring) { selection = option.value }
                }
                .accessibilityLabel(option.title)
            }
        }
    }
}

// MARK: - Section headers and text

struct TapeKicker: View {
    let text: String
    var color: Color = TapeTheme.faint

    var body: some View {
        Text(text.uppercased())
            .font(TapeType.kicker)
            .tracking(1.4)
            .foregroundStyle(color)
    }
}

struct TapeSectionHeader: View {
    let title: String
    var kicker: String?
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TapeTheme.space2) {
            VStack(alignment: .leading, spacing: 2) {
                if let kicker {
                    TapeKicker(text: kicker)
                }
                Text(title)
                    .font(TapeType.title3)
                    .tracking(-0.3)
                    .foregroundStyle(TapeTheme.ink)
            }
            Spacer(minLength: TapeTheme.space2)
            if let trailing {
                Text(trailing)
                    .font(TapeType.monoMeta)
                    .foregroundStyle(TapeTheme.faint)
            }
        }
    }
}

struct TapeMonoLabel: View {
    let text: String
    var color: Color = TapeTheme.faint

    var body: some View {
        Text(text)
            .font(TapeType.monoMeta)
            .foregroundStyle(color)
    }
}

// MARK: - Progress

struct TapeProgressBar: View {
    var progress: Double
    var fill: Color = TapeTheme.acid
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(progress, 0), 1)
            let width = proxy.size.width * clamped
            ZStack(alignment: .leading) {
                Capsule().fill(TapeTheme.cream)
                if width > 0 {
                    Capsule()
                        .fill(fill)
                        .frame(width: max(width, height))
                        .overlay(alignment: .trailing) {
                            Rectangle()
                                .fill(TapeTheme.ink)
                                .frame(width: TapeTheme.stroke)
                        }
                        .clipShape(Capsule())
                }
            }
            .overlay { Capsule().strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke) }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Toggle

struct TapeToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: TapeTheme.space3) {
            configuration.label
                .font(TapeType.body)
                .foregroundStyle(TapeTheme.ink)
            Spacer(minLength: TapeTheme.space2)
            Button {
                TapeTheme.tapHaptic()
                withAnimation(TapeTheme.spring) { configuration.isOn.toggle() }
            } label: {
                Capsule()
                    .fill(configuration.isOn ? TapeTheme.acid : TapeTheme.cream)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(TapeTheme.card)
                            .overlay { Circle().strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke) }
                            .padding(3)
                    }
                    .overlay { Capsule().strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke) }
                    .frame(width: 52, height: 32)
                    .shadow(color: TapeTheme.ink, radius: 0, x: 2, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isOn ? "1" : "0")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            TapeTheme.tapHaptic()
            withAnimation(TapeTheme.spring) { configuration.isOn.toggle() }
        }
    }
}

// MARK: - Empty state

struct TapeEmptyState: View {
    let sticker: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: TapeTheme.space3) {
            TapeRewardSticker(text: sticker, fill: TapeTheme.violet, foreground: TapeTheme.stickerInk)
            Text(title)
                .font(TapeType.title2)
                .tracking(-0.4)
                .foregroundStyle(TapeTheme.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(TapeType.body)
                .foregroundStyle(TapeTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(TapePrimaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TapeTheme.space5)
    }
}

// MARK: - Rows

/// Standard tape row: colored thumb, title + mono subtitle, trailing circle.
struct TapeRow: View {
    var thumbText: String = "A"
    var thumbFill: Color = TapeTheme.coral
    var icon: String?
    let title: String
    let subtitle: String
    var trailingIcon: String = "play.fill"
    var showsTrailing = true

    var body: some View {
        HStack(spacing: TapeTheme.space3) {
            ZStack {
                RoundedRectangle(cornerRadius: TapeTheme.radiusThumb, style: .continuous)
                    .fill(thumbFill)
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TapeTheme.ink)
                } else {
                    Text(thumbText)
                        .font(TapeFont.display(17, weight: .bold, relativeTo: .headline))
                        .foregroundStyle(TapeTheme.stickerInk)
                }
            }
            .frame(width: 36, height: 36)
            .overlay {
                RoundedRectangle(cornerRadius: TapeTheme.radiusThumb, style: .continuous)
                    .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(TapeType.headline)
                    .foregroundStyle(TapeTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(TapeType.monoMicro)
                    .foregroundStyle(TapeTheme.faint)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: TapeTheme.space2)

            if showsTrailing {
                Image(systemName: trailingIcon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(TapeTheme.ink)
                    .frame(width: 28, height: 28)
                    .background(TapeTheme.cream, in: Circle())
                    .overlay { Circle().strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke) }
            }
        }
        .padding(.horizontal, TapeTheme.space3)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .background(
            TapeTheme.card,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
        }
        .shadow(color: TapeTheme.ink, radius: 0, x: 2, y: 2)
    }
}

/// Hairline used between plain (non-card) rows.
struct TapeHairline: View {
    var body: some View {
        Rectangle()
            .fill(TapeTheme.ink.opacity(0.24))
            .frame(height: TapeTheme.hairline)
    }
}

// MARK: - List helpers

extension View {
    /// Cream canvas + clear list background, used by every List/Form screen.
    func tapeScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(TapeScreenBackground())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listSectionSpacing(TapeTheme.space3)
    }

    /// Clear, zero-inset list row so the content card owns its own margins.
    func tapeRowInsets(_ vertical: CGFloat = 4) -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(
                EdgeInsets(
                    top: vertical,
                    leading: TapeTheme.screenPadding,
                    bottom: vertical,
                    trailing: TapeTheme.screenPadding
                )
            )
    }

    /// Applies the shared primary card treatment without using TapeCard
    /// (for rows that already manage their own padding).
    func tapeCardSurface(fill: Color = TapeTheme.card, corner: CGFloat = TapeTheme.radiusCard) -> some View {
        self
            .background(fill, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
            }
            .shadow(color: TapeTheme.ink, radius: 0, x: 4, y: 4)
    }
}
