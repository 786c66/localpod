import AppIntents
import Foundation
import LocalPodKit

/// Shortcuts/Siri entry point: continue the persisted queue or the most
/// recent unfinished item. The request is persisted and consumed by RootView
/// after the app's playback session has attached, so cold launches behave the
/// same as warm ones.
struct ContinuePlaybackIntent: AppIntent {
    static var title: LocalizedStringResource { "继续播放" }
    static var description: IntentDescription? {
        IntentDescription("继续播放队列中的条目，或最近未听完的内容。")
    }
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        AppIntentLaunchRequestStore.save(.continuePlayback)
        return .result()
    }
}

/// Name-backed entity for the collection parameter. App Shortcut phrases only
/// accept `AppEntity`/`AppEnum` parameters (the metadata processor rejects
/// `String`), so the entity carries the free-form name through Siri.
struct CollectionEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "合集" }
    static var defaultQuery: CollectionEntityQuery { CollectionEntityQuery() }

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct CollectionEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [CollectionEntity] {
        identifiers.map { CollectionEntity(id: $0, name: $0) }
    }

    func entities(matching string: String) async throws -> [CollectionEntity] {
        let name = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return [] }
        return [CollectionEntity(id: name, name: name)]
    }
}

/// Shortcuts/Siri entry point: open a library collection by name. The name is
/// resolved against `MediaCollection.nameKey` so spaces/case/width variants
/// match the same way collection merges do.
struct OpenCollectionIntent: AppIntent {
    static var title: LocalizedStringResource { "打开合集" }
    static var description: IntentDescription? {
        IntentDescription("在资料库中打开指定的合集。")
    }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "合集名称")
    var collectionName: CollectionEntity

    init() {}

    init(collectionName: String) {
        self.collectionName = CollectionEntity(id: collectionName, name: collectionName)
    }

    func perform() async throws -> some IntentResult {
        let name = collectionName.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .result() }
        AppIntentLaunchRequestStore.save(.openCollection(name: name))
        return .result()
    }
}

struct LocalPodShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ContinuePlaybackIntent(),
            phrases: [
                "继续播放 \(.applicationName)",
                "用 \(.applicationName) 继续播放"
            ],
            shortTitle: "继续播放",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: OpenCollectionIntent(),
            phrases: [
                "打开 \(.applicationName) 合集 \(\.$collectionName)",
                "在 \(.applicationName) 中打开合集 \(\.$collectionName)"
            ],
            shortTitle: "打开合集",
            systemImageName: "square.stack.3d.up"
        )
    }
}
