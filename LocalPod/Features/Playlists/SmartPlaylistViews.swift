import SwiftUI
import SwiftData
import LocalPodKit

// MARK: - Display helpers

extension SmartPlaylistKind {
    var displayName: String {
        switch self {
        case .continueListening: L10n.string("smart.playlist.continue")
        case .unfinished: L10n.string("smart.playlist.unfinished")
        case .recentlyAdded: L10n.string("smart.playlist.recent")
        case .finished: L10n.string("smart.playlist.finished")
        }
    }

    var subtitle: String {
        switch self {
        case .continueListening: L10n.string("smart.playlist.continue.subtitle")
        case .unfinished: L10n.string("smart.playlist.unfinished.subtitle")
        case .recentlyAdded: L10n.string("smart.playlist.recent.subtitle")
        case .finished: L10n.string("smart.playlist.finished.subtitle")
        }
    }

    var emptyDescription: String {
        switch self {
        case .continueListening: L10n.string("smart.playlist.empty.continue")
        case .unfinished: L10n.string("smart.playlist.empty.unfinished")
        case .recentlyAdded: L10n.string("smart.playlist.empty.recent")
        case .finished: L10n.string("smart.playlist.empty.finished")
        }
    }
}

private extension PlaybackState {
    var smartSnapshot: SmartPlaylistPlayback {
        SmartPlaylistPlayback(
            position: position,
            duration: duration,
            isFinished: isFinished,
            playCount: playCount,
            lastPlayedAt: lastPlayedAt
        )
    }
}

private func makeSmartEntries(
    items: [MediaItem],
    states: [PlaybackState]
) -> [SmartPlaylistEntry] {
    let statesByID = Dictionary(
        states.map { ($0.itemID, $0) },
        uniquingKeysWith: { first, _ in first }
    )
    return items.map { item in
        SmartPlaylistEntry(
            id: item.id,
            addedAt: item.addedAt,
            collectionID: item.collectionID,
            isMissing: item.isMissing,
            playback: statesByID[item.id]?.smartSnapshot
        )
    }
}

// MARK: - Hub section

/// Dynamic smart lists are computed from the library and progress rows on
/// every render. They are never persisted, so deleting items/progress or
/// re-importing content can never leave a stale smart playlist behind.
struct SmartPlaylistHubSection: View {
    @Query(sort: \MediaItem.addedAt, order: .reverse)
    private var allItems: [MediaItem]
    @Query private var playbackStates: [PlaybackState]
    @Query(sort: \MediaCollection.name)
    private var collections: [MediaCollection]

    private var libraryItems: [MediaItem] {
        allItems.filter { $0.source != .benchmark }
    }

    private var entries: [SmartPlaylistEntry] {
        makeSmartEntries(items: libraryItems, states: playbackStates)
    }

    private var counts: [SmartPlaylistKind: Int] {
        SmartPlaylistEngine.counts(entries)
    }

    var body: some View {
        Section {
            ForEach(SmartPlaylistKind.allCases) { kind in
                NavigationLink {
                    SmartPlaylistDetailView(kind: kind)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: kind.symbolName)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(kind.displayName)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(kind.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Text("\(counts[kind, default: 0])")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("smartPlaylistCount-\(kind.rawValue)")
                    }
                }
                .accessibilityIdentifier("smartPlaylistRow-\(kind.rawValue)")
                .accessibilityValue("\(counts[kind, default: 0])")
            }

            NavigationLink {
                SmartCollectionPickerView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.grid.2x2")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.string("smart.playlist.byCollection"))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(L10n.string("smart.playlist.byCollection.subtitle"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Text(L10n.format("smart.playlist.collectionCount", collections.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("smartPlaylistRow-byCollection")
        } header: {
            Text(L10n.string("smart.playlist.section"))
        } footer: {
            Text(L10n.string("smart.playlist.section.footer"))
        }
    }
}

// MARK: - Smart detail

struct SmartPlaylistDetailView: View {
    let kind: SmartPlaylistKind

    @Environment(PlaybackSession.self) private var session

