import SwiftUI
import AVKit

struct VideoPlayerScreen: View {
    let player: AVPlayer
    var onPictureInPictureChange: @MainActor (Bool) -> Void = { _ in }
    var onRestoreUI: @MainActor () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VideoPlayerControllerRepresentable(
                player: player,
                onPictureInPictureChange: onPictureInPictureChange,
                onRestoreUI: onRestoreUI
            )
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
            .accessibilityIdentifier("closeVideoButton")
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
    }
}

struct VideoPlayerControllerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer
    var onPictureInPictureChange: @MainActor (Bool) -> Void
    var onRestoreUI: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onPictureInPictureChange: onPictureInPictureChange,
            onRestoreUI: onRestoreUI
        )
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
        if uiViewController.delegate !== context.coordinator {
            uiViewController.delegate = context.coordinator
        }
        context.coordinator.onPictureInPictureChange = onPictureInPictureChange
        context.coordinator.onRestoreUI = onRestoreUI
    }

    /// AVKit invokes these callbacks on the main thread. Swift 6 cannot infer
    /// that from the nonisolated protocol, so each callback hops back with an
    /// isolated assumption instead of touching MainActor state directly. The
    /// unchecked Sendable conformance is safe because AVKit only calls the
    /// delegate on the main thread and SwiftUI mutates the closures there too.
    final class Coordinator: NSObject, AVPlayerViewControllerDelegate, @unchecked Sendable {
        var onPictureInPictureChange: @MainActor (Bool) -> Void
        var onRestoreUI: @MainActor () -> Void

        init(
            onPictureInPictureChange: @escaping @MainActor (Bool) -> Void,
            onRestoreUI: @escaping @MainActor () -> Void
        ) {
            self.onPictureInPictureChange = onPictureInPictureChange
            self.onRestoreUI = onRestoreUI
        }

        private func notifyPictureInPicture(_ active: Bool) {
            MainActor.assumeIsolated {
                onPictureInPictureChange(active)
            }
        }

        func playerViewControllerWillStartPictureInPicture(
            _ playerViewController: AVPlayerViewController
        ) {
            notifyPictureInPicture(true)
        }

        func playerViewControllerDidStartPictureInPicture(
            _ playerViewController: AVPlayerViewController
        ) {
            notifyPictureInPicture(true)
        }

        func playerViewControllerWillStopPictureInPicture(
            _ playerViewController: AVPlayerViewController
        ) {
            notifyPictureInPicture(false)
        }

        func playerViewControllerDidStopPictureInPicture(
            _ playerViewController: AVPlayerViewController
        ) {
            notifyPictureInPicture(false)
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            failedToStartPictureInPictureWithError error: Error
        ) {
            notifyPictureInPicture(false)
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
        ) {
            MainActor.assumeIsolated {
                onRestoreUI()
            }
            completionHandler(true)
        }
    }
}
