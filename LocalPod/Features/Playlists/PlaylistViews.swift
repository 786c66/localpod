import SwiftUI
import SwiftData
import LocalPodKit

struct PlaylistListView: View {
    private enum Dialog: Identifiable {
        case create
        case rename(Playlist)

        var id: String {
            switch self {
            case .create: "create"
            case .rename(let playlist): "rename-\(playlist.id.uuidString)"
            }
        }
    }

    @Environment(PlaybackSession.self) private var session
    @Query(sort: \Playlist.sortOrder)
    private var playlists: [Playlist]
    @Query private var allEntries: [PlaylistEntry]

    @State private var dialog: Dialog?
    @State private var nameDraft = ""

    var body: some View {
        List {
            if playlists.isEmpty {
                Section {
                    ContentUnavailableView(
                        "还没有播放列表",
                        systemImage: "music.note.list",
                        description: Text("点右上角 + 创建一个，然后在资料库条目里加入。")
                    )
                    .accessibilityIdentifier("playlistEmptyState")
                }
            } else {
                Section("播放列表 · \(playlists.count)") {
                    ForEach(playlists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(playlist: playlist)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "music.note.list")
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(playlist.name)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text("\(count(playlist)) 条")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityIdentifier("playlistRow-\(playlist.name)")
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                nameDraft = playlist.name
                                dialog = .rename(playlist)
                            } label: {
                                Label("重命名", systemImage: "pencil")
                            }
                            .tint(Color.accentColor)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                session.playlists.delete(playlist)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("播放列表")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    nameDraft = ""
                    dialog = .create
                } label: {
                    Label("新建播放列表", systemImage: "plus")
                }
                .accessibilityIdentifier("playlistCreateButton")
            }
        }
        .alert(dialogTitle, isPresented: dialogPresented) {
            TextField("名称", text: $nameDraft)
                .accessibilityIdentifier("playlistNameField")
            Button("取消", role: .cancel) {
                dialog = nil
            }
            Button("保存") {
                saveDialog()
            }
            .accessibilityIdentifier("playlistDialogSaveButton")
        }
    }

    private var dialogTitle: String {
        switch dialog {
        case .rename: L10n.string("playlist.renameTitle")
        default: L10n.string("playlist.createTitle")
        }
    }

    private var dialogPresented: Binding<Bool> {
        Binding(
            get: { dialog != nil },
            set: { if !$0 { dialog = nil } }
        )
    }

    private func count(_ playlist: Playlist) -> Int {
        allEntries.filter { $0.playlistID == playlist.id }.count
    }

    private func saveDialog() {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        switch dialog {
        case .create:
            session.playlists.create(name: name)
        case .rename(let playlist):
            session.playlists.rename(playlist, to: name)
        case nil:
            break
        }
        dialog = nil
    }
}

struct PlaylistDetailView: View {
    let playlist: Playlist

    @Environment(PlaybackSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @Query private var allEntries: [PlaylistEntry]
    @Query private var allItems: [MediaItem]

    @State private var showDeleteConfirmation = false

    private var entries: [PlaylistEntry] {
        allEntries
            .filter { $0.playlistID == playlist.id }
            .sorted { $0.position < $1.position }
    }

    private var itemByID: [UUID: MediaItem] {
        Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
    }

    private var playableItems: [MediaItem] {
        entries.compactMap { itemByID[$0.itemID] }
    }

    var body: some View {
        List {
            Section {
                Button {
                    session.play(items: playableItems)
                } label: {
                    Label("播放全部（\(playableItems.count)）", systemImage: "play.fill")
                }
                .disabled(playableItems.isEmpty)
                .accessibilityIdentifier("playlistPlayAllButton")

                Button {
                    session.play(items: playableItems, shuffle: true)
                } label: {
                    Label("随机播放", systemImage: "shuffle")
                }
                .disabled(playableItems.isEmpty)
                .accessibilityIdentifier("playlistShuffleButton")
            }

            Section("条目 · \(entries.count)") {
                if entries.isEmpty {
                    Text("还没有条目。在资料库条目详情里选择「加入播放列表」。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        let item = itemByID[entry.itemID]
                        Button {
                            guard let item,
                                  let playIndex = playableItems.firstIndex(where: { $0.id == item.id }) else {
                                return
                            }
                            session.play(items: playableItems, startingAt: playIndex)
                        } label: {
                            HStack(spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22, alignment: .trailing)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item?.title ?? L10n.string("common.deletedItem"))
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(item?.durationText ?? "—")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "play.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(item == nil)
                        .accessibilityIdentifier("playlistItem-\(item?.title ?? entry.itemID.uuidString)")
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                moveEntry(at: index, by: -1)
                            } label: {
                                Label("上移", systemImage: "arrow.up")
                            }
                            .tint(Color.accentColor)
                            .disabled(index == 0)

                            Button {
                                moveEntry(at: index, by: 1)
                            } label: {
                                Label("下移", systemImage: "arrow.down")
                            }
                            .tint(.teal)
                            .disabled(index >= entries.count - 1)
                        }
                    }
                    .onMove { source, destination in
                        session.playlists.move(
                            in: playlist,
                            fromOffsets: source,
                            toOffset: destination
                        )
                    }
                    .onDelete { offsets in
                        for index in offsets.sorted(by: >) {
                            guard entries.indices.contains(index) else { continue }
                            session.playlists.removeEntry(id: entries[index].id)
                        }
                    }
                }
            }

            Section {
                Button("删除播放列表", role: .destructive) {
                    showDeleteConfirmation = true
                }
                .accessibilityIdentifier("playlistDeleteButton")
            }
        }
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !entries.isEmpty {
                EditButton()
            }
        }
        .alert("删除「\(playlist.name)」？", isPresented: $showDeleteConfirmation) {
            Button("删除", role: .destructive) {
                session.playlists.delete(playlist)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只删除播放列表本身，不会删除资料库里的媒体文件。")
        }
    }

    private func moveEntry(at index: Int, by delta: Int) {
        let destination = index + delta
        guard entries.indices.contains(destination) else { return }
        session.playlists.move(
            in: playlist,
            fromOffsets: IndexSet(integer: index),
            toOffset: delta > 0 ? destination + 1 : destination
        )
    }
}
