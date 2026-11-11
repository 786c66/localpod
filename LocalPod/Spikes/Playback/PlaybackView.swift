import Foundation
import SwiftUI
import SwiftData
import LocalPodKit

struct PlaybackView: View {
    @Environment(PlaybackController.self) private var playback
    @Environment(PlaybackSession.self) private var session
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(
        sort: \MediaItem.addedAt,
        order: .reverse
    )
    private var allItems: [MediaItem]

    /// Set by RootView so the empty state can switch tabs.
    var onGoToLibrary: () -> Void = {}

    private var items: [MediaItem] {
        allItems.filter { $0.source != .benchmark && !$0.isMissing }
    }

    private var itemByID: [UUID: MediaItem] {
        Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
    }

    @State private var showSettings = false
    @State private var localError: String?
    @State private var scrubPosition: Double?

    var body: some View {
        NavigationStack {
            List {
                // Now playing leads; the queue sits directly under it. The
                // built-in test signals are developer conveniences and come
                // after the real content. Dropping the player's section
                // header buys the space that keeps the transport controls
                // inside the first screenful on a 6.1" phone; the cassette
                // label already carries the title and subtitle.
                Section {
                    playerCard
                        .tapeRowInsets(8)
                }

                queueSection

                Section {
                    demoAudioRow
                    demoLongAudioRow
                } header: {
                    sectionHeader(title: "内置测试媒体", kicker: "TEST SIGNAL")
                } footer: {
                    Text("LocalPod 只播放音频。视频文件可导入并读取其音轨，但不显示画面、不做旋转/PiP。")
                        .font(TapeType.caption)
                        .foregroundStyle(TapeTheme.muted)
                        .padding(.horizontal, TapeTheme.space4)
                        .padding(.top, TapeTheme.space1)
                        .listRowBackground(Color.clear)
                }

                Section {
                    if items.isEmpty {
                        TapeDashedCard {
                            Text("还没有可播放的条目。先在「导入」页导入演示文件夹。")
                                .font(TapeType.body)
                                .foregroundStyle(TapeTheme.muted)
                                .multilineTextAlignment(.center)
                        }
                        .tapeRowInsets(6)
                    } else {
                        ForEach(items) { item in
                            Button {
                                playLibraryItem(item)
                            } label: {
                                libraryRow(item)
                            }
                            .buttonStyle(TapePlainPressStyle())
                            .tapeRowInsets(4)
                        }
                    }
                } header: {
                    sectionHeader(title: "资料库 · \(items.count)", kicker: "ON THE SHELF")
                }

                if let localError {
                    Section {
                        TapeCard(fill: TapeTheme.peach) {
                            HStack(alignment: .top, spacing: TapeTheme.space2) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(TapeTheme.ink)
                                Text(localError)
                                    .font(TapeType.body)
                                    .foregroundStyle(TapeTheme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .tapeRowInsets(6)
                    } header: {
                        sectionHeader(title: "错误", kicker: "TROUBLE")
                    }
                }
            }
            .listStyle(.plain)
            .tapeScreen()
            .navigationTitle(L10n.string("tab.playback"))
            .tapeNavigationChrome()
            .overlay(alignment: .topTrailing) {
                playbackPhaseSticker
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    if !session.queue.isEmpty {
                        EditButton()
                            .font(TapeType.bodySmall)
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Sleep timer is a utility, not a transport control: keep
                    // it in the bar so arming it never pushes the transport
                    // row down (and out of reach) while a timer is active.
                    sleepTimerMenu
                    Button {
                        showSettings = true
                    } label: {
                        Label("设置", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("playbackSettingsButton")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    // MARK: - Phase sticker

    /// Always-on status sticker. It floats above the list instead of living in
    /// the navigation bar: the bar drops out of the accessibility tree once
    /// the list is scrolled, and the status must stay queryable while the
    /// queue is on screen. The sticker is decorative for touch purposes so it
    /// never blocks the rows underneath.
    private var playbackPhaseSticker: some View {
        Text(playback.statusText)
            .font(TapeType.monoMicro)
            .foregroundStyle(TapeTheme.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(TapeTheme.acid, in: Capsule())
            .overlay { Capsule().strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke) }
            .shadow(color: TapeTheme.ink, radius: 0, x: 2, y: 2)
            .padding(.top, 56)
            .padding(.trailing, 14)
            .allowsHitTesting(false)
            .accessibilityIdentifier("playbackPhaseText")
    }

    // MARK: - Section chrome

    private func sectionHeader(title: String, kicker: String) -> some View {
        TapeSectionHeader(title: title, kicker: kicker)
            .textCase(nil)
            .padding(.horizontal, TapeTheme.screenPadding)
            .padding(.top, TapeTheme.space3)
            .padding(.bottom, TapeTheme.space1)
    }

    // MARK: - Built-in media

    private var demoAudioRow: some View {
        Button {
            playDemo(
                name: "demo-audio",
                fileExtension: "m4a",
                title: L10n.string("playback.demo.audioTitle"),
                kind: .audio
            )
        } label: {
            TapeRow(
                thumbText: "A",
                thumbFill: TapeTheme.coral,
                icon: "waveform",
                title: "播放内置音频",
                subtitle: "DEMO · SHORT CLIP"
            )
        }
        .buttonStyle(TapePlainPressStyle())
        .accessibilityIdentifier("playDemoAudioButton")
        .tapeRowInsets(4)
    }

    private var demoLongAudioRow: some View {
        Button {
            playDemo(
                name: "demo-long-audio",
                fileExtension: "m4a",
                title: L10n.string("playback.demo.longAudioTitle"),
                kind: .audio
            )
        } label: {
            TapeRow(
                thumbText: "B",
                thumbFill: TapeTheme.violet,
                icon: "clock",
                title: "播放 5 分钟测试音频",
                subtitle: "DEMO · LONG CLIP"
            )
        }
        .buttonStyle(TapePlainPressStyle())
        .accessibilityIdentifier("playLongAudioButton")
        .tapeRowInsets(4)
    }

    // MARK: - Player

    @ViewBuilder
    private var playerCard: some View {
        if let item = playback.currentItem {
            VStack(spacing: TapeTheme.space3) {
                TapeTapeCover(
                    title: item.title,
                    subtitle: item.subtitle,
                    durationText: formatTime(max(playback.duration, 0)),
                    isPlaying: playback.isPlaying,
                    artworkURL: item.artworkURL,
                    width: dynamicTypeSize.isAccessibilitySize ? 190 : 236
                )
                .padding(.top, 2)
                // The tape itself is the title now. Expose it as one element
                // so UI tests (and VoiceOver) still get the track name.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.title)
                .accessibilityIdentifier("currentPlaybackTitle")

                queueBadge
                    .frame(maxWidth: .infinity)

                if let error = playback.errorMessage {
                    errorRow(error)
                }

                controlCard

                // Below the transport card: arming a timer must not push the
                // transport controls toward (or past) the fold.
                if session.sleepTimer.isActive {
                    sleepTimerStatusRow
                }

                chapterSection
            }
            .padding(.vertical, TapeTheme.space2)
        } else {
            TapeDashedCard {
                VStack(spacing: TapeTheme.space3) {
                    TapeRewardSticker(
                        text: "SIDE A",
                        fill: TapeTheme.violet,
                        foreground: TapeTheme.stickerInk
                    )
                    Text("未在播放")
                        .font(TapeType.title2)
                        .foregroundStyle(TapeTheme.ink)
                        .accessibilityIdentifier("playbackEmptyState")
                    Text("从资料库选择条目，或播放上方的内置测试媒体。")
                        .font(TapeType.body)
                        .foregroundStyle(TapeTheme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("去资料库") {
                        onGoToLibrary()
                    }
                    .buttonStyle(TapePrimaryButtonStyle())
                    .accessibilityIdentifier("playbackEmptyLibraryButton")
                    .accessibilityHint("切换到资料库标签")
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var queueBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "text.line.3.summary")
                .font(.system(size: 10, weight: .bold))
            Text("队列 · \(session.queue.count)")
                .font(TapeType.monoMicro)
                .accessibilityIdentifier("queueCountText")
        }
        .foregroundStyle(TapeTheme.ink)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(TapeTheme.cream, in: Capsule())
        .overlay { Capsule().strokeBorder(TapeTheme.ink, lineWidth: 1) }
    }

    private func errorRow(_ error: String) -> some View {
        HStack(alignment: .top, spacing: TapeTheme.space2) {
            Text(error)
                .font(TapeType.caption)
                .foregroundStyle(TapeTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: TapeTheme.space2)
            Button("重试") {
                playback.retry()
            }
            .font(TapeType.monoMeta)
            .accessibilityIdentifier("playbackRetryButton")
            .accessibilityHint("重新加载当前音频")
        }
        .padding(TapeTheme.space3)
        .background(TapeTheme.peach, in: RoundedRectangle(cornerRadius: TapeTheme.radiusSmall))
        .overlay {
            RoundedRectangle(cornerRadius: TapeTheme.radiusSmall)
                .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
        }
    }

    private var controlCard: some View {
        VStack(spacing: TapeTheme.space4) {
            // Transport first: play/pause is the reason this screen exists
            // and must be visible without scrolling on a 6.1" phone.
            transportControls

            VStack(spacing: TapeTheme.space2) {
                ZStack {
                    TapeProgressBar(
                        progress: progressFraction,
                        fill: TapeTheme.acid,
                        height: 10
                    )
                    .padding(.horizontal, 2)

                    Slider(
                        value: Binding(
                            get: { scrubPosition ?? playback.currentTime },
                            set: { scrubPosition = $0 }
                        ),
                        in: 0...max(playback.duration, 1)
                    ) { editing in
                        if !editing, let target = scrubPosition {
                            playback.seek(to: target)
                            scrubPosition = nil
                        }
                    }
                    .tint(TapeTheme.ink)
                    .opacity(0.02)
                    .frame(height: 44)
                    .accessibilityIdentifier("playbackSlider")
                    .accessibilityLabel("播放进度")
                    .accessibilityValue(
                        "\(formatTime(scrubPosition ?? playback.currentTime))，共 \(formatTime(max(playback.duration, 0)))"
                    )
                    .accessibilityHint("左右滑动调整播放位置")
                }

                HStack {
                    Text(formatTime(scrubPosition ?? playback.currentTime))
                        .accessibilityIdentifier("currentTimeText")
                    Spacer()
                    Text("-" + formatTime(max(0, playback.duration - (scrubPosition ?? playback.currentTime))))
                        .accessibilityIdentifier("remainingTimeText")
                }
                .font(TapeType.monoTime)
                .foregroundStyle(TapeTheme.muted)
            }

            TapeHairline()

            VStack(spacing: TapeTheme.space2) {
                HStack(spacing: TapeTheme.space2) {
                    Text("速度")
                        .font(TapeType.caption)
                        .foregroundStyle(TapeTheme.muted)
                    Spacer(minLength: 8)
                    Text(PlaybackPolicy.speedLabel(playback.playbackRate))
                        .font(TapeType.monoMeta)
                        .foregroundStyle(TapeTheme.ink)
                        .accessibilityIdentifier("playbackRateText")
                }

                speedChips
            }

            Text("快进/快退 \(Int(playback.skipForwardInterval)) 秒")
                .font(TapeType.captionSmall)
                .foregroundStyle(TapeTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(TapeTheme.space4)
        .tapeCardSurface()
    }

    private var progressFraction: Double {
        let duration = max(playback.duration, 1)
        return (scrubPosition ?? playback.currentTime) / duration
    }

    @ViewBuilder
    private var transportControls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: TapeTheme.space4) {
                HStack(spacing: TapeTheme.space4) {
                    previousButton
                    skipBackwardButton
                    skipForwardButton
                    nextButton
                }
                playPauseButton
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: TapeTheme.space4) {
                Spacer(minLength: 0)
                previousButton
                skipBackwardButton
                playPauseButton
                skipForwardButton
                nextButton
                Spacer(minLength: 0)
            }
        }
    }

    private var previousButton: some View {
        Button {
            session.previous()
        } label: {
            Image(systemName: "backward.end.fill")
        }
        .buttonStyle(TapeIconButtonStyle(diameter: 40))
        .accessibilityIdentifier("previousTrackButton")
        .accessibilityLabel("上一首")
        .accessibilityHint("播放队列中的上一首")
    }

    private var skipBackwardButton: some View {
        Button {
            playback.skip(by: -playback.skipBackwardInterval)
        } label: {
            Image(systemName: "gobackward")
        }
        .buttonStyle(TapeIconButtonStyle(diameter: 40))
        .accessibilityIdentifier("skipBackwardButton")
        .accessibilityLabel("快退 \(Int(playback.skipBackwardInterval)) 秒")
        .accessibilityHint("从当前位置向后跳转")
    }

    private var playPauseButton: some View {
        Button {
            playback.togglePlayPause()
        } label: {
            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 26, weight: .bold))
        }
        .buttonStyle(TapePlayButtonStyle())
        .accessibilityIdentifier("playPauseButton")
        .accessibilityLabel(playback.isPlaying ? "暂停" : "播放")
        .accessibilityHint(playback.isPlaying ? "暂停当前音频" : "继续播放当前音频")
    }

    private var skipForwardButton: some View {
        Button {
            playback.skip(by: playback.skipForwardInterval)
        } label: {
            Image(systemName: "goforward")
        }
        .buttonStyle(TapeIconButtonStyle(diameter: 40))
        .accessibilityIdentifier("skipForwardButton")
        .accessibilityLabel("快进 \(Int(playback.skipForwardInterval)) 秒")
        .accessibilityHint("从当前位置向前跳转")
    }

    private var nextButton: some View {
        Button {
            session.next()
        } label: {
            Image(systemName: "forward.end.fill")
        }
        .buttonStyle(TapeIconButtonStyle(diameter: 40))
        .accessibilityIdentifier("nextTrackButton")
        .accessibilityLabel("下一首")
        .accessibilityHint("播放队列中的下一首")
    }

    @ViewBuilder
    private var speedChips: some View {
        ViewThatFits(in: .horizontal) {
            speedChipsRow
                .fixedSize(horizontal: true, vertical: false)
            ScrollView(.horizontal, showsIndicators: false) {
                speedChipsRow
            }
        }
    }

    private var speedChipsRow: some View {
        HStack(spacing: TapeTheme.space2) {
            ForEach(PlaybackPolicy.featuredSpeedPresets, id: \.self) { rate in
                speedButton(rate)
            }
        }
        .padding(.vertical, 2)
    }

    private func speedButton(_ rate: Float) -> some View {
        let isSelected = playback.playbackRate == rate
        return Button {
            playback.setRate(rate)
        } label: {
            Text(PlaybackPolicy.speedLabel(rate))
                .font(TapeFont.display(13, weight: .semibold, relativeTo: .caption))
                .foregroundStyle(TapeTheme.ink)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .frame(minHeight: 32)
                .background {
                    Capsule()
                        .fill(isSelected ? TapeTheme.acid : TapeTheme.cream)
                        .shadow(
                            color: TapeTheme.ink,
                            radius: 0,
                            x: isSelected ? 2 : 0,
                            y: isSelected ? 2 : 0
                        )
                }
                .overlay { Capsule().strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke) }
        }
        .buttonStyle(TapePlainPressStyle())
        .accessibilityIdentifier("speedOption-\(rate)")
        .accessibilityLabel("速度 \(PlaybackPolicy.speedLabel(rate))")
        .accessibilityHint("把播放速度设为 \(PlaybackPolicy.speedLabel(rate))")
        .accessibilityAddTraits(isSelected ? .isSelected : AccessibilityTraits())
    }

    private var sleepTimerMenu: some View {
        Menu {
            Button("关闭") {
                session.cancelSleepTimer()
            }
            ForEach([1, 5, 15, 30, 45, 60, 90], id: \.self) { minutes in
                Button("\(minutes) 分钟") {
                    session.startSleepTimer(minutes: minutes)
                }
            }
            Divider()
            Button("本集结束") {
                session.startSleepTimerEndOfEpisode()
            }
        } label: {
            Image(systemName: "moon.zzz.fill")
        }
        .accessibilityIdentifier("sleepTimerMenu")
        .accessibilityLabel("睡眠定时")
        .accessibilityHint("设置到点或本集结束时暂停")
    }

    private var sleepTimerStatusRow: some View {
        VStack(alignment: .leading, spacing: TapeTheme.space1) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Label("睡眠定时", systemImage: "moon.zzz.fill")
                    .font(TapeType.caption)
                    .foregroundStyle(TapeTheme.ink)
                Text(sleepTimerStatus)
                    .font(TapeType.monoMeta)
                    .foregroundStyle(TapeTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("sleepTimerStatus")
                Spacer(minLength: 4)
                Button("取消") {
                    session.cancelSleepTimer()
                }
                .font(TapeType.monoMeta)
                .accessibilityIdentifier("sleepTimerCancelButton")
                .accessibilityHint("关闭睡眠定时")
            }
            if session.sleepTimer.mode == .endOfEpisode {
                Text("本集播完后暂停，不会自动播放下一集。")
                    .font(TapeType.captionSmall)
                    .foregroundStyle(TapeTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(TapeTheme.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TapeTheme.acid, in: RoundedRectangle(cornerRadius: TapeTheme.radiusSmall))
        .overlay {
            RoundedRectangle(cornerRadius: TapeTheme.radiusSmall)
                .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
        }
    }

    private var sleepTimerStatus: String {
        switch session.sleepTimer.mode {
        case .off, .endOfEpisode:
            session.sleepTimer.mode.displayName
        case .minutes:
            if let remaining = session.sleepTimer.remainingText {
                "\(session.sleepTimer.mode.displayName) · \(remaining)"
            } else {
                session.sleepTimer.mode.displayName
            }
        }
    }

    // MARK: - Chapters

    @ViewBuilder
    private var chapterSection: some View {
        if !playback.chapters.isEmpty {
            VStack(alignment: .leading, spacing: TapeTheme.space2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L10n.format("chapter.section", playback.chapters.count))
                        .font(TapeType.title3)
                        .foregroundStyle(TapeTheme.ink)
                        .accessibilityIdentifier("chapterSectionHeader")
                    Spacer(minLength: 4)
                    TapeKicker(text: "CHAPTERS")
                }

                VStack(spacing: TapeTheme.space1) {
                    ForEach(Array(playback.chapters.enumerated()), id: \.element.id) {
                        index,
                        chapter in
                        chapterRow(index: index, chapter: chapter)
                    }
                }
            }
            .padding(TapeTheme.space4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tapeCardSurface()
        }
    }

    private func chapterRow(index: Int, chapter: ChapterInfo) -> some View {
        let isCurrent = playback.currentChapterIndex == index
        return Button {
            playback.seek(to: chapter.start)
        } label: {
            HStack(spacing: TapeTheme.space2) {
                Text(String(format: "%02d", index + 1))
                    .font(TapeType.monoMicro)
                    .foregroundStyle(isCurrent ? TapeTheme.ink : TapeTheme.faint)
                    .frame(width: 22, alignment: .leading)
                Image(systemName: isCurrent ? "play.fill" : "circle.dotted")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isCurrent ? TapeTheme.ink : TapeTheme.faint)
                    .frame(width: 14)
                Text(chapter.title.isEmpty
                    ? L10n.string("chapter.untitled")
                    : chapter.title)
                    .font(TapeType.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(TapeTheme.ink)
                Spacer(minLength: 8)
                Text(formatTime(chapter.start))
                    .font(TapeType.monoMicro)
                    .foregroundStyle(isCurrent ? TapeTheme.ink : TapeTheme.muted)
            }
            .padding(.horizontal, TapeTheme.space2)
            // Apple's 44 pt minimum hit target: caption rows are far too
            // small to tap reliably (and fail UI-test synthesized events).
            .frame(minHeight: 44)
            // The Spacer above is transparent and not hit-testable, so taps
            // in the middle of the row (where the a11y frame's center sits)
            // would fall through to the List row and do nothing. Extend the
            // button's hit area to the whole row.
            .contentShape(Rectangle())
            .background(
                isCurrent ? TapeTheme.acid.opacity(0.7) : Color.clear,
                in: RoundedRectangle(cornerRadius: TapeTheme.radiusThumb)
            )
        }
        .buttonStyle(TapePlainPressStyle())
        .accessibilityIdentifier(isCurrent ? "chapterRowCurrent" : "chapterRow-\(index)")
        .accessibilityLabel(
            L10n.format("chapter.rowLabel", index + 1, chapter.title, formatTime(chapter.start))
        )
        .accessibilityAddTraits(isCurrent ? .isSelected : AccessibilityTraits())
    }

    // MARK: - Queue

    private var queueSection: some View {
        Section {
            if session.queue.isEmpty {
                TapeDashedCard {
                    VStack(spacing: TapeTheme.space3) {
                        Text("队列为空。使用「播放下一首」或「加入队列」添加条目。")
                            .font(TapeType.body)
                            .foregroundStyle(TapeTheme.muted)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("去资料库") {
                            onGoToLibrary()
                        }
                        .buttonStyle(TapeSecondaryButtonStyle())
                        .accessibilityIdentifier("queueEmptyLibraryButton")
                        .accessibilityHint("切换到资料库标签")
                    }
                    .frame(maxWidth: .infinity)
                }
                .tapeRowInsets(6)
            } else {
                ForEach(Array(session.queue.entries.enumerated()), id: \.element.id) { index, entry in
                    let item = itemByID[entry.itemID]
                    Button {
                        session.playQueueItem(itemID: entry.itemID)
                    } label: {
                        queueRow(index: index, entry: entry, item: item)
                    }
                    .buttonStyle(TapePlainPressStyle())
                    .tapeRowInsets(4)
                    .accessibilityIdentifier("queueRow-\(item?.title ?? entry.itemID.uuidString)")
                }
                .onMove { source, destination in
                    session.moveQueue(fromOffsets: source, toOffset: destination)
                }
                .onDelete { offsets in
                    for index in offsets.sorted(by: >) {
                        guard session.queue.entries.indices.contains(index) else { continue }
                        let entry = session.queue.entries[index]
                        session.removeQueueEntry(entryID: entry.id)
                    }
                }
            }
        } header: {
            queueHeader
        }
    }

    private func queueRow(index: Int, entry: QueueManager.Entry, item: MediaItem?) -> some View {
        let isCurrent = entry.itemID == session.queue.currentItemID
        return HStack(spacing: TapeTheme.space3) {
            Text(String(format: "%02d", index + 1))
                .font(TapeType.monoMicro)
                .foregroundStyle(isCurrent ? TapeTheme.ink : TapeTheme.faint)
                .frame(width: 24, alignment: .trailing)

            ZStack {
                RoundedRectangle(cornerRadius: TapeTheme.radiusThumb, style: .continuous)
                    .fill(isCurrent ? TapeTheme.acid : TapeTheme.violetSoft)
                    .frame(width: 34, height: 34)
                Text("#\(index + 1)")
                    .font(TapeType.monoMicro)
                    .foregroundStyle(TapeTheme.ink)
            }
            .overlay {
                RoundedRectangle(cornerRadius: TapeTheme.radiusThumb, style: .continuous)
                    .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item?.title ?? L10n.string("common.deletedItem"))
                    .font(TapeType.headline)
                    .foregroundStyle(TapeTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if isCurrent {
                    Text("当前")
                        .font(TapeType.monoMicro)
                        .foregroundStyle(TapeTheme.ink)
                } else {
                    Text(item?.durationText ?? "—")
                        .font(TapeType.monoMicro)
                        .foregroundStyle(TapeTheme.faint)
                }
            }

            Spacer(minLength: TapeTheme.space2)

            if !isCurrent {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(TapeTheme.ink)
                    .frame(width: 28, height: 28)
                    .background(TapeTheme.cream, in: Circle())
                    .overlay { Circle().strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke) }
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

    @ViewBuilder
    private var queueHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: TapeTheme.space2) {
                queueCountTitle
                ScrollView(.horizontal, showsIndicators: false) {
                    queueActions
                }
            }
            .textCase(nil)
            .padding(.horizontal, TapeTheme.screenPadding)
            .padding(.top, TapeTheme.space3)
        } else {
            HStack {
                queueCountTitle
                Spacer(minLength: 8)
                queueActions
            }
            .textCase(nil)
            .padding(.horizontal, TapeTheme.screenPadding)
            .padding(.top, TapeTheme.space3)
        }
    }

    private var queueCountTitle: some View {
        Text("队列 · \(session.queue.count)")
            .font(TapeType.title3)
            .foregroundStyle(TapeTheme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var queueActions: some View {
        HStack(spacing: TapeTheme.space2) {
            Button {
                session.toggleShuffle()
            } label: {
                Label(
                    session.queue.shuffleEnabled ? "随机：开" : "随机：关",
                    systemImage: "shuffle"
                )
                .labelStyle(.titleAndIcon)
                .font(TapeType.monoMicro)
                .foregroundStyle(TapeTheme.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    session.queue.shuffleEnabled ? TapeTheme.acid : TapeTheme.cream,
                    in: Capsule()
                )
                .overlay { Capsule().strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke) }
            }
            .buttonStyle(TapePlainPressStyle())
            .accessibilityIdentifier("queueShuffleButton")
            .accessibilityLabel("随机播放")
            .accessibilityValue(session.queue.shuffleEnabled ? "已开启" : "已关闭")
            .accessibilityHint("切换随机播放")

            Button {
                session.cycleRepeatMode()
            } label: {
                Label(
                    "循环：\(session.queue.repeatMode.displayName)",
                    systemImage: session.queue.repeatMode.symbolName
                )
                .labelStyle(.titleAndIcon)
                .font(TapeType.monoMicro)
                .foregroundStyle(TapeTheme.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    session.queue.repeatMode == .off ? TapeTheme.cream : TapeTheme.acid,
                    in: Capsule()
                )
                .overlay { Capsule().strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke) }
            }
            .buttonStyle(TapePlainPressStyle())
            .accessibilityIdentifier("queueRepeatButton")
            .accessibilityLabel("循环模式")
            .accessibilityValue(session.queue.repeatMode.displayName)
            .accessibilityHint("切换循环模式")

            Button(role: .destructive) {
                session.clearQueue()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(TapeTheme.stickerInk)
                    .frame(width: 26, height: 26)
                    .background(TapeTheme.coral, in: Circle())
                    .overlay { Circle().strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke) }
            }
            .buttonStyle(TapePlainPressStyle())
            .accessibilityIdentifier("queueClearButton")
            .accessibilityLabel("清空队列")
            .accessibilityHint("移除队列中的所有条目")
        }
    }

    // MARK: - Library

    private func libraryRow(_ item: MediaItem) -> some View {
        TapeRow(
            thumbText: String(item.title.prefix(1)),
            thumbFill: item.kind.isVideo ? TapeTheme.violetSoft : TapeTheme.peach,
            icon: item.kind.isVideo ? "film" : "waveform",
            title: item.title,
            subtitle: "\(item.kind.displayName) · \(item.folderName ?? L10n.string("playback.libraryFallback"))"
        )
    }

    // MARK: - Actions

    private func playDemo(name: String, fileExtension ext: String, title: String, kind: MediaKind) {
        localError = nil
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            localError = L10n.format("error.playback.missingDemo", "\(name).\(ext)")
            return
        }
        session.queue.clear()
        let item = PlaybackItem(
            title: title,
            subtitle: L10n.string("playback.builtInSubtitle"),
            fileURL: url,
            kind: kind
        )
        playback.load(item, autoplay: true)
    }

    private func playLibraryItem(_ item: MediaItem) {
        localError = nil
        guard item.fileURL != nil, !item.isMissing else {
            localError = L10n.format(
                "error.playback.resolveFile",
                item.relativePath
            )
            return
        }
        session.play(item: item)
        if let error = session.lastError {
            localError = error
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

private struct TapePlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(TapeTheme.ink)
            .frame(width: 64, height: 64)
            .background {
                Circle()
                    .fill(TapeTheme.acid)
                    .shadow(
                        color: TapeTheme.ink,
                        radius: 0,
                        x: configuration.isPressed ? 1 : 4,
                        y: configuration.isPressed ? 1 : 4
                    )
            }
            .overlay { Circle().strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke) }
            .offset(x: configuration.isPressed ? 3 : 0, y: configuration.isPressed ? 3 : 0)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(TapeTheme.press, value: configuration.isPressed)
    }
}

struct PlaybackArtworkView: View {
    let url: URL?
    let kind: MediaKind
    let size: CGFloat
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: kind.isVideo
                        ? [TapeTheme.coralSoft, TapeTheme.coral]
                        : [TapeTheme.violetSoft, TapeTheme.violet],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: kind.isVideo ? "film.fill" : "waveform")
                        .font(.system(size: size * 0.38))
                        .foregroundStyle(TapeTheme.stickerInk.opacity(0.9))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
        }
        .accessibilityHidden(true)
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            image = UIImage(contentsOfFile: url.path)
        }
    }
}
