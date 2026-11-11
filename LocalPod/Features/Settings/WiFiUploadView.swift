import SwiftUI
import SwiftData
import UIKit
import CoreImage.CIFilterBuiltins
import LocalPodKit

struct WiFiUploadView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(ImportCoordinator.self) private var coordinator

    @State private var controller = WiFiUploadController()
    @State private var qrImage: UIImage?
    @State private var didCopyAddress = false

    private var displayURL: URL? {
        guard let url = controller.primaryURL,
              let host = url.host,
              host != "127.0.0.1",
              host != "::1",
              host != "localhost" else {
            return nil
        }
        return url
    }

    var body: some View {
        List {
            Section {
                Text(L10n.string("wifi.intro.detail"))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text(L10n.string("wifi.intro.title"))
            }

            switch controller.phase {
            case .idle:
                startSection
            case .starting:
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(L10n.string("wifi.starting"))
                            .foregroundStyle(.secondary)
                    }
                }
            case .running:
                runningSections
            case .failed:
                errorSection
            }

            Section {
                Text(L10n.format(
                    "wifi.limits",
                    ByteCountFormatter.string(
                        fromByteCount: WiFiUploadController.limits.maxFileBytes,
                        countStyle: .file
                    ),
                    WiFiUploadController.limits.maxFiles
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                warningRow(
                    L10n.string("wifi.foreground.warning"),
                    systemImage: "iphone"
                )
                warningRow(
                    L10n.string("wifi.publicWifi.warning"),
                    systemImage: "wifi.exclamationmark"
                )
                warningRow(
                    L10n.string("wifi.permission.warning"),
                    systemImage: "hand.raised"
                )
            }
        }
        .navigationTitle(L10n.string("wifi.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            controller.onSessionCompleted = { completed in
                coordinator.importWiFiSession(completed, modelContext: modelContext)
            }
        }
        .onDisappear {
            controller.onSessionCompleted = nil
            Task { await controller.stop() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                Task { await controller.stop() }
            }
        }
        .onChange(of: displayURL) { _, url in
            updateQRCode(for: url)
        }
    }

    private var startSection: some View {
        Section {
            Button {
                Task { await controller.start() }
            } label: {
                Label(L10n.string("wifi.start"), systemImage: "wifi")
            }
            .accessibilityIdentifier("wifiStartButton")
        } footer: {
            Text(L10n.string("wifi.start.footer"))
        }
    }

    @ViewBuilder
    private var runningSections: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("wifi.address"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let url = displayURL {
                    Text(url.absoluteString)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("wifiURLText")
                    Button {
                        UIPasteboard.general.string = url.absoluteString
                        didCopyAddress = true
                    } label: {
                        Label(
                            didCopyAddress
                                ? L10n.string("wifi.address.copied")
                                : L10n.string("wifi.address.copy"),
                            systemImage: didCopyAddress ? "checkmark" : "doc.on.doc"
                        )
                    }
                    .accessibilityIdentifier("wifiCopyAddressButton")
                } else {
                    Text(L10n.string("wifi.address.unavailable"))
                        .foregroundStyle(.secondary)
                }
            }

            Text(L10n.string("wifi.status.running"))
                .font(.caption)
                .foregroundStyle(.green)
                .accessibilityIdentifier("wifiStatusText")
        } header: {
            Text(L10n.string("wifi.connection"))
        } footer: {
            Text(L10n.string("wifi.address.footer"))
        }

        Section {
            Text(controller.pin)
                .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                .tracking(6)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel(L10n.format("wifi.pin.accessibility", controller.pin))
                .accessibilityIdentifier("wifiPINText")
                .textSelection(.enabled)
        } header: {
            Text(L10n.string("wifi.pin"))
        } footer: {
            Text(L10n.string("wifi.pin.footer"))
        }

        if let image = qrImage {
            Section {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 230, maxHeight: 230)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(L10n.string("wifi.qr.label"))
                    .accessibilityIdentifier("wifiQRCode")
            } header: {
                Text(L10n.string("wifi.qr.title"))
            }
        }

        Section {
            LabeledContent(
                L10n.string("wifi.received"),
                value: L10n.format("wifi.received.count", controller.uploadedFileCount)
            )
            .accessibilityIdentifier("wifiReceivedCount")
            if let name = controller.lastUploadedFileName {
                Text(L10n.format("wifi.received.last", name))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if controller.lastCompletedSessionID != nil {
                Label(
                    coordinator.isRunning
                        ? L10n.string("wifi.import.queuedBusy")
                        : L10n.string("wifi.import.queued"),
                    systemImage: "tray.and.arrow.down.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("wifiImportQueuedText")
            }
            if let error = controller.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("wifiErrorText")
            }
        } header: {
            Text(L10n.string("wifi.activity"))
        }

        Section {
            Button(role: .destructive) {
                Task { await controller.stop() }
            } label: {
                Label(L10n.string("wifi.stop"), systemImage: "stop.circle")
            }
            .disabled(controller.isStopping)
            .accessibilityIdentifier("wifiStopButton")
        }
    }

    private var errorSection: some View {
        Section {
            Label(L10n.string("wifi.error.title"), systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            if let error = controller.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("wifiErrorText")
            }
            Text(L10n.string("wifi.error.localNetwork"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await controller.start() }
            } label: {
                Label(L10n.string("wifi.retry"), systemImage: "arrow.clockwise")
            }
            .accessibilityIdentifier("wifiRetryButton")
        }
    }

    private func warningRow(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func updateQRCode(for url: URL?) {
        didCopyAddress = false
        guard let url else {
            qrImage = nil
            return
        }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else {
            qrImage = nil
            return
        }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            qrImage = nil
            return
        }
        qrImage = UIImage(cgImage: cgImage)
    }
}
