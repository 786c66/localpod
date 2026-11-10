import Foundation
import SwiftUI
import SwiftData
import UIKit
import LocalPodKit

struct LibraryView: View {
    private enum Scope: String, CaseIterable, Identifiable {
        case items = "条目"
        case collections = "合集"
        var id: String { rawValue }
    }

    private enum ItemFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case audio = "音频"
        case video = "视频"
        case missing = "缺失"
        var id: String { rawValue }
    }

    private enum ItemSort: String, CaseIterable, Identifiable {
        case recent = "最近添加"
        case title = "标题"
        case size = "大小"
        case duration = "时长"
        var id: String { rawValue }
    }

    @Environment(PlaybackSession.self) private var session

    @Query(sort: \MediaItem.addedAt, order: .reverse)
    private var allItems: [MediaItem]

    @Query(sort: \MediaCollection.name)
    private var collections: [MediaCollection]

    @Query(sort: \PlaybackState.lastPlayedAt, order: .reverse)
    private var progressStates: [PlaybackState]

    @Query(sort: \Playlist.sortOrder)
    private var playlists: [Playlist]

    @State private var scope: Scope = .items
    @State private var filter: ItemFilter = .all
    @State private var sort: ItemSort = .recent
    @State private var searchText = ""
    @State private var showSettings = false

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

    private var continueItems: [(item: MediaItem, state: PlaybackState)] {
        let byID = Dictionary(uniqueKeysWithValues: libraryItems.map { ($0.id, $0) })
        return progressStates.compactMap { state in
            guard !state.isFinished,
                  state.playCount > 0,
                  !(byID[state.itemID]?.isMissing ?? true),
                  let item = byID[state.itemID] else {
                return nil
            }
            return (item, state)
        }
        .prefix(5)
        .map { $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(libraryItems.count) 条 · \(collections.count) 个合集 · \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("libraryStatsText")
                    LabeledContent("条目", value: "\(libraryItems.count) 条")
                    LabeledContent("合集", value: "\(collections.count) 个")
                    LabeledContent("总大小", value: ByteCountFormatter.string(
                        fromByteCount: totalBytes,
                        countStyle: .file
                    ))
                    LabeledContent("总时长", value: formatDuration(totalDuration))
                } header: {
                    Text("资料库")
                }

                if !continueItems.isEmpty {
                    Section("继续播放") {
                        ForEach(continueItems, id: \.item.id) { entry in
                            Button {
                                session.play(item: entry.item)
                            } label: {
                                ContinueListeningRow(item: entry.item, state: entry.state)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("continueItem-\(entry.item.title)")
                        }
                    }
                }

                Section {
                    Picker("视图", selection: $scope) {
                        ForEach(Scope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if scope == .items {
                    itemsSection
                } else {
                    collectionsSection
                }
            }
            .navigationTitle("资料库")
            .searchable(text: $searchText, prompt: "搜索标题或文件夹")
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
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        Divider()
                        Picker("排序", selection: $sort) {
                            ForEach(ItemSort.allCases) { sort in
                                Text(sort.rawValue).tag(sort)
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
        }
    }

    @ViewBuilder
    private var itemsSection: some View {
        Section("条目 · \(displayedItems.count)") {
            if displayedItems.isEmpty {
                ContentUnavailableView(
                    libraryItems.isEmpty ? "资料库为空" : "没有匹配的条目",
                    systemImage: "waveform",
                    description: Text(libraryItems.isEmpty ? "去「导入」选择一个文件夹开始。" : "调整搜索或筛选条件。")
                )
                .accessibilityIdentifier("libraryEmptyState")
            } else {
                ForEach(displayedItems) { item in
                    NavigationLink {
                        LibraryItemDetailView(item: item)
                    } label: {
                        LibraryItemRow(item: item)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("libraryItem-\(item.title)")
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
        }
    }

    @ViewBuilder
    private var collectionsSection: some View {
        Section("合集 · \(collectionRows.count)") {
            if collectionRows.isEmpty {
                ContentUnavailableView(
                    "还没有合集",
                    systemImage: "square.stack.3d.up",
                    description: Text("导入一个文件夹后会自动生成合集。")
                )
                .accessibilityIdentifier("collectionEmptyState")
            } else {
                ForEach(collectionRows) { row in
                    NavigationLink {
                        LibraryCollectionDetailView(collection: row.collection)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "square.stack.3d.up.fill")
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.collection.name)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("\(row.itemCount) 条 · \(formatDuration(row.duration)) · \(ByteCountFormatter.string(fromByteCount: row.byteCount, countStyle: .file))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .accessibilityIdentifier("collectionRow-\(row.collection.name)")
                }
            }
        }
    }
}

private struct CollectionRow: Identifiable {
    let collection: MediaCollection
    let itemCount: Int
    let byteCount: Int64
    let duration: Double

    var id: UUID { collection.id }
}

struct LibraryItemRow: View {
    let item: MediaItem

    var body: some View {
        HStack(spacing: 12) {
            MediaArtworkView(item: item, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .fixedSize(horizontal: false, vertical: true)
                    if item.isMissing {
                        Text("缺失")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Text(item.durationText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
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

struct ContinueListeningRow: View {
    let item: MediaItem
    let state: PlaybackState

    private var progress: Double {
        guard state.duration > 0 else { return 0 }
        return min(max(state.position / state.duration, 0), 1)
    }

    var body: some View {
        HStack(spacing: 12) {
            MediaArtworkView(item: item, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .fixedSize(horizontal: false, vertical: true)
                ProgressView(value: progress)
                    .tint(Color.accentColor)
                Text("已听 \(Int(state.position)) 秒 / \(item.durationText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Image(systemName: "play.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
        }
    }
}

struct LibraryCollectionDetailView: View {
    let collection: MediaCollection

    @Environment(PlaybackSession.self) private var session

    @Query(sort: \MediaItem.relativeFolderPath)
    private var allItems: [MediaItem]

    private var items: [MediaItem] {
        allItems.filter { $0.collectionID == collection.id }
    }

    var body: some View {
        List {
            Section {
                Button {
                    session.play(items: items)
                } label: {
                    Label("播放全部（\(items.count)）", systemImage: "play.fill")
                }
                .accessibilityIdentifier("collectionPlayAllButton")

                Button {
                    session.play(items: items, shuffle: true)
                } label: {
                    Label("随机播放", systemImage: "shuffle")
                }
                .accessibilityIdentifier("collectionShuffleButton")
            }

            Section {
                LabeledContent("条目", value: "\(items.count) 条")
                LabeledContent("总大小", value: ByteCountFormatter.string(
                    fromByteCount: items.reduce(0) { $0 + $1.byteSize },
                    countStyle: .file
                ))
                LabeledContent("总时长", value: formatDuration(
                    items.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
                ))
            }

            Section("条目") {
                ForEach(items) { item in
                    NavigationLink {
                        LibraryItemDetailView(item: item)
                    } label: {
                        LibraryItemRow(item: item)
                    }
                }
            }
        }
        .navigationTitle(collection.name)
    }
}

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

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    MediaArtworkView(item: item, size: 160)
                    Spacer()
                }
                .padding(.vertical, 8)
            }

            Section("信息") {
                LabeledContent("标题", value: item.title)
                LabeledContent("类型", value: item.kind.displayName)
                LabeledContent("格式", value: item.fileExtension.uppercased())
                LabeledContent("大小", value: ByteCountFormatter.string(
                    fromByteCount: item.byteSize,
                    countStyle: .file
                ))
                LabeledContent("时长", value: item.durationText)
                if let folder = item.folderName {
                    LabeledContent("合集", value: folder)
                }
                if !item.relativeFolderPath.isEmpty {
                    LabeledContent("文件夹内路径", value: item.relativeFolderPath)
                }
                LabeledContent("来源", value: item.source.displayName)
                LabeledContent("添加时间", value: item.addedAt.formatted(
                    date: .abbreviated,
                    time: .shortened
                ))
                if let fingerprint = item.fingerprint {
                    LabeledContent("SHA-256", value: String(fingerprint.prefix(16)) + "…")
                }
                if item.isMissing {
                    Text("媒体文件缺失。重新导入相同内容可重链此条目。")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("存储路径") {
                Text(item.relativePath)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    play()
                } label: {
                    Label(
                        item.kind.isVideo ? "播放音频（视频仅音轨）" : "播放音频",
                        systemImage: "play.fill"
                    )
                }
                .accessibilityIdentifier("detailPlayButton")

                Button {
                    session.playNext(itemID: item.id)
                    infoMessage = "已加入「播放下一首」。"
                } label: {
                    Label("播放下一首", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                .accessibilityIdentifier("detailPlayNextButton")

                Button {
                    session.enqueue(itemID: item.id)
                    infoMessage = "已加入队列末尾。"
                } label: {
                    Label("加入队列", systemImage: "text.append")
                }
                .accessibilityIdentifier("detailEnqueueButton")

                if playlists.isEmpty {
                    Text("还没有播放列表。在资料库右上角进入「播放列表」创建。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        showPlaylistPicker = true
                    } label: {
                        Label("加入播放列表", systemImage: "music.note.list")
                    }
                    .accessibilityIdentifier("detailAddToPlaylistMenu")
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("删除条目", systemImage: "trash")
                }
                .accessibilityIdentifier("detailDeleteButton")
            }

            if let infoMessage {
                Section {
                    Text(infoMessage)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityIdentifier("detailQueueInfoText")
                }
            }

            if let errorMessage {
                Section("错误") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPlaylistPicker) {
            NavigationStack {
                List(playlists) { playlist in
                    Button(playlist.name) {
                        if session.playlists.add(itemID: item.id, to: playlist) {
                            infoMessage = "已加入播放列表「\(playlist.name)」。"
                        } else {
                            infoMessage = "「\(playlist.name)」已包含此条目。"
                        }
                        showPlaylistPicker = false
                    }
                    .accessibilityIdentifier("addToPlaylistOption-\(playlist.name)")
                }
                .navigationTitle("加入播放列表")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showPlaylistPicker = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .alert("删除这个条目？", isPresented: $showDeleteConfirmation) {
            Button("删除", role: .destructive) {
                deleteItem()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除资料库记录、媒体文件与封面，释放 \(ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file))。")
        }
    }

    @discardableResult
    private func play() -> Bool {
        guard let url = item.fileURL,
              FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "媒体文件不存在：\(item.relativePath)"
            return false
        }
        session.play(item: item)
        if let sessionError = session.lastError {
            errorMessage = sessionError
            return false
        }
        return true
    }

    private func deleteItem() {
        let itemID = item.id
        do {
            let service = LibraryService(storage: .live)
            _ = try service.delete(item, in: modelContext)
            session.handleDeletedItem(itemID)
            dismiss()
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
        }
    }
}

struct MediaArtworkView: View {
    let item: MediaItem
    let size: CGFloat
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size > 60 ? 16 : 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: item.kind.isVideo
                            ? [.orange.opacity(0.85), .red.opacity(0.65)]
                            : [Color.accentColor.opacity(0.85), .blue.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: item.kind.isVideo ? "film.fill" : "waveform")
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size > 60 ? 16 : 8, style: .continuous))
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
        return "\(hours) 小时 \(minutes) 分"
    }
    return "\(minutes) 分 \(total % 60) 秒"
}
