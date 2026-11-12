import Foundation
import SwiftUI
import SwiftData
import UIKit
import LocalPodKit

private enum LibraryDestination {
    case item(MediaItem)
    case collection(MediaCollection)
    case trash
}

struct LibraryView: View {
    private enum Scope: String, CaseIterable, Identifiable {
        case items = "条目"
        case collections = "合集"
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .items: L10n.string("library.scope.items")
            case .collections: L10n.string("library.scope.collections")
            }
        }

        /// Stable token persisted in AppSettingsStore.libraryScope. The
        /// rawValue is a display string and must not be stored.
        var storedValue: LibraryScopeToken {
            switch self {
            case .items: .items
            case .collections: .collections
            }
        }

        init(storedValue: LibraryScopeToken) {
            self = storedValue == .collections ? .collections : .items
        }
    }

    private enum ItemFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case audio = "音频"
        case video = "视频"
        case missing = "缺失"
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .all: L10n.string("library.filter.all")
            case .audio: L10n.string("library.filter.audio")
            case .video: L10n.string("library.filter.video")
            case .missing: L10n.string("library.filter.missing")
            }
        }
    }

    private enum ItemSort: String, CaseIterable, Identifiable {
        case recent = "最近添加"
        case title = "标题"
        case size = "大小"
        case duration = "时长"
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .recent: L10n.string("library.sort.recent")
            case .title: L10n.string("library.sort.title")
            case .size: L10n.string("library.sort.size")
            case .duration: L10n.string("library.sort.duration")
            }
        }
    }

    @Environment(PlaybackSession.self) private var session
    @Environment(AppIntentRouter.self) private var intentRouter
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \MediaItem.addedAt, order: .reverse)
    private var allItems: [MediaItem]

    @Query(sort: \MediaCollection.name)
    private var collections: [MediaCollection]

    @Query(sort: \Playlist.sortOrder)
    private var playlists: [Playlist]

    @Query(sort: \TrashItem.deletedAt, order: .reverse)
    private var trashItems: [TrashItem]

    /// Persisted through the settings store so the pane chosen before a
    /// relaunch opens again (owner: selecting 合集 always came back to 条目).
    private var scope: Scope {
        get { Scope(storedValue: session.settings.libraryScope) }
        nonmutating set { session.settings.libraryScope = newValue.storedValue }
    }
    @State private var filter: ItemFilter = .all
    @State private var sort: ItemSort = .recent
    @State private var searchText = ""
    @State private var showSettings = false
    @State private var destination: LibraryDestination?
    @State private var showDestination = false

    private var libraryItems: [MediaItem] {
        allItems.filter { $0.source != .benchmark }
    }

    private var displayedItems: [MediaItem] {
        var items = libraryItems
        switch filter {
        case .all:
            break
        case .audio:
            items = items.filter { !$0.kind.isVideo }
        case .video:
            items = items.filter(\.kind.isVideo)
        case .missing:
            items = items.filter(\.isMissing)
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            items = items.filter {
                $0.title.localizedStandardContains(query)
                    || ($0.folderName ?? "").localizedStandardContains(query)
                    || $0.relativeFolderPath.localizedStandardContains(query)
                    || $0.originalFileName.localizedStandardContains(query)
            }
        }

        switch sort {
        case .recent:
            items.sort { $0.addedAt > $1.addedAt }
        case .title:
            items.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .size:
            items.sort { $0.byteSize > $1.byteSize }
        case .duration:
            items.sort { ($0.durationSeconds ?? 0) > ($1.durationSeconds ?? 0) }
        }
        return items
    }

    private var collectionRows: [CollectionRow] {
        collections.map { collection in
            let items = libraryItems.filter { $0.collectionID == collection.id }
            return CollectionRow(
                collection: collection,
                itemCount: items.count,
                byteCount: items.reduce(0) { $0 + $1.byteSize },
                duration: items.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
            )
        }
    }

    private var totalBytes: Int64 {
        libraryItems.reduce(0) { $0 + $1.byteSize }
    }

    private var totalDuration: Double {
        libraryItems.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    heroCard
                        .tapeRowInsets(8)
                }

                Section {
                    scopeChips
                        .tapeRowInsets(4)
                }

                if scope == .items {
                    itemsSection
                } else {
                    collectionsSection
                }

                trashSection
            }
            .listStyle(.plain)
            .tapeScreen()
            .navigationTitle("资料库")
            .tapeNavigationChrome()
            .navigationDestination(isPresented: $showDestination) {
                switch destination {
                case .collection(let collection):
                    LibraryCollectionDetailView(collection: collection)
                case .item(let item):
                    LibraryItemDetailView(item: item)
                case .trash:
                    TrashView()
                case nil:
                    EmptyView()
                }
            }
            // The owner's repro: flipping between tabs made the library's
            // search field jump. The old `.searchable` field is hosted by the
            // system search bar, which on iOS 26+ docks at the bottom against
            // the hidden system tab bar and the custom TapeTabBar sibling and
            // re-docks on every tab switch. A custom field pinned in a top
            // safe-area inset sits outside the scroll view entirely, so its
            // frame cannot depend on tab or scroll state.
            .safeAreaInset(edge: .top, spacing: 0) {
                searchField
                    .padding(.horizontal, TapeTheme.screenPadding)
                    .padding(.top, TapeTheme.space2)
                    .padding(.bottom, TapeTheme.space1)
                    .frame(maxWidth: .infinity)
                    // The inset overlays the scroll view, so rows would
                    // otherwise bleed through around the field's card. A
                    // cream band (same color as the nav bar above) occludes
                    // the scrolling content behind the pinned anchor.
                    .background(TapeTheme.cream)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("设置", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("librarySettingsButton")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        PlaylistListView()
                    } label: {
                        Label("播放列表", systemImage: "music.note.list")
                    }
                    .accessibilityIdentifier("libraryPlaylistsLink")

                    Menu {
                        Picker("筛选", selection: $filter) {
                            ForEach(ItemFilter.allCases) { filter in
                                Text(filter.displayName).tag(filter)
                            }
                        }
                        Divider()
                        Picker("排序", selection: $sort) {
                            ForEach(ItemSort.allCases) { sort in
                                Text(sort.displayName).tag(sort)
                            }
                        }
                    } label: {
                        Label("筛选与排序", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityIdentifier("libraryFilterMenu")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            // App Intents (Siri/Shortcuts) and localpod:// URL opens stage a
            // request before or after this view appears; `.task(id:)` covers
            // both because it runs on first appearance and on id changes.
            .task(id: intentRouter.collectionRequest) {
                handlePendingCollectionRequestIfNeeded()
            }
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: TapeTheme.space3) {
            HStack(alignment: .top, spacing: TapeTheme.space2) {
                VStack(alignment: .leading, spacing: 5) {
                    TapeKicker(text: "YOUR MIXTAPE", color: TapeTheme.ink.opacity(0.62))
                    HStack(spacing: TapeTheme.space2) {
                        Text("我的磁带盒")
                            .font(TapeType.display)
                            .tracking(-0.9)
                            .foregroundStyle(TapeTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        TapeSticker(text: "本地磁带", fill: TapeTheme.coral, angle: 5)
                    }
                }
                Spacer(minLength: TapeTheme.space2)
                heroPlayButton
            }

            Text("\(libraryItems.count) 条 · \(collections.count) 个合集 · \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))")
                .font(TapeType.monoMeta)
                .foregroundStyle(TapeTheme.ink.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("libraryStatsText")

            HStack(spacing: TapeTheme.space2) {
                heroStat(value: "\(libraryItems.count)", label: "条目")
                heroStat(value: "\(collections.count)", label: "合集")
                heroStat(value: formatDuration(totalDuration), label: "总时长")
                heroStat(
                    value: ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file),
                    label: "总大小"
                )
            }
        }
        .padding(TapeTheme.space4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: TapeTheme.radiusCard, style: .continuous)
                .fill(TapeTheme.acid)
                .shadow(color: TapeTheme.ink, radius: 0, x: 4, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: TapeTheme.radiusCard, style: .continuous)
                .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
        }
    }

    /// The hero button mirrors the player screen exactly: it drives and
    /// reflects the shared PlaybackController, not a "play newest" shortcut.
    /// Playing → pause toggle with the pause glyph; otherwise resume whatever
    /// the queue holds via togglePlayPause, which for a paused/ready item
    /// resumes it and for an ended item restarts it from zero — the same
    /// semantics as the player's own button. A fresh launch with a persisted
    /// queue but nothing loaded yet loads the queue's current entry first
    /// (`resumeForShortcut`); if the button shows at all there is always
    /// something it can start.
    @ViewBuilder
    private var heroPlayButton: some View {
        let hasCurrent = session.playback.currentItem != nil
        let hasQueue = session.queue.currentItemID != nil
        if hasCurrent || hasQueue {
            Button {
                if session.playback.currentItem == nil {
                    session.resumeForShortcut()
                } else {
                    session.playback.togglePlayPause()
                }
            } label: {
                Image(systemName: session.playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .bold))
            }
            .buttonStyle(TapeIconButtonStyle(diameter: 44, fill: TapeTheme.card))
            .accessibilityIdentifier("libraryHeroPlayButton")
            .accessibilityLabel(session.playback.isPlaying ? "暂停" : "播放")
            .accessibilityHint(session.playback.isPlaying ? "暂停当前音频" : "继续播放当前音频")
        }
    }

    private func heroStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(TapeFont.mono(12, weight: .semibold, relativeTo: .caption))
                .foregroundStyle(TapeTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(TapeType.captionSmall)
                .foregroundStyle(TapeTheme.ink.opacity(0.62))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            TapeTheme.card.opacity(0.55),
            in: RoundedRectangle(cornerRadius: TapeTheme.radiusThumb)
        )
        .overlay {
            RoundedRectangle(cornerRadius: TapeTheme.radiusThumb)
                .strokeBorder(TapeTheme.ink.opacity(0.35), lineWidth: 1)
        }
    }

    // MARK: - Search

    /// App-owned search anchor: same card language as the list rows, always
    /// between the nav bar and the scroll viewport, never re-docked.
    private var searchField: some View {
        HStack(spacing: TapeTheme.space2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TapeTheme.faint)
            TextField("搜索标题或文件夹", text: $searchText)
                .font(TapeType.body)
                .foregroundStyle(TapeTheme.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                // The identifier sits on the TextField itself so tests read
                // its value (the typed text) directly.
                .accessibilityIdentifier("librarySearchField")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(TapeTheme.faint)
                }
                .buttonStyle(TapePlainPressStyle())
                .accessibilityIdentifier("librarySearchClearButton")
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, TapeTheme.space3)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: TapeTheme.radiusThumb, style: .continuous)
                .fill(TapeTheme.card)
                .shadow(color: TapeTheme.ink, radius: 0, x: 2, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: TapeTheme.radiusThumb, style: .continuous)
                .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
        }
    }

    // MARK: - Scope

    private var scopeChips: some View {
        HStack(spacing: TapeTheme.space2) {
            ForEach(Scope.allCases) { option in
                TapeChip(text: option.displayName, isSelected: scope == option) {
                    withAnimation(TapeTheme.spring) { scope = option }
                }
                .accessibilityIdentifier("libraryScope-\(option.rawValue)")
            }
            Spacer(minLength: TapeTheme.space2)
            Text(scope == .items
                ? "\(displayedItems.count) 条"
                : "\(collectionRows.count) 个")
                .font(TapeType.monoMicro)
                .foregroundStyle(TapeTheme.faint)
        }
    }

    // MARK: - Items

    @ViewBuilder
    private var itemsSection: some View {
        Section {
            if displayedItems.isEmpty {
                emptyCard(
                    sticker: "EMPTY",
                    title: libraryItems.isEmpty ? "资料库为空" : "没有匹配的条目",
                    message: libraryItems.isEmpty
                        ? "去「导入」选择一个文件夹开始。"
                        : "调整搜索或筛选条件。",
                    identifier: "libraryEmptyState"
                )
                .tapeRowInsets(6)
            } else {
                ForEach(displayedItems) { item in
                    Button {
                        destination = .item(item)
                        showDestination = true
                    } label: {
                        LibraryItemRow(item: item) {
                            session.play(item: item)
                        }
                    }
                    .buttonStyle(TapePlainPressStyle())
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("libraryItem-\(item.title)")
                    .tapeRowInsets(4)
                    .contextMenu {
                        Button("播放") {
                            session.play(item: item)
                        }
                        Button("播放下一首") {
                            session.playNext(itemID: item.id)
                        }
                        Button("加入队列") {
                            session.enqueue(itemID: item.id)
                        }
                        if !playlists.isEmpty {
                            Menu("加入播放列表") {
                                ForEach(playlists) { playlist in
                                    Button(playlist.name) {
                                        _ = session.playlists.add(
                                            itemID: item.id,
                                            to: playlist
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } header: {
            libraryHeader(
                "条目 · \(displayedItems.count)",
                kicker: "ON THE SHELF"
            )
        }
    }

    // MARK: - Collections

    @ViewBuilder
    private var collectionsSection: some View {
        Section {
            if collectionRows.isEmpty {
                emptyCard(
                    sticker: "NO TAPES",
                    title: "还没有合集",
                    message: "导入一个文件夹后会自动生成合集。",
                    identifier: "collectionEmptyState"
                )
                .tapeRowInsets(6)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: TapeTheme.space3),
                        GridItem(.flexible(), spacing: TapeTheme.space3)
                    ],
                    spacing: TapeTheme.space3
                ) {
                    ForEach(Array(collectionRows.enumerated()), id: \.element.id) { index, row in
                        Button {
                            destination = .collection(row.collection)
                            showDestination = true
                        } label: {
                            CollectionTile(row: row, index: index)
                        }
                        .buttonStyle(TapePlainPressStyle())
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("collectionRow-\(row.collection.name)")
                    }
                }
                .tapeRowInsets(4)
            }
        } header: {
            libraryHeader(
                "合集 · \(collectionRows.count)",
                kicker: "TAPE BOXES"
            )
        }
    }

    // MARK: - Trash

    @ViewBuilder
    private var trashSection: some View {
        Section {
            Button {
                destination = .trash
                showDestination = true
            } label: {
                HStack(spacing: TapeTheme.space3) {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(TapeTheme.ink)
                        .frame(width: 34, height: 34)
                        .background(TapeTheme.cream, in: RoundedRectangle(
                            cornerRadius: TapeTheme.radiusThumb,
                            style: .continuous
                        ))
                        .overlay {
                            RoundedRectangle(cornerRadius: TapeTheme.radiusThumb, style: .continuous)
                                .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
                        }
                    Text(L10n.string("trash.section"))
                        .font(TapeType.headline)
                        .foregroundStyle(TapeTheme.ink)
                    Spacer(minLength: TapeTheme.space2)
                    Text(L10n.format("trash.count", trashItems.count))
                        .font(TapeType.monoMicro)
                        .foregroundStyle(TapeTheme.muted)
                        .accessibilityIdentifier("trashCountText")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(TapeTheme.faint)
                }
                .padding(TapeTheme.space3)
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
            .accessibilityIdentifier("trashSectionLink")
            .tapeRowInsets(4)
        }
    }

    // MARK: - Shared chrome

    private func libraryHeader(_ title: String, kicker: String) -> some View {
        TapeSectionHeader(title: title, kicker: kicker)
            .textCase(nil)
            .padding(.horizontal, TapeTheme.screenPadding)
            .padding(.top, TapeTheme.space3)
            .padding(.bottom, TapeTheme.space1)
    }

    private func emptyCard(
        sticker: String,
        title: String,
        message: String,
        identifier: String
    ) -> some View {
        TapeDashedCard {
            VStack(spacing: TapeTheme.space3) {
                TapeRewardSticker(text: sticker, fill: TapeTheme.violet, foreground: TapeTheme.stickerInk)
                Text(title)
                    .font(TapeType.title2)
                    .tracking(-0.4)
                    .foregroundStyle(TapeTheme.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier(identifier)
                Text(message)
                    .font(TapeType.body)
                    .foregroundStyle(TapeTheme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Pushes the requested collection when it exists; otherwise falls back to
    /// the collections scope with the requested name pre-filled in search.
    private func handlePendingCollectionRequestIfNeeded() {
        guard let request = intentRouter.collectionRequest else { return }
        let key = MediaCollection.normalizedKey(for: request.name)
        if let collection = collections.first(where: { $0.nameKey == key }) {
            destination = .collection(collection)
            showDestination = true
        } else {
            scope = .collections
            searchText = request.name
        }
        intentRouter.consumeCollectionRequest(id: request.id)
    }
}

// MARK: - Collection row + tile

private struct CollectionRow: Identifiable {
    let collection: MediaCollection
    let itemCount: Int
    let byteCount: Int64
    let duration: Double

    var id: UUID { collection.id }

    var metaText: String {
        "\(itemCount) 条 · \(formatDuration(duration)) · "
            + ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

private struct CollectionTile: View {
    let row: CollectionRow
    let index: Int

    private var fill: Color {
        switch index % 6 {
        case 0: TapeTheme.acid
        case 1: TapeTheme.violetSoft
        case 2: TapeTheme.peach
        case 3: TapeTheme.coral
        case 4: TapeTheme.card
        default: TapeTheme.ink
        }
    }

    private var ink: Color {
        if index % 6 == 3 || index % 6 == 5 {
            return TapeTheme.stickerInk
        }
        return TapeTheme.ink
    }

    private var monogram: String {
        String(row.collection.name.prefix(1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TapeTheme.space2) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fill)
                if index % 6 == 4 {
                    // Paper grid variant.
                    Canvas { context, size in
                        var x: CGFloat = 0
                        while x < size.width {
                            var y: CGFloat = 0
                            while y < size.height {
                                context.fill(
                                    Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)),
                                    with: .color(TapeTheme.ink.opacity(0.25))
                                )
                                y += 16
                            }
                            x += 16
                        }
                    }
                    .padding(4)
                }
                Text(monogram)
                    .font(TapeFont.display(40, weight: .bold, relativeTo: .largeTitle))
                    .foregroundStyle(ink)
                VStack {
                    HStack {
                        Spacer()
                        TapeSticker(
                            text: "\(row.itemCount)",
                            fill: TapeTheme.card,
                            foreground: TapeTheme.ink,
                            angle: index.isMultiple(of: 2) ? 4 : -4
                        )
                    }
                    Spacer()
                }
                .padding(8)
            }
            .frame(height: 104)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
            }
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fill)
                    .shadow(color: TapeTheme.ink, radius: 0, x: 2, y: 2)
            }

            Text(row.collection.name)
                .font(TapeType.headline)
                .foregroundStyle(TapeTheme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(row.metaText)
                .font(TapeType.monoMicro)
                .foregroundStyle(TapeTheme.faint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rotationEffect(.degrees(index.isMultiple(of: 2) ? -0.5 : 0.5))
    }
}

// MARK: - Item rows

struct LibraryItemRow: View {
    let item: MediaItem
    /// When provided, the trailing tape button plays this row directly —
    /// the owner asked for one-tap playback from list rows without opening
    /// the detail page. Rows without it stay navigation-only.
    var onPlay: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: TapeTheme.space3) {
            MediaArtworkView(item: item, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(TapeType.headline)
                        .foregroundStyle(TapeTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if item.isMissing {
                        TapeSticker(text: "缺失", fill: TapeTheme.coral, angle: -4)
                    }
                }
                Text(subtitle)
                    .font(TapeType.monoMicro)
                    .foregroundStyle(TapeTheme.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Text(item.durationText)
                .font(TapeType.monoMicro)
                .foregroundStyle(TapeTheme.muted)
            if let onPlay, !item.isMissing {
                Button {
                    onPlay()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(TapeTheme.ink)
                        .frame(width: 28, height: 28)
                        .background(TapeTheme.acid, in: Circle())
                        .overlay { Circle().strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke) }
                }
                .buttonStyle(TapePlainPressStyle())
                // Own the tap: without a contentShape the 28 pt circle loses
                // its empty quarters to the surrounding Button, which would
                // open the detail page instead of playing.
                .contentShape(Circle())
            }
        }
        .padding(.horizontal, TapeTheme.space3)
        .padding(.vertical, 9)
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

    private var subtitle: String {
        var parts = [item.kind.displayName]
        if !item.relativeFolderPath.isEmpty {
            parts.append(item.relativeFolderPath)
        } else if let folder = item.folderName {
            parts.append(folder)
        }
        parts.append(ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file))
        return parts.joined(separator: " · ")
    }
}

// MARK: - Collection detail

struct LibraryCollectionDetailView: View {
    let collection: MediaCollection

    @Environment(PlaybackSession.self) private var session
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \MediaItem.relativeFolderPath)
    private var allItems: [MediaItem]

    @State private var itemDetailTarget: MediaItem?
    @State private var showItemDetail = false
    @State private var editMode: EditMode = .inactive

    private var items: [MediaItem] {
        allItems.filter { $0.collectionID == collection.id }
    }

    /// Items in the collection's persisted order. Manual mode follows the
    /// per-item `collectionPosition`; the other modes are pure functions of
    /// the source path/title/date, so they never rewrite stored rows.
    private var sortedItems: [MediaItem] {
        CollectionOrdering.sorted(items, by: collection.sortMode)
    }

    private var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.byteSize }
    }

    private var totalDuration: Double {
        items.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: TapeTheme.space3) {
                    HStack {
                        TapeSticker(text: "TAPE BOX", fill: TapeTheme.violet, foreground: TapeTheme.stickerInk)
                        Spacer()
                        Text("\(items.count) 条")
                            .font(TapeType.monoMeta)
                            .foregroundStyle(TapeTheme.ink.opacity(0.65))
                    }
                    Text(collection.name)
                        .font(TapeType.title1)
                        .tracking(-0.6)
                        .foregroundStyle(TapeTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(formatDuration(totalDuration)) · \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))")
                        .font(TapeType.monoMeta)
                        .foregroundStyle(TapeTheme.ink.opacity(0.7))

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
                .padding(TapeTheme.space4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: TapeTheme.radiusCard, style: .continuous)
                        .fill(TapeTheme.acid)
                        .shadow(color: TapeTheme.ink, radius: 0, x: 4, y: 4)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: TapeTheme.radiusCard, style: .continuous)
                        .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
                }
                .tapeRowInsets(8)
            }

            Section {
                TapeCard {
                    VStack(spacing: TapeTheme.space2) {
                        detailStat(label: "条目", value: "\(items.count) 条")
                        TapeHairline()
                        detailStat(
                            label: "总大小",
                            value: ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
                        )
                        TapeHairline()
                        detailStat(label: "总时长", value: formatDuration(totalDuration))
                    }
                }
                .tapeRowInsets(6)
            } header: {
                TapeSectionHeader(title: "统计", kicker: "CASE FILE")
                    .textCase(nil)
                    .padding(.horizontal, TapeTheme.screenPadding)
                    .padding(.top, TapeTheme.space3)
            }

            Section {
                ForEach(sortedItems) { item in
                    Button {
                        itemDetailTarget = item
                        showItemDetail = true
                    } label: {
                        LibraryItemRow(item: item) {
                            session.play(item: item)
                        }
                    }
                    .buttonStyle(TapePlainPressStyle())
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("collectionItem-\(item.title)")
                    .tapeRowInsets(4)
                }
                .onMove { source, destination in
                    moveItems(fromOffsets: source, toOffset: destination)
                }
            } header: {
                TapeSectionHeader(
                    title: "条目 · \(items.count)",
                    kicker: "ON THE SHELF"
                )
                .textCase(nil)
                .padding(.horizontal, TapeTheme.screenPadding)
                .padding(.top, TapeTheme.space3)
            }
        }
        .listStyle(.plain)
        .tapeScreen()
        .environment(\.editMode, $editMode)
        .navigationTitle(collection.name)
        .tapeNavigationChrome()
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                sortMenu
                if collection.sortMode == .manual {
                    Button(editMode == .active ? "完成排序" : "拖动排序") {
                        withAnimation {
                            editMode = editMode == .active ? .inactive : .active
                        }
                    }
                    .font(TapeType.bodySmall)
                    .accessibilityIdentifier("collectionReorderButton")
                }
            }
        }
        .navigationDestination(isPresented: $showItemDetail) {
            if let itemDetailTarget {
                LibraryItemDetailView(item: itemDetailTarget)
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("排序方式", selection: sortModeBinding) {
                ForEach(CollectionSortMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
        } label: {
            Label("排序", systemImage: "arrow.up.arrow.down")
        }
        .accessibilityIdentifier("collectionSortMenu")
    }

    private var sortModeBinding: Binding<CollectionSortMode> {
        Binding(
            get: { collection.sortMode },
            set: { newMode in
                // Entering manual mode freezes the order the user is looking
                // at, so the first drag starts from the visible sequence.
                if newMode == .manual {
                    let current = CollectionOrdering.sorted(
                        items,
                        by: collection.sortMode
                    )
                    CollectionOrdering.assignManualPositions(current)
                }
                collection.sortMode = newMode
                editMode = .inactive
                try? modelContext.save()
            }
        )
    }

    private func moveItems(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard collection.sortMode == .manual else { return }
        let reordered = CollectionOrdering.moving(
            sortedItems,
            fromOffsets: source,
            toOffset: destination
        )
        CollectionOrdering.assignManualPositions(reordered)
        try? modelContext.save()
    }

    private var playAllButton: some View {
        Button {
            session.play(items: sortedItems)
        } label: {
            Label("播放全部（\(items.count)）", systemImage: "play.fill")
        }
        .buttonStyle(TapePrimaryButtonStyle())
        .accessibilityIdentifier("collectionPlayAllButton")
    }

    private var shuffleButton: some View {
        Button {
            session.play(items: sortedItems, shuffle: true)
        } label: {
            Label("随机播放", systemImage: "shuffle")
        }
        .buttonStyle(TapeSecondaryButtonStyle())
        .accessibilityIdentifier("collectionShuffleButton")
    }

    private func detailStat(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(TapeType.body)
                .foregroundStyle(TapeTheme.muted)
            Spacer(minLength: TapeTheme.space2)
            Text(value)
                .font(TapeType.monoMeta)
                .foregroundStyle(TapeTheme.ink)
        }
    }
}

