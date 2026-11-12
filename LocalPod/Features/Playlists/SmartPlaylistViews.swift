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
    var onSelectKind: (SmartPlaylistKind) -> Void = { _ in }
    var onSelectCollections: () -> Void = {}

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
                kindRow(kind)
            }

            collectionRow
        } header: {
            TapeSectionHeader(
                title: L10n.string("smart.playlist.section"),
                kicker: "SMART MIXES"
            )
            .textCase(nil)
            .padding(.horizontal, TapeTheme.screenPadding)
            .padding(.top, TapeTheme.space3)
            .padding(.bottom, TapeTheme.space1)
        } footer: {
            Text(L10n.string("smart.playlist.section.footer"))
                .font(TapeType.caption)
                .foregroundStyle(TapeTheme.muted)
                .padding(.horizontal, TapeTheme.screenPadding)
                .padding(.top, TapeTheme.space1)
                .listRowBackground(Color.clear)
        }
    }

    private func kindRow(_ kind: SmartPlaylistKind) -> some View {
        Button {
            onSelectKind(kind)
        } label: {
            HStack(spacing: TapeTheme.space3) {
                hubThumb(symbol: kind.symbolName, fill: thumbFill(for: kind))

                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.displayName)
                        .font(TapeType.headline)
                        .foregroundStyle(TapeTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(kind.subtitle)
                        .font(TapeType.monoMicro)
                        .foregroundStyle(TapeTheme.faint)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: TapeTheme.space2)

                Text("\(counts[kind, default: 0])")
                    .font(TapeFont.mono(12, weight: .semibold, relativeTo: .caption))
                    .foregroundStyle(TapeTheme.ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(TapeTheme.cream, in: Capsule())
                    .overlay { Capsule().strokeBorder(TapeTheme.ink, lineWidth: 1) }
                    .accessibilityIdentifier("smartPlaylistCount-\(kind.rawValue)")

                trailingChevron
            }
            .hubCardChrome()
        }
        .buttonStyle(TapePlainPressStyle())
        .accessibilityIdentifier("smartPlaylistRow-\(kind.rawValue)")
        .accessibilityValue("\(counts[kind, default: 0])")
        .tapeRowInsets(4)
    }

    private var collectionRow: some View {
        Button {
            onSelectCollections()
        } label: {
            HStack(spacing: TapeTheme.space3) {
                hubThumb(symbol: "square.grid.2x2", fill: TapeTheme.violetSoft)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("smart.playlist.byCollection"))
                        .font(TapeType.headline)
                        .foregroundStyle(TapeTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.string("smart.playlist.byCollection.subtitle"))
                        .font(TapeType.monoMicro)
                        .foregroundStyle(TapeTheme.faint)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: TapeTheme.space2)

                Text(L10n.format("smart.playlist.collectionCount", collections.count))
                    .font(TapeType.monoMeta)
                    .foregroundStyle(TapeTheme.faint)

                trailingChevron
            }
            .hubCardChrome()
        }
        .buttonStyle(TapePlainPressStyle())
        .accessibilityIdentifier("smartPlaylistRow-byCollection")
        .tapeRowInsets(4)
    }

    private func hubThumb(symbol: String, fill: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: TapeTheme.radiusThumb, style: .continuous)
                .fill(fill)
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TapeTheme.ink)
        }
        .frame(width: 36, height: 36)
        .overlay {
            RoundedRectangle(cornerRadius: TapeTheme.radiusThumb, style: .continuous)
                .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
        }
        .accessibilityHidden(true)
    }

    private var trailingChevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(TapeTheme.faint)
    }

    private func thumbFill(for kind: SmartPlaylistKind) -> Color {
        switch kind {
        case .continueListening: TapeTheme.acid
        case .unfinished: TapeTheme.peach
        case .recentlyAdded: TapeTheme.violetSoft
        case .finished: TapeTheme.coralSoft
        }
    }
}

private extension View {
    /// Shared card chrome for the smart-list hub rows.
    func hubCardChrome() -> some View {
        self
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
    @State private var itemDetailTarget: MediaItem?
    @State private var showItemDetail = false

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
                heroCard
                    .tapeRowInsets(8)
            }

            Section {
                TapeCard {
                    filterRow
                }
                .tapeRowInsets(6)
            } footer: {
                Text(L10n.string("smart.playlist.filter.footer"))
                    .font(TapeType.caption)
                    .foregroundStyle(TapeTheme.muted)
                    .padding(.horizontal, TapeTheme.screenPadding)
                    .padding(.top, TapeTheme.space1)
                    .listRowBackground(Color.clear)
            }

