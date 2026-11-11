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
            if trashItems.isEmpty {
                Section {
                    ContentUnavailableView(
                        L10n.string("trash.empty.title"),
                        systemImage: "trash",
                        description: Text(L10n.string("trash.empty.detail"))
                    )
                    .accessibilityIdentifier("trashEmptyState")
                }
            } else {
                Section {
                    ForEach(trashItems) { trashItem in
                        trashRow(trashItem)
                    }
                } header: {
                    Text(L10n.format("trash.count", trashItems.count))
                        .accessibilityIdentifier("trashList")
                } footer: {
                    Text(L10n.format(
                        "trash.retention.footer",
                        L10n.trashRetentionDays
                    ))
                }
            }

            if !trashItems.isEmpty {
                Section {
                    Button(role: .destructive) {
                        showEmptyConfirmation = true
                    } label: {
                        Label(L10n.string("trash.emptyAll"), systemImage: "trash.slash")
                    }
                    .accessibilityIdentifier("trashEmptyButton")
                }
            }

            if let infoMessage {
                Section {
                    Text(infoMessage)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityIdentifier("trashInfoText")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("trashErrorText")
                }
            }
        }
        .navigationTitle(L10n.string("trash.title"))
        .navigationBarTitleDisplayMode(.inline)
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

    @ViewBuilder
    private func trashRow(_ trashItem: TrashItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(trashItem.title)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.format(
                    "trash.deletedAt",
                    trashItem.deletedAt.formatted(date: .abbreviated, time: .shortened),
                    daysRemaining(trashItem)
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            // Visible actions keep VoiceOver and UI tests deterministic;
            // swipe actions below are the same operations for touch flow.
            Button {
                restoreItem(trashItem)
            } label: {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("trash.restore"))
            .accessibilityIdentifier("trashRestore-\(trashItem.title)")

            Button {
                itemPendingPurge = trashItem
            } label: {
                Image(systemName: "trash.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("trash.purgeItem"))
            .accessibilityIdentifier("trashPurge-\(trashItem.title)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trashItem-\(trashItem.title)")
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                restoreItem(trashItem)
            } label: {
                Label(L10n.string("trash.restore"), systemImage: "arrow.uturn.backward")
            }
            .tint(Color.accentColor)
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
