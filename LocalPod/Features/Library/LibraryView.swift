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

    @Query(sort: \MediaItem.addedAt, order: .reverse)
    private var allItems: [MediaItem]

    @Query(sort: \MediaCollection.name)
    private var collections: [MediaCollection]

    @State private var scope: Scope = .items
    @State private var filter: ItemFilter = .all
    @State private var sort: ItemSort = .recent
    @State private var searchText = ""

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
                ToolbarItem(placement: .topBarTrailing) {
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
            } else {
                ForEach(displayedItems) { item in
                    NavigationLink {
                        LibraryItemDetailView(item: item)
                    } label: {
                        LibraryItemRow(item: item)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("libraryItem-\(item.title)")
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
            } else {
                ForEach(collectionRows) { row in
                    NavigationLink {
                        LibraryCollectionDetailView(collection: row.collection)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "square.stack.3d.up.fill")
                                .foregroundStyle(.indigo)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.collection.name)
                                    .lineLimit(1)
                                Text("\(row.itemCount) 条 · \(formatDuration(row.duration)) · \(ByteCountFormatter.string(fromByteCount: row.byteCount, countStyle: .file))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
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
                        .lineLimit(1)
                    if item.isMissing {
                        Text("缺失")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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

struct LibraryCollectionDetailView: View {
    let collection: MediaCollection

    @Query(sort: \MediaItem.relativeFolderPath)
    private var allItems: [MediaItem]

    private var items: [MediaItem] {
        allItems.filter { $0.collectionID == collection.id }
    }

    var body: some View {
        List {
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
    @Environment(PlaybackController.self) private var playback

    @State private var showDeleteConfirmation = false
    @State private var showVideo = false
    @State private var errorMessage: String?

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
                    Label(item.kind.isVideo ? "播放视频" : "播放音频", systemImage: "play.fill")
                }
                .accessibilityIdentifier("detailPlayButton")

                if item.kind.isVideo {
                    Button {
                        guard play() else { return }
                        showVideo = true
                    } label: {
                        Label("打开视频画面", systemImage: "rectangle.expand.vertical")
                    }
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("删除条目", systemImage: "trash")
                }
                .accessibilityIdentifier("detailDeleteButton")
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
        .alert("删除这个条目？", isPresented: $showDeleteConfirmation) {
            Button("删除", role: .destructive) {
                deleteItem()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除资料库记录、媒体文件与封面，释放 \(ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file))。")
        }
        .fullScreenCover(isPresented: $showVideo) {
            VideoPlayerScreen(
                player: playback.player,
                onPictureInPictureChange: { playback.setPictureInPictureActive($0) },
                onRestoreUI: { showVideo = true }
            )
        }
    }

    @discardableResult
    private func play() -> Bool {
        guard let url = item.fileURL,
              FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "媒体文件不存在：\(item.relativePath)"
            return false
        }
        playback.load(
            PlaybackItem(
                title: item.title,
                subtitle: item.folderName ?? "资料库",
                fileURL: url,
                kind: item.kind,
                durationHint: item.durationSeconds,
                libraryItemID: item.id,
                artworkURL: item.artworkURL
            ),
            autoplay: true
        )
        return true
    }

    private func deleteItem() {
        do {
            let service = LibraryService(storage: .live)
            _ = try service.delete(item, in: modelContext)
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
                            : [.indigo.opacity(0.85), .blue.opacity(0.6)],
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
