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
            // While the server runs, the connection/PIN cards sit above the
            // intro: a List only realises visible rows, and the tests (and a
            // glance at the screen) expect the live address and PIN first.
            switch controller.phase {
            case .idle:
                EmptyView()
            case .starting:
                Section {
                    TapeCard {
                        HStack(spacing: TapeTheme.space3) {
                            ProgressView()
                                .tint(TapeTheme.ink)
                            Text(L10n.string("wifi.starting"))
                                .font(TapeType.body)
                                .foregroundStyle(TapeTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .tapeRowInsets(6)
                }
            case .running:
                runningSections
            case .failed:
                errorSection
            }

            Section {
                TapeCard(fill: TapeTheme.violetSoft) {
                    VStack(alignment: .leading, spacing: TapeTheme.space3) {
                        HStack(alignment: .center, spacing: TapeTheme.space2) {
                            TapeSticker(
                                text: "WI-FI",
                                fill: TapeTheme.violet,
                                foreground: TapeTheme.stickerInk
                            )
                            Spacer(minLength: TapeTheme.space2)
                            Text("LOCAL LAN")
                                .font(TapeType.monoMicro)
                                .foregroundStyle(TapeTheme.ink.opacity(0.62))
                        }
                        Text(L10n.string("wifi.intro.detail"))
                            .font(TapeType.body)
                            .foregroundStyle(TapeTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .tapeRowInsets(8)
            } header: {
                sectionHeader(L10n.string("wifi.intro.title"), kicker: "WI-FI UPLOAD")
            }

            if controller.phase == .idle {
                startSection
            }

            Section {
                TapeCard {
                    VStack(alignment: .leading, spacing: TapeTheme.space3) {
                        Text(L10n.format(
                            "wifi.limits",
                            ByteCountFormatter.string(
                                fromByteCount: WiFiUploadController.limits.maxFileBytes,
                                countStyle: .file
                            ),
                            WiFiUploadController.limits.maxFiles
                        ))
                        .font(TapeType.monoMicro)
                        .foregroundStyle(TapeTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                        TapeHairline()

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
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .tapeRowInsets(6)
            }
        }
        .listStyle(.plain)
        .tapeScreen()
        .navigationTitle(L10n.string("wifi.title"))
        .tapeNavigationChrome()
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
            .buttonStyle(TapePrimaryButtonStyle())
            .accessibilityIdentifier("wifiStartButton")
            .tapeRowInsets(4)
        } footer: {
            sectionFooter(L10n.string("wifi.start.footer"))
        }
    }

    @ViewBuilder
    private var runningSections: some View {
        Section {
            TapeCard {
                VStack(alignment: .leading, spacing: TapeTheme.space3) {
                    VStack(alignment: .leading, spacing: TapeTheme.space2) {
                        Text(L10n.string("wifi.address"))
                            .font(TapeType.monoMicro)
                            .foregroundStyle(TapeTheme.faint)
                        if let url = displayURL {
                            Text(url.absoluteString)
                                .font(TapeFont.mono(17, weight: .semibold, relativeTo: .body))
                                .foregroundStyle(TapeTheme.ink)
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
                            .buttonStyle(TapeSecondaryButtonStyle())
                            .accessibilityIdentifier("wifiCopyAddressButton")
                        } else {
                            Text(L10n.string("wifi.address.unavailable"))
                                .font(TapeType.body)
                                .foregroundStyle(TapeTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    HStack(spacing: TapeTheme.space2) {
                        Circle()
                            .fill(TapeTheme.acid)
                            .frame(width: 10, height: 10)
                            .overlay {
                                Circle().strokeBorder(TapeTheme.ink, lineWidth: 1)
                            }
                            .accessibilityHidden(true)
                        Text(L10n.string("wifi.status.running"))
                            .font(TapeType.monoMeta)
                            .foregroundStyle(TapeTheme.ink)
                            .accessibilityIdentifier("wifiStatusText")
                    }
                    .padding(.horizontal, TapeTheme.space3)
                    .padding(.vertical, TapeTheme.space2)
                    .background(TapeTheme.acid, in: Capsule())
                    .overlay { Capsule().strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tapeRowInsets(6)
        } header: {
            sectionHeader(L10n.string("wifi.connection"), kicker: "CONNECTION")
        } footer: {
            sectionFooter(L10n.string("wifi.address.footer"))
        }

        Section {
            TapeCard(fill: TapeTheme.acid) {
                Text(controller.pin)
                    .font(TapeFont.mono(40, weight: .bold, relativeTo: .largeTitle))
                    .tracking(6)
                    .foregroundStyle(TapeTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityLabel(L10n.format("wifi.pin.accessibility", controller.pin))
                    .accessibilityIdentifier("wifiPINText")
                    .textSelection(.enabled)
            }
            .tapeRowInsets(6)
        } header: {
            sectionHeader(L10n.string("wifi.pin"), kicker: "PIN")
        } footer: {
            sectionFooter(L10n.string("wifi.pin.footer"))
        }

        if let image = qrImage {
            Section {
                TapeCard {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 230, maxHeight: 230)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(L10n.string("wifi.qr.label"))
                        .accessibilityIdentifier("wifiQRCode")
                }
                .tapeRowInsets(6)
            } header: {
                sectionHeader(L10n.string("wifi.qr.title"), kicker: "QR")
            }
        }

        Section {
            TapeCard {
                VStack(alignment: .leading, spacing: TapeTheme.space2) {
                    HStack(alignment: .firstTextBaseline, spacing: TapeTheme.space2) {
                        Text(L10n.string("wifi.received"))
                            .font(TapeType.body)
                            .foregroundStyle(TapeTheme.muted)
                        Spacer(minLength: TapeTheme.space2)
                        Text(L10n.format("wifi.received.count", controller.uploadedFileCount))
                            .font(TapeFont.mono(19, weight: .semibold, relativeTo: .title3))
                            .foregroundStyle(TapeTheme.ink)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("wifiReceivedCount")

                    if let name = controller.lastUploadedFileName {
                        Text(L10n.format("wifi.received.last", name))
                            .font(TapeType.monoMicro)
                            .foregroundStyle(TapeTheme.faint)
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
                        .font(TapeType.captionSmall)
                        .foregroundStyle(TapeTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("wifiImportQueuedText")
                    }
                    if let error = controller.lastError {
                        Text(error)
                            .font(TapeType.captionSmall)
                            .foregroundStyle(TapeTheme.coral)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("wifiErrorText")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tapeRowInsets(6)
        } header: {
            sectionHeader(L10n.string("wifi.activity"), kicker: "ACTIVITY")
        }

        Section {
            Button(role: .destructive) {
                Task { await controller.stop() }
            } label: {
                Label(L10n.string("wifi.stop"), systemImage: "stop.circle")
            }
            .buttonStyle(TapeDestructiveButtonStyle())
            .disabled(controller.isStopping)
            .opacity(controller.isStopping ? 0.5 : 1)
            .accessibilityIdentifier("wifiStopButton")
            .tapeRowInsets(4)
        }
    }

    private var errorSection: some View {
        Section {
            TapeCard {
                VStack(alignment: .leading, spacing: TapeTheme.space3) {
                    Label(L10n.string("wifi.error.title"), systemImage: "exclamationmark.triangle")
                        .font(TapeType.headline)
                        .foregroundStyle(TapeTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let error = controller.lastError {
                        Text(error)
                            .font(TapeType.monoMicro)
                            .foregroundStyle(TapeTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("wifiErrorText")
                    }
                    Text(L10n.string("wifi.error.localNetwork"))
                        .font(TapeType.captionSmall)
                        .foregroundStyle(TapeTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        Task { await controller.start() }
                    } label: {
                        Label(L10n.string("wifi.retry"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(TapeSecondaryButtonStyle())
                    .accessibilityIdentifier("wifiRetryButton")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tapeRowInsets(6)
        }
    }

    private func warningRow(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(TapeType.captionSmall)
            .foregroundStyle(TapeTheme.ink.opacity(0.78))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func sectionHeader(_ title: String, kicker: String) -> some View {
        TapeSectionHeader(title: title, kicker: kicker)
            .textCase(nil)
            .padding(.horizontal, TapeTheme.screenPadding)
            .padding(.top, TapeTheme.space3)
            .padding(.bottom, TapeTheme.space1)
    }

    private func sectionFooter(_ text: String) -> some View {
        Text(text)
            .font(TapeType.captionSmall)
            .foregroundStyle(TapeTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, TapeTheme.space4)
            .padding(.top, TapeTheme.space1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowBackground(Color.clear)
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
