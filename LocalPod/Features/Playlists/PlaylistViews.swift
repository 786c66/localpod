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

    private enum Destination {
        case playlist(Playlist)
        case smartKind(SmartPlaylistKind)
        case smartCollections
    }

    @Environment(PlaybackSession.self) private var session
    @Query(sort: \Playlist.sortOrder)
    private var playlists: [Playlist]
    @Query private var allEntries: [PlaylistEntry]

    @State private var dialog: Dialog?
    @State private var nameDraft = ""
    @State private var destination: Destination?
    @State private var showDestination = false

    var body: some View {
        List {
            if !playlists.isEmpty {
                Section {
                    heroCard
                        .tapeRowInsets(8)
                }

                Section {
                    ForEach(playlists) { playlist in
                        Button {
                            destination = .playlist(playlist)
                            showDestination = true
                        } label: {
                            TapeRow(
                                thumbFill: TapeTheme.violet,
                                icon: "music.note.list",
                                title: playlist.name,
                                subtitle: "\(count(playlist)) 条",
                                trailingIcon: "chevron.right"
                            )
                        }
                        .buttonStyle(TapePlainPressStyle())
                        .accessibilityIdentifier("playlistRow-\(playlist.name)")
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                nameDraft = playlist.name
                                dialog = .rename(playlist)
                            } label: {
                                Label("重命名", systemImage: "pencil")
                            }
                            .tint(TapeTheme.violet)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                session.playlists.delete(playlist)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .tapeRowInsets(4)
                    }
                } header: {
                    sectionHeader("播放列表 · \(playlists.count)", kicker: "PLAYLISTS")
                }
            }

            SmartPlaylistHubSection(
                onSelectKind: { kind in
                    destination = .smartKind(kind)
                    showDestination = true
                },
                onSelectCollections: {
                    destination = .smartCollections
                    showDestination = true
                }
            )

            // With no user playlists the empty card sits below the smart
            // mixes: the smart rows are the useful first screen, and the
            // card would otherwise push the By Collection row off screen.
            if playlists.isEmpty {
                Section {
                    emptyCard
                        .tapeRowInsets(6)
                }
            }
        }
        .listStyle(.plain)
        .tapeScreen()
        .navigationTitle("播放列表")
        .tapeNavigationChrome()
        .navigationDestination(isPresented: $showDestination) {
            switch destination {
            case .playlist(let playlist):
                PlaylistDetailView(playlist: playlist)
            case .smartKind(let kind):
                SmartPlaylistDetailView(kind: kind)
            case .smartCollections:
                SmartCollectionPickerView()
            case nil:
                EmptyView()
            }
        }
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

    // MARK: - Hero and empty state

    private var heroCard: some View {
        TapeCard(fill: TapeTheme.acid) {
            HStack(alignment: .top, spacing: TapeTheme.space2) {
                VStack(alignment: .leading, spacing: 5) {
                    TapeKicker(text: "MIXTAPES", color: TapeTheme.ink.opacity(0.62))
                    Text("播放列表")
                        .font(TapeType.title1)
                        .tracking(-0.6)
                        .foregroundStyle(TapeTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: TapeTheme.space2)
                TapeSticker(
                    text: "\(playlists.count)",
                    fill: TapeTheme.card,
                    foreground: TapeTheme.ink,
                    angle: 4
                )
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
                Text("还没有播放列表")
                    .font(TapeType.title2)
                    .tracking(-0.4)
                    .foregroundStyle(TapeTheme.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("playlistEmptyState")
                Text("点右上角 + 创建一个，然后在资料库条目里加入。")
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
    @State private var itemDetailTarget: MediaItem?
    @State private var showItemDetail = false

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
                heroCard
                    .tapeRowInsets(8)
            }

            Section {
                if entries.isEmpty {
                    TapeDashedCard {
                        VStack(spacing: TapeTheme.space3) {
                            TapeRewardSticker(
                                text: "EMPTY",
                                fill: TapeTheme.violet,
                                foreground: TapeTheme.stickerInk
                            )
                            Text("还没有条目。在资料库条目详情里选择「加入播放列表」。")
                                .font(TapeType.body)
                                .foregroundStyle(TapeTheme.muted)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .tapeRowInsets(6)
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
                            entryRow(index: index, item: item)
                        }
                        .buttonStyle(TapePlainPressStyle())
                        .disabled(item == nil)
                        .accessibilityIdentifier("playlistItem-\(item?.title ?? entry.itemID.uuidString)")
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                moveEntry(at: index, by: -1)
                            } label: {
                                Label("上移", systemImage: "arrow.up")
                            }
                            .tint(TapeTheme.violet)
                            .disabled(index == 0)

                            Button {
                                moveEntry(at: index, by: 1)
                            } label: {
                                Label("下移", systemImage: "arrow.down")
                            }
                            .tint(TapeTheme.violet)
                            .disabled(index >= entries.count - 1)
                        }
                        .tapeRowInsets(4)
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
            } header: {
                sectionHeader("条目 · \(entries.count)", kicker: "IN THE MIX")
            }

            Section {
                Button("删除播放列表", role: .destructive) {
                    showDeleteConfirmation = true
                }
                .buttonStyle(TapeDestructiveButtonStyle())
                .accessibilityIdentifier("playlistDeleteButton")
                .tapeRowInsets(6)
            }
        }
        .listStyle(.plain)
        .tapeScreen()
        .navigationTitle(playlist.name)
        .tapeNavigationChrome()
        .navigationDestination(isPresented: $showItemDetail) {
            if let itemDetailTarget {
                LibraryItemDetailView(item: itemDetailTarget)
            }
        }
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

    // MARK: - Hero

    private var heroCard: some View {
        TapeCard(fill: TapeTheme.acid) {
            VStack(alignment: .leading, spacing: TapeTheme.space3) {
                HStack(alignment: .top, spacing: TapeTheme.space2) {
                    VStack(alignment: .leading, spacing: 5) {
                        TapeKicker(text: "MIXTAPE", color: TapeTheme.ink.opacity(0.62))
                        Text(playlist.name)
                            .font(TapeType.title1)
                            .tracking(-0.6)
                            .foregroundStyle(TapeTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: TapeTheme.space2)
                    TapeSticker(
                        text: "\(entries.count) 条",
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
            session.play(items: playableItems)
        } label: {
            Label("播放全部（\(playableItems.count)）", systemImage: "play.fill")
        }
        .buttonStyle(TapePrimaryButtonStyle())
        .disabled(playableItems.isEmpty)
        .opacity(playableItems.isEmpty ? 0.55 : 1)
        .accessibilityIdentifier("playlistPlayAllButton")
    }

    private var shuffleButton: some View {
        Button {
            session.play(items: playableItems, shuffle: true)
        } label: {
            Label("随机播放", systemImage: "shuffle")
        }
        .buttonStyle(TapeSecondaryButtonStyle())
        .disabled(playableItems.isEmpty)
        .opacity(playableItems.isEmpty ? 0.55 : 1)
        .accessibilityIdentifier("playlistShuffleButton")
    }

    // MARK: - Rows

    private func entryRow(index: Int, item: MediaItem?) -> some View {
        HStack(spacing: TapeTheme.space3) {
            Text("\(index + 1)")
                .font(TapeFont.mono(12, weight: .semibold, relativeTo: .caption))
                .foregroundStyle(TapeTheme.faint)
                .frame(width: 22, alignment: .trailing)

            ZStack {
                RoundedRectangle(cornerRadius: TapeTheme.radiusThumb, style: .continuous)
                    .fill(item == nil ? TapeTheme.track : TapeTheme.violetSoft)
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TapeTheme.ink)
            }
            .frame(width: 36, height: 36)
            .overlay {
                RoundedRectangle(cornerRadius: TapeTheme.radiusThumb, style: .continuous)
                    .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item?.title ?? L10n.string("common.deletedItem"))
                    .font(TapeType.headline)
                    .foregroundStyle(TapeTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item?.durationText ?? "—")
                    .font(TapeType.monoMicro)
                    .foregroundStyle(TapeTheme.faint)
            }

            Spacer(minLength: TapeTheme.space2)

            Image(systemName: "play.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(TapeTheme.ink)
                .frame(width: 28, height: 28)
                .background(TapeTheme.cream, in: Circle())
                .overlay { Circle().strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke) }
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

    private func sectionHeader(_ title: String, kicker: String) -> some View {
        TapeSectionHeader(title: title, kicker: kicker)
            .textCase(nil)
            .padding(.horizontal, TapeTheme.screenPadding)
            .padding(.top, TapeTheme.space3)
            .padding(.bottom, TapeTheme.space1)
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
