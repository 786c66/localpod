import SwiftUI
import SwiftData
import LocalPodKit

/// 回收站: browse recently deleted items, restore them, or purge for real.
/// Reached from the bottom of the Library tab; lives in the Library feature
/// folder next to LibraryView.
struct TrashView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PlaybackSession.self) private var session

    @Query(sort: \TrashItem.deletedAt, order: .reverse)
    private var trashItems: [TrashItem]

    @State private var itemPendingPurge: TrashItem?
    @State private var showEmptyConfirmation = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    var body: some View {
        List {
            Section {
                heroCard
                    .tapeRowInsets(8)
            }

            if trashItems.isEmpty {
                Section {
                    emptyCard
                        .tapeRowInsets(6)
                }
            } else {
                Section {
                    ForEach(trashItems) { trashItem in
                        trashRow(trashItem)
                            .tapeRowInsets(4)
                    }
                } header: {
                    TapeSectionHeader(
                        title: L10n.format("trash.count", trashItems.count),
                        kicker: "TRASH"
                    )
                    .textCase(nil)
                    .padding(.horizontal, TapeTheme.screenPadding)
                    .padding(.top, TapeTheme.space3)
                    .padding(.bottom, TapeTheme.space1)
                    .accessibilityIdentifier("trashList")
                } footer: {
                    Text(L10n.format(
                        "trash.retention.footer",
                        L10n.trashRetentionDays
                    ))
                    .font(TapeType.caption)
                    .foregroundStyle(TapeTheme.muted)
                    .padding(.horizontal, TapeTheme.screenPadding)
                    .padding(.top, TapeTheme.space1)
                    .listRowBackground(Color.clear)
                }

                Section {
                    Button(role: .destructive) {
                        showEmptyConfirmation = true
                    } label: {
                        Label(L10n.string("trash.emptyAll"), systemImage: "trash.slash")
                    }
                    .buttonStyle(TapeDestructiveButtonStyle())
                    .accessibilityIdentifier("trashEmptyButton")
                    .tapeRowInsets(6)
                }
            }

            if let infoMessage {
                Section {
                    TapeCard(fill: TapeTheme.acid) {
                        Text(infoMessage)
                            .font(TapeType.body)
                            .foregroundStyle(TapeTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("trashInfoText")
                    }
                    .tapeRowInsets(6)
                }
            }

            if let errorMessage {
                Section {
                    TapeCard(fill: TapeTheme.peach) {
                        Text(errorMessage)
                            .font(TapeType.body)
                            .foregroundStyle(TapeTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("trashErrorText")
                    }
                    .tapeRowInsets(6)
                }
            }
        }
        .listStyle(.plain)
        .tapeScreen()
        .navigationTitle(L10n.string("trash.title"))
        .tapeNavigationChrome()
        .confirmationDialog(
            L10n.string("trash.emptyConfirm.title"),
            isPresented: $showEmptyConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.string("trash.emptyConfirm.confirm"), role: .destructive) {
                emptyTrash()
            }
            .accessibilityIdentifier("trashEmptyConfirm")
            Button(L10n.string("trash.emptyConfirm.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.format("trash.emptyConfirm.message", trashItems.count))
        }
        .confirmationDialog(
            L10n.string("trash.purgeConfirm.title"),
            isPresented: purgeConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button(L10n.string("trash.purgeItem"), role: .destructive) {
                if let item = itemPendingPurge {
                    purgeItem(item)
                }
                itemPendingPurge = nil
            }
            .accessibilityIdentifier("trashPurgeConfirm")
            Button(L10n.string("trash.emptyConfirm.cancel"), role: .cancel) {
                itemPendingPurge = nil
            }
        } message: {
            Text(L10n.string("trash.purgeConfirm.message"))
        }
    }

    // MARK: - Hero and empty state

    private var heroCard: some View {
        TapeCard(fill: TapeTheme.peach) {
            VStack(alignment: .leading, spacing: TapeTheme.space3) {
                HStack(alignment: .top, spacing: TapeTheme.space2) {
                    VStack(alignment: .leading, spacing: 5) {
                        TapeKicker(text: "RECYCLE BIN", color: TapeTheme.ink.opacity(0.62))
                        Text(L10n.string("trash.title"))
                            .font(TapeType.title1)
                            .tracking(-0.6)
                            .foregroundStyle(TapeTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: TapeTheme.space2)
                    TapeSticker(
                        text: "\(L10n.trashRetentionDays) DAYS",
                        fill: TapeTheme.coral,
                        angle: 5
                    )
                }

                Text(L10n.format("trash.count", trashItems.count))
                    .font(TapeType.monoMeta)
                    .foregroundStyle(TapeTheme.ink.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var emptyCard: some View {
        TapeDashedCard {
            VStack(spacing: TapeTheme.space3) {
                TapeRewardSticker(
                    text: "EMPTY",
                    fill: TapeTheme.violet,
                    foreground: TapeTheme.stickerInk
                )
                Text(L10n.string("trash.empty.title"))
                    .font(TapeType.title2)
                    .tracking(-0.4)
                    .foregroundStyle(TapeTheme.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("trashEmptyState")
                Text(L10n.string("trash.empty.detail"))
                    .font(TapeType.body)
                    .foregroundStyle(TapeTheme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// confirmationDialog needs a concrete Bool binding; `itemPendingPurge`
    /// is optional, so project it (same pattern as SettingsView).
    private var purgeConfirmationBinding: Binding<Bool> {
        Binding(
            get: { itemPendingPurge != nil },
            set: { shown in
                if !shown { itemPendingPurge = nil }
            }
        )
    }

    private func trashRow(_ trashItem: TrashItem) -> some View {
        HStack(spacing: TapeTheme.space3) {
            ZStack {
                RoundedRectangle(cornerRadius: TapeTheme.radiusThumb, style: .continuous)
                    .fill(TapeTheme.coralSoft)
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TapeTheme.ink)
            }
            .frame(width: 36, height: 36)
            .overlay {
                RoundedRectangle(cornerRadius: TapeTheme.radiusThumb, style: .continuous)
                    .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(trashItem.title)
                    .font(TapeType.headline)
                    .foregroundStyle(TapeTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.format(
                    "trash.deletedAt",
                    trashItem.deletedAt.formatted(date: .abbreviated, time: .shortened),
                    daysRemaining(trashItem)
                ))
                .font(TapeType.monoMicro)
                .foregroundStyle(TapeTheme.faint)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: TapeTheme.space2)

            // Visible actions keep VoiceOver and UI tests deterministic;
            // swipe actions below are the same operations for touch flow.
            Button {
                restoreItem(trashItem)
            } label: {
                Image(systemName: "arrow.uturn.backward.circle.fill")
            }
            .buttonStyle(TapeIconButtonStyle(diameter: 36, fill: TapeTheme.acid))
            .accessibilityLabel(L10n.string("trash.restore"))
            .accessibilityIdentifier("trashRestore-\(trashItem.title)")

            Button {
                itemPendingPurge = trashItem
            } label: {
                Image(systemName: "trash.circle.fill")
            }
            .buttonStyle(TapeIconButtonStyle(
                diameter: 36,
                fill: TapeTheme.coral,
                foreground: TapeTheme.stickerInk
            ))
            .accessibilityLabel(L10n.string("trash.purgeItem"))
            .accessibilityIdentifier("trashPurge-\(trashItem.title)")
        }
        .padding(.horizontal, TapeTheme.space3)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(TapeTheme.card)
                .shadow(color: TapeTheme.ink, radius: 0, x: 2, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trashItem-\(trashItem.title)")
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                restoreItem(trashItem)
            } label: {
                Label(L10n.string("trash.restore"), systemImage: "arrow.uturn.backward")
            }
            .tint(TapeTheme.violet)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                itemPendingPurge = trashItem
            } label: {
                Label(L10n.string("trash.purgeItem"), systemImage: "trash")
            }
        }
    }

    private func daysRemaining(_ trashItem: TrashItem) -> String {
        let remaining = Int(
            (trashItem.expiresAt.timeIntervalSinceNow / (24 * 60 * 60))
                .rounded(.up)
        )
        return L10n.format("trash.daysRemaining", max(remaining, 0))
    }

    private func restoreItem(_ trashItem: TrashItem) {
        do {
            let result = try TrashService().restore(trashItem, in: modelContext)
            infoMessage = L10n.format(
                "trash.restored",
                result.title
            )
            errorMessage = nil
        } catch {
            errorMessage = L10n.format(
                "trash.restoreFailed",
                error.localizedDescription
            )
            infoMessage = nil
        }
    }

    private func purgeItem(_ trashItem: TrashItem) {
        do {
            _ = try TrashService().purge(trashItem, in: modelContext)
            session.handleDeletedItem(trashItem.itemID)
            infoMessage = L10n.format(
                "trash.purged",
                trashItem.title
            )
            errorMessage = nil
        } catch {
            errorMessage = L10n.format(
                "trash.purgeFailed",
                error.localizedDescription
            )
            infoMessage = nil
        }
    }

    private func emptyTrash() {
        do {
            let result = try TrashService().emptyTrash(in: modelContext)
            // The in-memory queue must drop everything that was purged; the
            // service cleaned the persisted rows.
            for row in trashItems {
                session.handleDeletedItem(row.itemID)
            }
            infoMessage = L10n.format(
                "trash.emptied",
                result.purgedCount
            )
            errorMessage = nil
        } catch {
            errorMessage = L10n.format(
                "trash.purgeFailed",
                error.localizedDescription
            )
            infoMessage = nil
        }
    }
}
