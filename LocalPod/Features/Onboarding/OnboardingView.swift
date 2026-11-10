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
                        title: "文件夹导入会递归扫描",
                        detail: "选择整个文件夹后，LocalPod 会扫描所有子文件夹，复制音频与视频文件进本地资料库。"
                    )
                    feature(
                        icon: "waveform",
                        title: "只播放音频",
                        detail: "视频文件也可以导入，但只播放其中的音轨；不显示画面、不做旋转或画中画。"
                    )
                    feature(
                        icon: "gift",
                        title: "完全免费",
                        detail: "没有内购、订阅或广告。所有功能都可以直接使用。"
                    )
                    feature(
                        icon: "checkmark.seal",
                        title: "免费 Apple ID 侧载",
                        detail: "通过 Xcode 或 SideStore/AltStore 安装时，需要每 7 天用免费 Apple ID 重新签名；重新签名不会清除资料库。"
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