            Section {
                if entries.isEmpty {
                    emptyCard
                        .tapeRowInsets(6)
                } else {
                    ForEach(entries) { entry in
                        if let item = itemByID[entry.id] {
                            Button {
                                itemDetailTarget = item
                                showItemDetail = true
                            } label: {
                                SmartPlaylistItemRow(
                                    item: item,
                                    state: stateByID[item.id],
                                    kind: kind,
                                    collectionName: item.collectionID
                                        .flatMap { collectionByID[$0]?.name }
                                )
                            }
                            .buttonStyle(TapePlainPressStyle())
                            .accessibilityIdentifier("smartPlaylistItem-\(item.title)")
                            .tapeRowInsets(4)
                        }
                    }
                }
            } header: {
                sectionHeader(
                    L10n.format("smart.playlist.items", entries.count),
                    kicker: "ON THE MIX"
                )
            }
        }
        .listStyle(.plain)
        .tapeScreen()
        .navigationTitle(kind.displayName)
        .tapeNavigationChrome()
        .navigationDestination(isPresented: $showItemDetail) {
            if let itemDetailTarget {
                LibraryItemDetailView(item: itemDetailTarget)
            }
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        TapeCard(fill: TapeTheme.acid) {
            VStack(alignment: .leading, spacing: TapeTheme.space3) {
                HStack(alignment: .top, spacing: TapeTheme.space2) {
                    VStack(alignment: .leading, spacing: 5) {
                        TapeKicker(text: "SMART MIX", color: TapeTheme.ink.opacity(0.62))
                        Text(kind.displayName)
                            .font(TapeType.title1)
                            .tracking(-0.6)
                            .foregroundStyle(TapeTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: TapeTheme.space2)
                    TapeSticker(
                        text: "\(entries.count)",
                        fill: TapeTheme.card,
                        foreground: TapeTheme.ink,
                        angle: 4
                    )
                }

                Text(kind.subtitle)
                    .font(TapeType.body)
                    .foregroundStyle(TapeTheme.ink.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: TapeTheme.space2) {
                        playAllButton
                        shuffleButton
                    }
                    VStack(spacing: TapeTheme.space2) {
                        playAllButton
                        shuffleButton
                    }
                }
            }
        }
    }

    private var playAllButton: some View {
        Button {
            session.play(items: playableItems)
        } label: {
            Label(
                L10n.format("smart.playlist.playAll", playableItems.count),
                systemImage: "play.fill"
            )
        }
        .buttonStyle(TapePrimaryButtonStyle())
        .disabled(playableItems.isEmpty)
        .opacity(playableItems.isEmpty ? 0.55 : 1)
        .accessibilityIdentifier("smartPlaylistPlayAllButton")
    }

    private var shuffleButton: some View {
        Button {
            session.play(items: playableItems, shuffle: true)
        } label: {
            Label(L10n.string("smart.playlist.shuffle"), systemImage: "shuffle")
        }
        .buttonStyle(TapeSecondaryButtonStyle())
        .disabled(playableItems.isEmpty)
        .opacity(playableItems.isEmpty ? 0.55 : 1)
        .accessibilityIdentifier("smartPlaylistShuffleButton")
    }

    // MARK: - Filter

    @ViewBuilder
    private var filterRow: some View {
        if collections.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: TapeTheme.space2) {
                Text(L10n.string("smart.playlist.filter.menu"))
                    .font(TapeType.body)
                    .foregroundStyle(TapeTheme.muted)
                Spacer(minLength: TapeTheme.space2)
                Text(L10n.string("smart.playlist.filter.allCollections"))
                    .font(TapeType.monoMeta)
                    .foregroundStyle(TapeTheme.ink)
            }
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
                HStack(spacing: TapeTheme.space3) {
                    ZStack {
                        RoundedRectangle(cornerRadius: TapeTheme.radiusThumb, style: .continuous)
                            .fill(TapeTheme.cream)
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(TapeTheme.ink)
                    }
                    .frame(width: 32, height: 32)
                    .overlay {
                        RoundedRectangle(cornerRadius: TapeTheme.radiusThumb, style: .continuous)
                            .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.string("smart.playlist.filter.menu"))
                            .font(TapeType.body)
                            .foregroundStyle(TapeTheme.muted)
                        Text(filterTitle)
                            .font(TapeType.headline)
                            .foregroundStyle(TapeTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: TapeTheme.space2)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(TapeTheme.faint)
                }
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("smartPlaylistFilterMenu")
        }
    }

    // MARK: - Empty state

    private var emptyCard: some View {
        TapeDashedCard {
            VStack(spacing: TapeTheme.space3) {
                TapeRewardSticker(
                    text: "EMPTY",
                    fill: TapeTheme.violet,
                    foreground: TapeTheme.stickerInk
                )
                Text(L10n.string("smart.playlist.empty.title"))
                    .font(TapeType.title2)
                    .tracking(-0.4)
                    .foregroundStyle(TapeTheme.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("smartPlaylistEmptyState")
                Text(kind.emptyDescription)
                    .font(TapeType.body)
                    .foregroundStyle(TapeTheme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func sectionHeader(_ title: String, kicker: String) -> some View {
        TapeSectionHeader(title: title, kicker: kicker)
            .textCase(nil)
            .padding(.horizontal, TapeTheme.screenPadding)
            .padding(.top, TapeTheme.space3)
            .padding(.bottom, TapeTheme.space1)
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
        HStack(spacing: TapeTheme.space3) {
            MediaArtworkView(item: item, size: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(TapeType.headline)
                    .foregroundStyle(TapeTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                switch kind {
                case .continueListening, .unfinished:
                    if let state, state.position > 0 {
                        TapeProgressBar(progress: progress, height: 6)
                        Text(L10n.format(
                            "smart.playlist.progress",
                            Int(state.position),
                            item.durationText
                        ))
                        .font(TapeType.monoMicro)
                        .foregroundStyle(TapeTheme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                case .finished:
                    Label(
                        L10n.string("smart.playlist.finished.badge"),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(TapeType.caption)
                    .foregroundStyle(TapeTheme.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(TapeTheme.acid, in: Capsule())
                    .overlay { Capsule().strokeBorder(TapeTheme.ink, lineWidth: 1) }
                case .recentlyAdded:
                    Text(L10n.format(
                        "smart.playlist.addedAt",
                        item.addedAt.formatted(date: .abbreviated, time: .omitted)
                    ))
                    .font(TapeType.monoMicro)
                    .foregroundStyle(TapeTheme.faint)
                }

                if let collectionName, !collectionName.isEmpty {
                    Text(collectionName)
                        .font(TapeType.monoMicro)
                        .foregroundStyle(TapeTheme.faint)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: TapeTheme.space1)

            Text(item.durationText)
                .font(TapeType.monoMicro)
                .foregroundStyle(TapeTheme.muted)
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
    }
}

// MARK: - Collection-filtered browse

struct SmartCollectionPickerView: View {
    @Query(sort: \MediaCollection.name)
    private var collections: [MediaCollection]
    @Query(sort: \MediaItem.addedAt, order: .reverse)
    private var allItems: [MediaItem]

    @State private var destinationCollection: MediaCollection?
    @State private var showCollectionItems = false

    private var libraryItems: [MediaItem] {
        allItems.filter { $0.source != .benchmark }
    }

    var body: some View {
        List {
            if collections.isEmpty {
                Section {
                    TapeDashedCard {
                        VStack(spacing: TapeTheme.space3) {
                            TapeRewardSticker(
                                text: "EMPTY",
                                fill: TapeTheme.violet,
                                foreground: TapeTheme.stickerInk
                            )
                            Text(L10n.string("smart.playlist.collections.empty"))
                                .font(TapeType.title2)
                                .tracking(-0.4)
                                .foregroundStyle(TapeTheme.ink)
                                .multilineTextAlignment(.center)
                                .accessibilityIdentifier("smartCollectionEmptyState")
                            Text(L10n.string("smart.playlist.collections.empty.detail"))
                                .font(TapeType.body)
                                .foregroundStyle(TapeTheme.muted)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .tapeRowInsets(6)
                }
            } else {
                Section {
                    ForEach(collections) { collection in
                        Button {
                            destinationCollection = collection
                            showCollectionItems = true
                        } label: {
                            HStack(spacing: TapeTheme.space3) {
                                ZStack {
                                    RoundedRectangle(
                                        cornerRadius: TapeTheme.radiusThumb,
                                        style: .continuous
                                    )
                                    .fill(TapeTheme.violetSoft)
                                    Image(systemName: "folder")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(TapeTheme.ink)
                                }
                                .frame(width: 36, height: 36)
                                .overlay {
                                    RoundedRectangle(
                                        cornerRadius: TapeTheme.radiusThumb,
                                        style: .continuous
                                    )
                                    .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(collection.name)
                                        .font(TapeType.headline)
                                        .foregroundStyle(TapeTheme.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(L10n.format(
                                        "smart.playlist.collectionItemCount",
                                        libraryItems.filter { $0.collectionID == collection.id }.count
                                    ))
                                    .font(TapeType.monoMicro)
                                    .foregroundStyle(TapeTheme.faint)
                                }

                                Spacer(minLength: TapeTheme.space2)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(TapeTheme.faint)
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
                        }
                        .buttonStyle(TapePlainPressStyle())
                        .accessibilityIdentifier("smartCollectionRow-\(collection.name)")
                        .tapeRowInsets(4)
                    }
                } header: {
                    TapeSectionHeader(
                        title: L10n.string("smart.playlist.byCollection"),
                        kicker: "COLLECTIONS"
                    )
                    .textCase(nil)
                    .padding(.horizontal, TapeTheme.screenPadding)
                    .padding(.top, TapeTheme.space3)
                    .padding(.bottom, TapeTheme.space1)
                }
            }
        }
        .listStyle(.plain)
        .tapeScreen()
        .navigationTitle(L10n.string("smart.playlist.byCollection"))
        .tapeNavigationChrome()
        .navigationDestination(isPresented: $showCollectionItems) {
            if let destinationCollection {
                SmartCollectionItemsView(collection: destinationCollection)
            }
        }
    }
}

struct SmartCollectionItemsView: View {
    let collection: MediaCollection

    @Environment(PlaybackSession.self) private var session
    @Query private var allItems: [MediaItem]
    @Query private var playbackStates: [PlaybackState]

    @State private var itemDetailTarget: MediaItem?
    @State private var showItemDetail = false

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
                heroCard
                    .tapeRowInsets(8)
            }

            Section {
                if items.isEmpty {
                    TapeDashedCard {
                        VStack(spacing: TapeTheme.space3) {
                            TapeRewardSticker(
                                text: "EMPTY",
                                fill: TapeTheme.violet,
                                foreground: TapeTheme.stickerInk
                            )
                            Text(L10n.string("smart.playlist.empty.title"))
                                .font(TapeType.title2)
                                .tracking(-0.4)
                                .foregroundStyle(TapeTheme.ink)
                                .multilineTextAlignment(.center)
                                .accessibilityIdentifier("smartCollectionItemsEmptyState")
                            Text(L10n.string("smart.playlist.empty.collection"))
                                .font(TapeType.body)
                                .foregroundStyle(TapeTheme.muted)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .tapeRowInsets(6)
                } else {
                    ForEach(items) { item in
                        Button {
                            itemDetailTarget = item
                            showItemDetail = true
                        } label: {
                            SmartPlaylistItemRow(
                                item: item,
                                state: stateByID[item.id],
                                kind: .recentlyAdded,
                                collectionName: nil
                            )
                        }
                        .buttonStyle(TapePlainPressStyle())
                        .accessibilityIdentifier("smartCollectionItem-\(item.title)")
                        .tapeRowInsets(4)
                    }
                }
            } header: {
                TapeSectionHeader(
                    title: L10n.format("smart.playlist.items", items.count),
                    kicker: "ON THE SHELF"
                )
                .textCase(nil)
                .padding(.horizontal, TapeTheme.screenPadding)
                .padding(.top, TapeTheme.space3)
                .padding(.bottom, TapeTheme.space1)
            }
        }
        .listStyle(.plain)
        .tapeScreen()
        .navigationTitle(collection.name)
        .tapeNavigationChrome()
        .navigationDestination(isPresented: $showItemDetail) {
            if let itemDetailTarget {
                LibraryItemDetailView(item: itemDetailTarget)
            }
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        TapeCard(fill: TapeTheme.acid) {
            VStack(alignment: .leading, spacing: TapeTheme.space3) {
                HStack(alignment: .top, spacing: TapeTheme.space2) {
                    VStack(alignment: .leading, spacing: 5) {
                        TapeKicker(text: "TAPE BOX", color: TapeTheme.ink.opacity(0.62))
                        Text(collection.name)
                            .font(TapeType.title1)
                            .tracking(-0.6)
                            .foregroundStyle(TapeTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: TapeTheme.space2)
                    TapeSticker(
                        text: "\(items.count) 条",
                        fill: TapeTheme.card,
                        foreground: TapeTheme.ink,
                        angle: 4
                    )
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: TapeTheme.space2) {
                        playAllButton
                        shuffleButton
                    }
                    VStack(spacing: TapeTheme.space2) {
                        playAllButton
                        shuffleButton
                    }
                }
            }
        }
    }

    private var playAllButton: some View {
        Button {
            session.play(items: items)
        } label: {
            Label(
                L10n.format("smart.playlist.playAll", items.count),
                systemImage: "play.fill"
            )
        }
        .buttonStyle(TapePrimaryButtonStyle())
        .disabled(items.isEmpty)
        .opacity(items.isEmpty ? 0.55 : 1)
        .accessibilityIdentifier("smartCollectionPlayAllButton")
    }

    private var shuffleButton: some View {
        Button {
            session.play(items: items, shuffle: true)
        } label: {
            Label(L10n.string("smart.playlist.shuffle"), systemImage: "shuffle")
        }
        .buttonStyle(TapeSecondaryButtonStyle())
        .disabled(items.isEmpty)
        .opacity(items.isEmpty ? 0.55 : 1)
        .accessibilityIdentifier("smartCollectionShuffleButton")
    }
}
