import SwiftUI

/// The cassette that anchors the playback screen: coral shell, cream window,
/// two spinning reels and an acid title strip. It is the signature object of
/// Direction C — everything else is built around it.
struct TapeTapeCover: View {
    let title: String
    let subtitle: String
    let durationText: String
    let isPlaying: Bool
    var artworkURL: URL?
    var width: CGFloat = 236

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var artwork: UIImage?
    @State private var accumulatedAngle: Double = 0
    @State private var spinStart: Date?

    private var reelSize: CGFloat { width * 0.2 }
    private var windowHeight: CGFloat { width * 0.38 }

    var body: some View {
        VStack(spacing: 10) {
            header
            window
            labelStrip
        }
        .padding(12)
        .frame(width: width)
        .background {
            RoundedRectangle(cornerRadius: TapeTheme.radiusCard, style: .continuous)
                .fill(TapeTheme.coral)
                .shadow(color: TapeTheme.ink, radius: 0, x: 5, y: 5)
        }
        .overlay {
            RoundedRectangle(cornerRadius: TapeTheme.radiusCard, style: .continuous)
                .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
        }
        .overlay(alignment: .topLeading) { screw }
        .overlay(alignment: .topTrailing) { screw }
        .overlay(alignment: .bottomLeading) { screw }
        .overlay(alignment: .bottomTrailing) { screw }
        .task(id: artworkURL) {
            guard let artworkURL else {
                artwork = nil
                return
            }
            artwork = UIImage(contentsOfFile: artworkURL.path)
        }
        .onAppear {
            if isPlaying { spinStart = Date() }
        }
        .onChange(of: isPlaying) { _, playing in
            accumulatedAngle = angle(at: Date())
            spinStart = playing ? Date() : nil
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 6) {
            Text("TAPE SESSIONS")
                .font(TapeType.monoMicro)
                .tracking(0.8)
            Spacer(minLength: 4)
            Text("SIDE A · 042")
                .font(TapeType.monoMicro)
                .tracking(0.8)
        }
        .foregroundStyle(TapeTheme.stickerInk.opacity(0.92))
        .padding(.horizontal, 2)
    }

    private var window: some View {
        ZStack {
            RoundedRectangle(cornerRadius: TapeTheme.radiusThumb, style: .continuous)
                .fill(TapeTheme.cream)

            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width - 24, height: windowHeight)
                    .clipped()
                    .opacity(0.35)
            }

            // Tape band linking the two reels.
            Rectangle()
                .fill(TapeTheme.ink.opacity(0.16))
                .frame(height: reelSize * 0.34)

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying || reduceMotion)) { context in
                let angle = angle(at: context.date)
                HStack(spacing: width * 0.13) {
                    TapeReel(size: reelSize, angle: angle, accent: TapeTheme.acid)
                    TapeReel(size: reelSize, angle: angle * 0.92, accent: TapeTheme.acid)
                }
            }
        }
        .frame(height: windowHeight)
        .clipShape(RoundedRectangle(cornerRadius: TapeTheme.radiusThumb, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TapeTheme.radiusThumb, style: .continuous)
                .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
        }
    }

    private var labelStrip: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(TapeFont.display(15, weight: .bold, relativeTo: .headline))
                    .foregroundStyle(TapeTheme.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(TapeType.monoMicro)
                    .foregroundStyle(TapeTheme.ink.opacity(0.72))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text("A")
                    .font(TapeFont.display(18, weight: .bold, relativeTo: .title3))
                    .foregroundStyle(TapeTheme.ink)
                Text(durationText)
                    .font(TapeType.monoMicro)
                    .foregroundStyle(TapeTheme.ink.opacity(0.72))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TapeTheme.acid, in: RoundedRectangle(cornerRadius: TapeTheme.radiusThumb, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TapeTheme.radiusThumb, style: .continuous)
                .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
        }
    }

    private var screw: some View {
        Circle()
            .fill(TapeTheme.stickerInk.opacity(0.55))
            .frame(width: 4, height: 4)
            .overlay(Circle().strokeBorder(TapeTheme.ink.opacity(0.4), lineWidth: 0.5))
            .padding(6)
    }

    // MARK: - Reel math

    /// 0.6 revolutions per second, paused by freezing the accumulated angle.
    private func angle(at date: Date) -> Double {
        guard isPlaying, !reduceMotion, let spinStart else {
            return accumulatedAngle
        }
        return accumulatedAngle + date.timeIntervalSince(spinStart) * 216
    }
}

private struct TapeReel: View {
    let size: CGFloat
    let angle: Double
    let accent: Color

    var body: some View {
        ZStack {
            Circle().fill(TapeTheme.cream)
            Circle().strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
            Circle()
                .strokeBorder(TapeTheme.ink.opacity(0.45), lineWidth: 1)
                .padding(size * 0.16)

            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(TapeTheme.ink)
                    .frame(width: size * 0.07, height: size * 0.36)
                    .offset(y: -size * 0.12)
                    .rotationEffect(.degrees(Double(index) * 120))
            }

            Circle()
                .fill(accent)
                .frame(width: size * 0.3, height: size * 0.3)
                .overlay(Circle().strokeBorder(TapeTheme.ink, lineWidth: 1.5))
            Circle()
                .fill(TapeTheme.ink)
                .frame(width: size * 0.09, height: size * 0.09)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(angle))
    }
}
