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
    @State private var status = "未运行"
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("当前基准条目", value: "\(benchmarkCount) 条")
                    LabeledContent("状态", value: status)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("benchmarkStatus")
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("SwiftData 5k 基准")
                } footer: {
                    Text("M0 只验证插入、查询与 5k 列表滚动；如果主界面卡顿，后续只做批处理/索引/分页优化，不更换持久化框架。")
                }

                Section("操作") {
                    Button {
                        runInsert()
                    } label: {
                        Label("插入 5000 条", systemImage: "square.stack.3d.up")
                    }
                    .disabled(isWorking || benchmarkCount > 0)
                    .accessibilityIdentifier("benchmarkInsertButton")

                    Button {
                        runQuery()
                    } label: {
                        Label("查询 100 条 + 总数", systemImage: "magnifyingglass")
                    }
                    .disabled(isWorking || benchmarkCount == 0)

                    NavigationLink {
                        BenchmarkListView()
                    } label: {
                        Label("打开 5000 条列表", systemImage: "list.number")
                    }
                    .disabled(benchmarkCount == 0)
                    .accessibilityIdentifier("benchmarkListLink")

                    Button(role: .destructive) {
                        runCleanup()
                    } label: {
                        Label("清理基准数据", systemImage: "trash")
                    }
                    .disabled(isWorking || benchmarkCount == 0)
                }

                Section("结果") {
                    LabeledContent("插入 5000 条", value: format(insertSeconds))
                    LabeledContent("查询 100 条 + 总数", value: format(querySeconds))
                    LabeledContent("列表本次读取", value: lastPageCount == 0 ? "—" : "\(lastPageCount) 条")
                    LabeledContent("清理", value: format(cleanupSeconds))
                }

                Section("说明") {
                    Text("插入使用主线程 ModelContext 一次性保存，模拟最保守的路径；真实 M1 导入会改为后台 ModelActor + 分批保存。")
                    Text("列表页用 @Query 拉取全部基准条目，验证 SwiftUI List 的懒加载滚动。")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("SwiftData 基准")
            .task {
                refreshCount()
            }
        }
    }

    private var sourcePredicate: Predicate<MediaItem> {
        #Predicate<MediaItem> { $0.sourceRaw == "benchmark" }
    }

    private func runInsert() {
        guard !isWorking, benchmarkCount == 0 else { return }
        isWorking = true
        status = "插入中…"
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
                status = "插入完成"
            } catch {
                errorMessage = "插入失败：\(error.localizedDescription)"
                status = "失败"
            }
            refreshCount()
            isWorking = false
        }
    }

    private func runQuery() {
        guard !isWorking, benchmarkCount > 0 else { return }
        isWorking = true
        status = "查询中…"
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
                status = "查询完成（总数 \(count)）"
            } catch {
                errorMessage = "查询失败：\(error.localizedDescription)"
                status = "失败"
            }
            isWorking = false
        }
    }

    private func runCleanup() {
        guard !isWorking, benchmarkCount > 0 else { return }
        isWorking = true
        status = "清理中…"
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
                status = "清理完成"
            } catch {
                errorMessage = "清理失败：\(error.localizedDescription)"
                status = "失败"
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
            HStack(spacing: 12) {
                Image(systemName: item.kind.isVideo ? "film" : "waveform")
                    .foregroundStyle(item.kind.isVideo ? .orange : .indigo)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                    Text("\(item.kind.displayName) · \(ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("\(items.count) 条")
        .navigationBarTitleDisplayMode(.inline)
    }
}