    @Query(sort: \MediaItem.addedAt, order: .reverse)
    private var allItems: [MediaItem]
    @Query private var playbackStates: [PlaybackState]
    @Query(sort: \MediaCollection.name)
    private var collections: [MediaCollection]

    @State private var selectedCollectionID: UUID?

    private var libraryItems: [MediaItem] {
        allItems.filter { $0.source != .benchmark }
    }

    private var entries: [SmartPlaylistEntry] {
        let all = makeSmartEntries(items: libraryItems, states: playbackStates)
        return SmartPlaylistEngine.entries(
            all,
            kind: kind,
            collectionID: selectedCollectionID
        )
    }

    private var itemByID: [UUID: MediaItem] {
        Dictionary(uniqueKeysWithValues: libraryItems.map { ($0.id, $0) })
    }

    private var stateByID: [UUID: PlaybackState] {
        Dictionary(
            playbackStates.map { ($0.itemID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var playableItems: [MediaItem] {
        entries.compactMap { itemByID[$0.id] }
    }

    private var collectionByID: [UUID: MediaCollection] {
        Dictionary(uniqueKeysWithValues: collections.map { ($0.id, $0) })
    }

    private var filterTitle: String {
        guard let selectedCollectionID,
              let collection = collectionByID[selectedCollectionID] else {
            return L10n.string("smart.playlist.filter.allCollections")
        }
        return collection.name
    }

    var body: some View {
        List {
            Section {
                Button {
                    session.play(items: playableItems)
                } label: {
                    Label(
                        L10n.format("smart.playlist.playAll", playableItems.count),
                        systemImage: "play.fill"
                    )
                }
                .disabled(playableItems.isEmpty)
                .accessibilityIdentifier("smartPlaylistPlayAllButton")

                Button {
                    session.play(items: playableItems, shuffle: true)
                } label: {
                    Label(L10n.string("smart.playlist.shuffle"), systemImage: "shuffle")
                }
                .disabled(playableItems.isEmpty)
                .accessibilityIdentifier("smartPlaylistShuffleButton")
            }

            Section {
                if collections.isEmpty {
                    LabeledContent(
                        L10n.string("smart.playlist.filter.menu"),
                        value: L10n.string("smart.playlist.filter.allCollections")
                    )
                } else {
                    Menu {
                        Button(L10n.string("smart.playlist.filter.allCollections")) {
                            selectedCollectionID = nil
                        }
                        Divider()
                        ForEach(collections) { collection in
                            Button(collection.name) {
                                selectedCollectionID = collection.id
                            }
                        }
                    } label: {
                        LabeledContent(
                            L10n.string("smart.playlist.filter.menu"),
                            value: filterTitle
                        )
                    }
                    .accessibilityIdentifier("smartPlaylistFilterMenu")
                }
            } footer: {
                Text(L10n.string("smart.playlist.filter.footer"))
            }

            Section(L10n.format("smart.playlist.items", entries.count)) {
                if entries.isEmpty {
                    ContentUnavailableView(
                        L10n.string("smart.playlist.empty.title"),
                        systemImage: kind.symbolName,
                        description: Text(kind.emptyDescription)
                    )
                    .accessibilityIdentifier("smartPlaylistEmptyState")
                } else {
                    ForEach(entries) { entry in
                        if let item = itemByID[entry.id] {
                            NavigationLink {
                                LibraryItemDetailView(item: item)
                            } label: {
                                SmartPlaylistItemRow(
                                    item: item,
                                    state: stateByID[item.id],
                                    kind: kind,
                                    collectionName: item.collectionID
                                        .flatMap { collectionByID[$0]?.name }
                                )
                            }
                            .accessibilityIdentifier("smartPlaylistItem-\(item.title)")
                        }
                    }
                }
            }
        }
        .navigationTitle(kind.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SmartPlaylistItemRow: View {
    let item: MediaItem
    let state: PlaybackState?
    let kind: SmartPlaylistKind
    let collectionName: String?

    private var progress: Double {
        guard let state, state.duration > 0 else { return 0 }
        return min(max(state.position / state.duration, 0), 1)
    }

    var body: some View {
        HStack(spacing: 12) {
            MediaArtworkView(item: item, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .fixedSize(horizontal: false, vertical: true)

                switch kind {
                case .continueListening, .unfinished:
                    if let state, state.position > 0 {
                        ProgressView(value: progress)
                            .tint(Color.accentColor)
                        Text(L10n.format(
                            "smart.playlist.progress",
                            Int(state.position),
                            item.durationText
                        ))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                case .finished:
                    Label(
                        L10n.string("smart.playlist.finished.badge"),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.green)
                case .recentlyAdded:
                    Text(L10n.format(
                        "smart.playlist.addedAt",
                        item.addedAt.formatted(date: .abbreviated, time: .omitted)
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let collectionName, !collectionName.isEmpty {
                    Text(collectionName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(item.durationText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Collection-filtered browse

struct SmartCollectionPickerView: View {
    @Query(sort: \MediaCollection.name)
    private var collections: [MediaCollection]
    @Query(sort: \MediaItem.addedAt, order: .reverse)
    private var allItems: [MediaItem]

    private var libraryItems: [MediaItem] {
        allItems.filter { $0.source != .benchmark }
    }

    var body: some View {
        List {
            if collections.isEmpty {
                ContentUnavailableView(
                    L10n.string("smart.playlist.collections.empty"),
                    systemImage: "square.grid.2x2",
                    description: Text(L10n.string("smart.playlist.collections.empty.detail"))
                )
                .accessibilityIdentifier("smartCollectionEmptyState")
            } else {
                Section {
                    ForEach(collections) { collection in
                        NavigationLink {
                            SmartCollectionItemsView(collection: collection)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "folder")
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(collection.name)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(L10n.format(
                                        "smart.playlist.collectionItemCount",
                                        libraryItems.filter { $0.collectionID == collection.id }.count
                                    ))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityIdentifier("smartCollectionRow-\(collection.name)")
                    }
                }
            }
        }
        .navigationTitle(L10n.string("smart.playlist.byCollection"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SmartCollectionItemsView: View {
    let collection: MediaCollection

    @Environment(PlaybackSession.self) private var session
    @Query private var allItems: [MediaItem]
    @Query private var playbackStates: [PlaybackState]

    private var items: [MediaItem] {
        allItems
            .filter { $0.collectionID == collection.id && $0.source != .benchmark }
            .sorted { $0.relativeFolderPath.localizedStandardCompare($1.relativeFolderPath) == .orderedAscending }
    }

    private var stateByID: [UUID: PlaybackState] {
        Dictionary(uniqueKeysWithValues: playbackStates.map { ($0.itemID, $0) })
    }

    var body: some View {
        List {
            Section {
                Button {
                    session.play(items: items)
                } label: {
                    Label(
                        L10n.format("smart.playlist.playAll", items.count),
                        systemImage: "play.fill"
                    )
                }
                .disabled(items.isEmpty)
                .accessibilityIdentifier("smartCollectionPlayAllButton")

                Button {
                    session.play(items: items, shuffle: true)
                } label: {
                    Label(L10n.string("smart.playlist.shuffle"), systemImage: "shuffle")
                }
                .disabled(items.isEmpty)
                .accessibilityIdentifier("smartCollectionShuffleButton")
            }

            Section(L10n.format("smart.playlist.items", items.count)) {
                if items.isEmpty {
                    ContentUnavailableView(
                        L10n.string("smart.playlist.empty.title"),
                        systemImage: "folder",
                        description: Text(L10n.string("smart.playlist.empty.collection"))
                    )
                    .accessibilityIdentifier("smartCollectionItemsEmptyState")
                } else {
                    ForEach(items) { item in
                        NavigationLink {
                            LibraryItemDetailView(item: item)
                        } label: {
                            SmartPlaylistItemRow(
                                item: item,
                                state: stateByID[item.id],
                                kind: .recentlyAdded,
                                collectionName: nil
                            )
                        }
                        .accessibilityIdentifier("smartCollectionItem-\(item.title)")
                    }
                }
            }
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
