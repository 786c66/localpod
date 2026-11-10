import SwiftUI
import AVKit

struct VideoPlayerScreen: View {
    let player: AVPlayer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VideoPlayerControllerRepresentable(player: player)
                .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.55))
                    .padding()
            }
            .accessibilityLabel("关闭视频")
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
    }
}

struct VideoPlayerControllerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        // PiP is deliberately M2 scope; M0 only verifies picture + fullscreen.
        controller.allowsPictureInPicturePlayback = false
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}
