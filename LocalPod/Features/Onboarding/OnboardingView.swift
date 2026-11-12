import SwiftUI

enum OnboardingStorage {
    /// App-local first-run flag. Deliberately stored in UserDefaults rather
    /// than the SwiftData store so a media/library reset does not replay it.
    static let completedKey = "localpod.onboarding.completed"
}

struct OnboardingView: View {
    let onContinue: () -> Void
    let onGoToImport: () -> Void
    let onSkip: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TapeTheme.space5) {
                hero

                VStack(alignment: .leading, spacing: TapeTheme.space2) {
                    TapeKicker(text: "WHAT'S INSIDE")
                        .padding(.horizontal, TapeTheme.space1)

                    TapeCard {
                        VStack(alignment: .leading, spacing: TapeTheme.space3) {
                            feature(
                                icon: "folder.badge.plus",
                                fill: TapeTheme.coral,
                                title: L10n.string("onboarding.folders.title"),
                                detail: L10n.string("onboarding.folders.detail")
                            )
                            TapeHairline()
                            feature(
                                icon: "waveform",
                                fill: TapeTheme.violetSoft,
                                title: L10n.string("onboarding.audioOnly.title"),
                                detail: L10n.string("onboarding.audioOnly.detail")
                            )
                            TapeHairline()
                            feature(
                                icon: "gift",
                                fill: TapeTheme.acid,
                                title: L10n.string("onboarding.free.title"),
                                detail: L10n.string("onboarding.free.detail")
                            )
                            TapeHairline()
                            feature(
                                icon: "checkmark.seal",
                                fill: TapeTheme.peach,
                                title: L10n.string("onboarding.sideload.title"),
                                detail: L10n.string("onboarding.sideload.detail")
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, TapeTheme.screenPadding)
            .padding(.vertical, TapeTheme.space5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("onboardingScreen")
        }
        .scrollIndicators(.hidden)
        .background(TapeScreenBackground())
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
    }

    // MARK: - Hero

    private var hero: some View {
        TapeCard(fill: TapeTheme.acid) {
            VStack(alignment: .leading, spacing: TapeTheme.space4) {
                HStack(alignment: .center, spacing: TapeTheme.space2) {
                    TapeKicker(
                        text: "SIDE A · LOCALPOD",
                        color: TapeTheme.ink.opacity(0.62)
                    )
                    Spacer(minLength: TapeTheme.space2)
                    TapeSticker(text: "100% LOCAL", fill: TapeTheme.violet, angle: 6)
                }
                .accessibilityHidden(true)

                TapeTapeCover(
                    title: "LocalPod",
                    subtitle: "AUDIO ONLY",
                    durationText: "SIDE A",
                    isPlaying: false,
                    artworkURL: nil,
                    width: dynamicTypeSize.isAccessibilitySize ? 156 : 190
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityHidden(true)

                Text("欢迎使用 LocalPod")
                    .font(TapeType.displayXL)
                    .tracking(-0.8)
                    .foregroundStyle(TapeTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text("把本地音频放进资料库，按合集、播放列表和队列收听。")
                    .font(TapeType.body)
                    .foregroundStyle(TapeTheme.ink.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Feature rows

    private func feature(
        icon: String,
        fill: Color,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: TapeTheme.space3) {
            ZStack {
                RoundedRectangle(cornerRadius: TapeTheme.radiusThumb, style: .continuous)
                    .fill(fill)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TapeTheme.ink)
            }
            .frame(width: 36, height: 36)
            .overlay {
                RoundedRectangle(cornerRadius: TapeTheme.radiusThumb, style: .continuous)
                    .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: TapeTheme.space1) {
                Text(title)
                    .font(TapeType.headline)
                    .foregroundStyle(TapeTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(TapeType.caption)
                    .foregroundStyle(TapeTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Bottom actions

    private var bottomBar: some View {
        VStack(spacing: TapeTheme.space2) {
            Button(action: onContinue) {
                Text("开始使用")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(TapePrimaryButtonStyle())
            .accessibilityIdentifier("onboardingContinueButton")
            .accessibilityHint("关闭引导，进入资料库")

            Button(action: onGoToImport) {
                Text("去导入资料库")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(TapeSecondaryButtonStyle())
            .accessibilityIdentifier("onboardingImportButton")
            .accessibilityHint("关闭引导并打开导入页，文件夹会递归扫描")

            Button(action: onSkip) {
                Text("跳过")
                    .font(TapeType.bodySmall)
                    .foregroundStyle(TapeTheme.muted)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TapePlainPressStyle())
            .accessibilityIdentifier("onboardingSkipButton")
            .accessibilityHint("关闭引导，下次启动不再显示")
        }
        .padding(.horizontal, TapeTheme.screenPadding)
        .padding(.top, TapeTheme.space3)
        .padding(.bottom, TapeTheme.space2)
        .background(TapeTheme.cream)
        .overlay(alignment: .top) { TapeHairline() }
    }
}
