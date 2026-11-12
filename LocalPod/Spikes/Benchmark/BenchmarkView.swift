import Foundation
import SwiftUI
import SwiftData
import LocalPodKit

struct BenchmarkView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var benchmarkCount = 0
    @State private var lastPageCount = 0
    @State private var insertSeconds: Double?
    @State private var querySeconds: Double?
    @State private var cleanupSeconds: Double?
    @State private var status = L10n.string("benchmark.status.idle")
    @State private var isWorking = false
    @State private var errorMessage: String?

    var embedded = false

    var body: some View {
        Group {
            if embedded {
                content
            } else {
                NavigationStack { content }
            }
        }
    }

    private var content: some View {
        List {
                Section {
                    TapeCard {
                        VStack(alignment: .leading, spacing: TapeTheme.space3) {
                            HStack(alignment: .center, spacing: TapeTheme.space2) {
                                TapeSticker(
                                    text: "5K",
                                    fill: TapeTheme.acid,
                                    foreground: TapeTheme.ink,
                                    angle: -4
                                )
                                Spacer(minLength: TapeTheme.space2)
                                Text("\(benchmarkCount) 条")
                                    .font(TapeType.monoMeta)
                                    .foregroundStyle(TapeTheme.faint)
                            }

                            infoRow("当前基准条目", "\(benchmarkCount) 条")

                            HStack(alignment: .firstTextBaseline, spacing: TapeTheme.space2) {
                                Text("状态")
                                    .font(TapeType.bodySmall)
                                    .foregroundStyle(TapeTheme.muted)
                                Spacer(minLength: TapeTheme.space2)
                                Text(status)
                                    .font(TapeType.monoMeta)
                                    .foregroundStyle(TapeTheme.ink)
                                    .multilineTextAlignment(.trailing)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("benchmarkStatus")
                            }

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(TapeType.captionSmall)
                                    .foregroundStyle(TapeTheme.coral)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .tapeRowInsets(6)
                } header: {
                    sectionHeader("SwiftData 5k 基准", kicker: "BENCHMARK")
                } footer: {
                    sectionFooter("M0 只验证插入、查询与 5k 列表滚动；如果主界面卡顿，后续只做批处理/索引/分页优化，不更换持久化框架。")
                }

                Section {
                    Button {
                        runInsert()
                    } label: {
                        Label("插入 5000 条", systemImage: "square.stack.3d.up")
                    }
                    .buttonStyle(TapePrimaryButtonStyle())
                    .disabled(isWorking || benchmarkCount > 0)
                    .opacity(isWorking || benchmarkCount > 0 ? 0.5 : 1)
                    .accessibilityIdentifier("benchmarkInsertButton")
                    .tapeRowInsets(4)

                    Button {
                        runQuery()
                    } label: {
                        Label("查询 100 条 + 总数", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(TapeSecondaryButtonStyle())
                    .disabled(isWorking || benchmarkCount == 0)
                    .opacity(isWorking || benchmarkCount == 0 ? 0.5 : 1)
                    .tapeRowInsets(4)

                    benchmarkListLink

                    Button(role: .destructive) {
                        runCleanup()
                    } label: {
                        Label("清理基准数据", systemImage: "trash")
                    }
                    .buttonStyle(TapeDestructiveButtonStyle())
                    .disabled(isWorking || benchmarkCount == 0)
                    .opacity(isWorking || benchmarkCount == 0 ? 0.5 : 1)
                    .tapeRowInsets(4)
                } header: {
                    sectionHeader("操作", kicker: "ACTIONS")
                }

                Section {
                    TapeCard {
                        VStack(spacing: TapeTheme.space2) {
                            infoRow("插入 5000 条", format(insertSeconds))
                            TapeHairline()
                            infoRow("查询 100 条 + 总数", format(querySeconds))
                            TapeHairline()
                            infoRow(
                                "列表本次读取",
                                lastPageCount == 0
                                    ? "—"
                                    : L10n.format("benchmark.lastPageCount", lastPageCount)
                            )
                            TapeHairline()
                            infoRow("清理", format(cleanupSeconds))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .tapeRowInsets(6)
                } header: {
                    sectionHeader("结果", kicker: "RESULTS")
                }

                Section {
                    TapeCard {
                        VStack(alignment: .leading, spacing: TapeTheme.space2) {
                            Text("插入使用主线程 ModelContext 一次性保存，模拟最保守的路径；真实 M1 导入会改为后台 ModelActor + 分批保存。")
                            Text("列表页用 @Query 拉取全部基准条目，验证 SwiftUI List 的懒加载滚动。")
                        }
                        .font(TapeType.caption)
                        .foregroundStyle(TapeTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .tapeRowInsets(6)
                } header: {
                    sectionHeader("说明", kicker: "NOTES")
                }
            }
            .listStyle(.plain)
            .tapeScreen()
            .navigationTitle("SwiftData 基准")
            .tapeNavigationChrome()
            .task {
                refreshCount()
            }
    }

    private var benchmarkListLink: some View {
        NavigationLink {
            BenchmarkListView()
        } label: {
            HStack(spacing: TapeTheme.space3) {
                Image(systemName: "list.number")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TapeTheme.ink)
                    .frame(width: 36, height: 36)
                    .background(
                        TapeTheme.violetSoft,
                        in: RoundedRectangle(cornerRadius: TapeTheme.radiusThumb, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: TapeTheme.radiusThumb, style: .continuous)
                            .strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke)
                    }
                Text("打开 5000 条列表")
                    .font(TapeType.headline)
                    .foregroundStyle(TapeTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: TapeTheme.space2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
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
            .opacity(benchmarkCount == 0 ? 0.5 : 1)
        }
        .buttonStyle(TapePlainPressStyle())
        .disabled(benchmarkCount == 0)
        .accessibilityLabel("打开 5000 条列表")
        .accessibilityIdentifier("benchmarkListLink")
        .tapeRowInsets(4)
    }

    private func sectionHeader(_ title: String, kicker: String) -> some View {
        TapeSectionHeader(title: title, kicker: kicker)
            .textCase(nil)
            .padding(.horizontal, TapeTheme.screenPadding)
            .padding(.top, TapeTheme.space3)
            .padding(.bottom, TapeTheme.space1)
    }

    private func sectionFooter(_ text: String) -> some View {
        Text(text)
            .font(TapeType.captionSmall)
            .foregroundStyle(TapeTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, TapeTheme.space4)
            .padding(.top, TapeTheme.space1)
            .listRowBackground(Color.clear)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TapeTheme.space2) {
            Text(label)
                .font(TapeType.bodySmall)
                .foregroundStyle(TapeTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: TapeTheme.space2)
            Text(value)
                .font(TapeType.monoMeta)
                .foregroundStyle(TapeTheme.ink)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sourcePredicate: Predicate<MediaItem> {
        #Predicate<MediaItem> { $0.sourceRaw == "benchmark" }
    }

    private func runInsert() {
        guard !isWorking, benchmarkCount == 0 else { return }
        isWorking = true
        status = L10n.string("benchmark.status.inserting")
        errorMessage = nil
        Task { @MainActor in
            await Task.yield()
            let started = Date()
            for index in 0..<5_000 {
                modelContext.insert(MediaItem(
                    title: "Benchmark \(index)",
                    relativePath: "benchmark/\(index)",
                    kind: index.isMultiple(of: 2) ? .audio : .video,
                    fileExtension: index.isMultiple(of: 2) ? "m4a" : "mp4",
                    byteSize: Int64(index),
                    folderName: "benchmark",
                    source: .benchmark
                ))
            }
            do {
                try modelContext.save()
                insertSeconds = Date().timeIntervalSince(started)
                status = L10n.string("benchmark.status.inserted")
            } catch {
                errorMessage = L10n.format(
                    "benchmark.error.insert",
                    error.localizedDescription
                )
                status = L10n.string("benchmark.status.failed")
            }
            refreshCount()
            isWorking = false
        }
    }

    private func runQuery() {
        guard !isWorking, benchmarkCount > 0 else { return }
        isWorking = true
        status = L10n.string("benchmark.status.querying")
        errorMessage = nil
        Task { @MainActor in
            await Task.yield()
            let started = Date()
            do {
                let count = try modelContext.fetchCount(FetchDescriptor<MediaItem>(predicate: sourcePredicate))
                var descriptor = FetchDescriptor<MediaItem>(
                    predicate: sourcePredicate,
                    sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
                )
                descriptor.fetchLimit = 100
                let page = try modelContext.fetch(descriptor)
                querySeconds = Date().timeIntervalSince(started)
                lastPageCount = page.count
                status = L10n.format("benchmark.status.queried", count)
            } catch {
                errorMessage = L10n.format(
                    "benchmark.error.query",
                    error.localizedDescription
                )
                status = L10n.string("benchmark.status.failed")
            }
            isWorking = false
        }
    }

    private func runCleanup() {
        guard !isWorking, benchmarkCount > 0 else { return }
        isWorking = true
        status = L10n.string("benchmark.status.cleaning")
        errorMessage = nil
        Task { @MainActor in
            await Task.yield()
            let started = Date()
            do {
                let items = try modelContext.fetch(FetchDescriptor<MediaItem>(predicate: sourcePredicate))
                for item in items {
                    modelContext.delete(item)
                }
                try modelContext.save()
                cleanupSeconds = Date().timeIntervalSince(started)
                lastPageCount = 0
                status = L10n.string("benchmark.status.cleaned")
            } catch {
                errorMessage = L10n.format(
                    "benchmark.error.cleanup",
                    error.localizedDescription
                )
                status = L10n.string("benchmark.status.failed")
            }
            refreshCount()
            isWorking = false
        }
    }

    private func refreshCount() {
        benchmarkCount = (try? modelContext.fetchCount(
            FetchDescriptor<MediaItem>(predicate: sourcePredicate)
        )) ?? 0
    }

    private func format(_ seconds: Double?) -> String {
        guard let seconds else { return "—" }
        if seconds < 1 {
            return String(format: "%.0f ms", seconds * 1_000)
        }
        return String(format: "%.2f s", seconds)
    }
}

struct BenchmarkListView: View {
    @Query(
        filter: #Predicate<MediaItem> { $0.sourceRaw == "benchmark" },
        sort: \MediaItem.addedAt,
        order: .forward
    )
    private var items: [MediaItem]

    var body: some View {
        List(items) { item in
            TapeRow(
                thumbText: "",
                thumbFill: item.kind.isVideo ? TapeTheme.peach : TapeTheme.cream,
                icon: item.kind.isVideo ? "film" : "waveform",
                title: item.title,
                subtitle: "\(item.kind.displayName) · \(ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file))",
                showsTrailing: false
            )
            .tapeRowInsets(4)
        }
        .listStyle(.plain)
        .tapeScreen()
        .navigationTitle("\(items.count) 条")
        .tapeNavigationChrome()
    }
}