// MARK: - Item detail

struct LibraryItemDetailView: View {
    let item: MediaItem

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(PlaybackSession.self) private var session

    @Query(sort: \Playlist.sortOrder)
    private var playlists: [Playlist]

    @State private var showDeleteConfirmation = false
    @State private var showPlaylistPicker = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @State private var playbackStatus: PlaybackStatus = .notStarted

    private var infoRows: [(String, String)] {
        var rows: [(String, String)] = [
            ("标题", item.title),
            ("类型", item.kind.displayName),
            ("格式", item.fileExtension.uppercased()),
            ("大小", ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file)),
            ("时长", item.durationText)
        ]
        if let folder = item.folderName {
            rows.append(("合集", folder))
        }
        if !item.relativeFolderPath.isEmpty {
            rows.append(("文件夹内路径", item.relativeFolderPath))
        }
        rows.append((
            "存储方式",
            item.isLinked ? "原地读取（不复制）" : "已复制到 App"
        ))
        rows.append(("来源", item.source.displayName))
        rows.append(("添加时间", item.addedAt.formatted(date: .abbreviated, time: .shortened)))
        if let fingerprint = item.fingerprint {
            rows.append(("SHA-256", String(fingerprint.prefix(16)) + "…"))
        }
        return rows
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: TapeTheme.space3) {
                    MediaArtworkView(item: item, size: 180)
                    HStack(spacing: TapeTheme.space2) {
                        TapeSticker(
                            text: item.kind.isVideo ? "VIDEO · AUDIO ONLY" : "AUDIO",
                            fill: item.kind.isVideo ? TapeTheme.peach : TapeTheme.acid,
                            foreground: TapeTheme.ink,
                            angle: -3
                        )
                        if item.isMissing {
                            TapeSticker(text: "缺失", fill: TapeTheme.coral, angle: 4)
                        }
                    }

                    // Primary actions sit with the hero — the owner moved
                    // them up from the bottom of the page so playing or
                    // queueing never needs a scroll. Full-width rows keep the
                    // 44 pt hit target and the tape button language.
                    if !item.isMissing {
                        Button {
                            play()
                        } label: {
                            Label(
                                item.kind.isVideo ? "播放音频（视频仅音轨）" : "播放音频",
                                systemImage: "play.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(TapePrimaryButtonStyle())
                        .accessibilityIdentifier("detailPlayButton")

                        HStack(spacing: TapeTheme.space2) {
                            Button {
                                session.playNext(itemID: item.id)
                                infoMessage = L10n.string("library.queue.nextAdded")
                            } label: {
                                Label("播放下一首", systemImage: "text.line.first.and.arrowtriangle.forward")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(TapeSecondaryButtonStyle())
                            .accessibilityIdentifier("detailPlayNextButton")

                            Button {
                                session.enqueue(itemID: item.id)
                                infoMessage = L10n.string("library.queue.enqueued")
                            } label: {
                                Label("加入队列", systemImage: "text.append")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(TapeSecondaryButtonStyle())
                            .accessibilityIdentifier("detailEnqueueButton")
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, TapeTheme.space2)
                .tapeRowInsets(8)
            }

            Section {
                TapeCard {
                    VStack(spacing: TapeTheme.space2) {
                        ForEach(Array(infoRows.enumerated()), id: \.offset) { index, row in
                            HStack(alignment: .firstTextBaseline, spacing: TapeTheme.space2) {
                                Text(row.0)
                                    .font(TapeType.body)
                                    .foregroundStyle(TapeTheme.muted)
                                Spacer(minLength: TapeTheme.space2)
                                Text(row.1)
                                    .font(TapeType.monoMeta)
                                    .foregroundStyle(TapeTheme.ink)
                                    .multilineTextAlignment(.trailing)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if index < infoRows.count - 1 {
                                TapeHairline()
                            }
                        }
                        if item.isMissing {
                            TapeHairline()
                            Text("媒体文件缺失。重新导入相同内容可重链此条目。")
                                .font(TapeType.caption)
                                .foregroundStyle(TapeTheme.coral)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .tapeRowInsets(6)
            } header: {
                detailHeader("信息", kicker: "CASE FILE")
            }

            Section {
                TapeCard {
                    Text(
                        item.isLinked
                            ? item.linkedSourceRelativePath
                            : item.relativePath
                    )
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(TapeTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if item.isLinked {
                        Text("文件保留在原文件夹中，App 只读取，不复制。")
                            .font(TapeType.captionSmall)
                            .foregroundStyle(TapeTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tapeRowInsets(6)
            } header: {
                detailHeader("存储路径", kicker: "ON DISK")
            }

            Section {
                TapeCard {
                    VStack(alignment: .leading, spacing: TapeTheme.space3) {
                        HStack(alignment: .firstTextBaseline, spacing: TapeTheme.space2) {
                            Text("当前状态")
                                .font(TapeType.body)
                                .foregroundStyle(TapeTheme.ink)
                            Spacer(minLength: TapeTheme.space2)
                            TapeSticker(
                                text: playbackStatus.displayName,
                                fill: playbackStatus == .finished
                                    ? TapeTheme.acid
                                    : TapeTheme.cream,
                                angle: -2
                            )
                            .accessibilityIdentifier("detailPlaybackStatusText")
                        }

                        if playbackStatus == .finished {
                            Button {
                                markUnfinished()
                            } label: {
                                Label("标记为未完成", systemImage: "arrow.uturn.backward")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(TapeSecondaryButtonStyle())
                            .accessibilityIdentifier("detailMarkUnfinishedButton")
                        } else {
                            Button {
                                markFinished()
                            } label: {
                                Label("标记为已完成", systemImage: "checkmark.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(TapeSecondaryButtonStyle())
                            .accessibilityIdentifier("detailMarkFinishedButton")
                        }

                        Button(role: .destructive) {
                            resetProgress()
                        } label: {
                            Label("重置播放进度", systemImage: "gobackward")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(TapeSecondaryButtonStyle())
                        .accessibilityIdentifier("detailResetProgressButton")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .tapeRowInsets(6)
            } header: {
                detailHeader("播放状态", kicker: "STATUS")
            }

            Section {
                VStack(spacing: TapeTheme.space2) {
                    if playlists.isEmpty {
                        Text("还没有播放列表。在资料库右上角进入「播放列表」创建。")
                            .font(TapeType.caption)
                            .foregroundStyle(TapeTheme.muted)
                            .multilineTextAlignment(.center)
                            .padding(.top, TapeTheme.space1)
                    } else {
                        Button {
                            showPlaylistPicker = true
                        } label: {
                            Label("加入播放列表", systemImage: "music.note.list")
                        }
                        .buttonStyle(TapeSecondaryButtonStyle())
                        .accessibilityIdentifier("detailAddToPlaylistMenu")
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("删除条目", systemImage: "trash")
                    }
                    .buttonStyle(TapeDestructiveButtonStyle())
                    .accessibilityIdentifier("detailDeleteButton")
                }
                .tapeRowInsets(6)
            }

            if let infoMessage {
                Section {
                    TapeCard(fill: TapeTheme.acid) {
                        Text(infoMessage)
                            .font(TapeType.body)
                            .foregroundStyle(TapeTheme.ink)
                            .accessibilityIdentifier("detailQueueInfoText")
                    }
                    .tapeRowInsets(6)
                }
            }

            if let errorMessage {
                Section {
                    TapeCard(fill: TapeTheme.coral) {
                        Text(errorMessage)
                            .font(TapeType.body)
                            .foregroundStyle(TapeTheme.stickerInk)
                    }
                    .tapeRowInsets(6)
                } header: {
                    detailHeader("错误", kicker: "TROUBLE")
                }
            }
        }
        .listStyle(.plain)
        .tapeScreen()
        .navigationTitle(item.title)
        .tapeNavigationChrome()
        .sheet(isPresented: $showPlaylistPicker) {
            NavigationStack {
                List(playlists) { playlist in
                    Button(playlist.name) {
                        if session.playlists.add(itemID: item.id, to: playlist) {
                            infoMessage = L10n.format(
                                "library.playlist.added",
                                playlist.name
                            )
                        } else {
                            infoMessage = L10n.format(
                                "library.playlist.alreadyContains",
                                playlist.name
                            )
                        }
                        showPlaylistPicker = false
                    }
                    .buttonStyle(TapePlainPressStyle())
                    .accessibilityIdentifier("addToPlaylistOption-\(playlist.name)")
                    .tapeRowInsets(4)
                }
                .listStyle(.plain)
                .tapeScreen()
                .navigationTitle("加入播放列表")
                .tapeNavigationChrome()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showPlaylistPicker = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear { refreshPlaybackStatus() }
        .alert("删除这个条目？", isPresented: $showDeleteConfirmation) {
            Button("移到回收站", role: .destructive) {
                deleteItem()
            }
            .accessibilityIdentifier("detailDeleteConfirmButton")
            Button("取消", role: .cancel) {}
        } message: {
            Text("条目会从资料库移除，并在回收站保留 \(L10n.trashRetentionDays) 天，期间可以恢复；彻底删除时才释放 \(ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file))。")
        }
    }

    private func detailHeader(_ title: String, kicker: String) -> some View {
        TapeSectionHeader(title: title, kicker: kicker)
            .textCase(nil)
            .padding(.horizontal, TapeTheme.screenPadding)
            .padding(.top, TapeTheme.space3)
    }

    @discardableResult
    private func play() -> Bool {
        guard !item.isMissing else {
            errorMessage = L10n.format(
                "error.library.fileMissing",
                item.isLinked ? item.linkedSourceRelativePath : item.relativePath
            )
            return false
        }
        // Linked items have no sandbox URL; PlaybackSession resolves their
        // security scope and reports a missing source through lastError.
        session.play(item: item)
        if let sessionError = session.lastError {
            errorMessage = sessionError
            return false
        }
        return true
    }

    private func refreshPlaybackStatus() {
        playbackStatus = (try? PlaybackProgressStore(context: modelContext)
            .status(for: item.id)) ?? .notStarted
    }

    private func markFinished() {
        do {
            try PlaybackProgressStore(context: modelContext).markFinished(
                itemID: item.id,
                duration: item.durationSeconds ?? 0
            )
            refreshPlaybackStatus()
            infoMessage = "已标记为已完成。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func markUnfinished() {
        do {
            try PlaybackProgressStore(context: modelContext)
                .markUnfinished(itemID: item.id)
            refreshPlaybackStatus()
            infoMessage = "已标记为未完成。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetProgress() {
        do {
            try PlaybackProgressStore(context: modelContext)
                .resetProgress(itemID: item.id)
            refreshPlaybackStatus()
            infoMessage = "播放进度已重置。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteItem() {
        let itemID = item.id
        do {
            let service = LibraryService(storage: .live)
            _ = try service.delete(item, in: modelContext)
            // The persisted queue/playlist rows were cleaned by the service;
            // keep the in-memory session consistent too.
            session.handleDeletedItem(itemID)
            dismiss()
        } catch {
            errorMessage = L10n.format(
                "error.library.deleteFailed",
                error.localizedDescription
            )
        }
    }
}

// MARK: - Artwork

struct MediaArtworkView: View {
    let item: MediaItem
    let size: CGFloat
    @State private var image: UIImage?

    private var corner: CGFloat {
        size > 60 ? 10 : TapeTheme.radiusThumb
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(item.kind.isVideo ? TapeTheme.peach : TapeTheme.cream)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: item.kind.isVideo ? "film.fill" : "waveform")
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(TapeTheme.ink)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
        }
        .background {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(TapeTheme.card)
                .shadow(color: TapeTheme.ink, radius: 0, x: 2, y: 2)
        }
        .accessibilityHidden(true)
        .task(id: item.artworkKey) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let key = item.artworkKey,
              let url = try? MediaStorage.live.artworkURL(forKey: key) else {
            image = nil
            return
        }
        let data = await Task.detached(priority: .utility) {
            try? Data(contentsOf: url)
        }.value
        image = data.flatMap(UIImage.init(data:))
    }
}

private func formatDuration(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "—" }
    let total = Int(seconds.rounded())
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    if hours > 0 {
        return L10n.format("duration.hoursMinutes", hours, minutes)
    }
    return L10n.format("duration.minutesSeconds", minutes, total % 60)
}
