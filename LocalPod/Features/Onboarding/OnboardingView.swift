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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero

                VStack(alignment: .leading, spacing: 18) {
                    feature(
                        icon: "folder.badge.plus",
                        title: L10n.string("onboarding.folders.title"),
                        detail: L10n.string("onboarding.folders.detail")
                    )
                    feature(
                        icon: "waveform",
                        title: L10n.string("onboarding.audioOnly.title"),
                        detail: L10n.string("onboarding.audioOnly.detail")
                    )
                    feature(
                        icon: "gift",
                        title: L10n.string("onboarding.free.title"),
                        detail: L10n.string("onboarding.free.detail")
                    )
                    feature(
                        icon: "checkmark.seal",
                        title: L10n.string("onboarding.sideload.title"),
                        detail: L10n.string("onboarding.sideload.detail")
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("onboardingScreen")
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button(action: onContinue) {
                    Text("开始使用")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("onboardingContinueButton")
                .accessibilityHint("关闭引导，进入资料库")

                Button(action: onGoToImport) {
                    Text("去导入资料库")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("onboardingImportButton")
                .accessibilityHint("关闭引导并打开导入页，文件夹会递归扫描")

                Button("跳过", action: onSkip)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("onboardingSkipButton")
                    .accessibilityHint("关闭引导，下次启动不再显示")
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(.bar)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                LinearGradient(
                    colors: [Color.accentColor, .teal],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)

            Text("欢迎使用 LocalPod")
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text("把本地音频放进资料库，按合集、播放列表和队列收听。")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func feature(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
