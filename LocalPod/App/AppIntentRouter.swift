import Foundation
import Observation

/// App-level bridge from App Intent routing to SwiftUI navigation. RootView
/// consumes the persisted request and publishes a collection request here;
/// LibraryView owns the actual push so TabView selection and navigation stay
/// decoupled.
@MainActor
@Observable
final class AppIntentRouter {
    struct CollectionRequest: Equatable, Identifiable {
        let id: UUID
        let name: String
    }

    private(set) var collectionRequest: CollectionRequest?

    func requestCollection(named name: String) {
        collectionRequest = CollectionRequest(id: UUID(), name: name)
    }

    func consumeCollectionRequest(id: UUID) {
        guard collectionRequest?.id == id else { return }
        collectionRequest = nil
    }
}
