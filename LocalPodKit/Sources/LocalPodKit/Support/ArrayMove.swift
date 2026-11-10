import Foundation

/// `Array.move(fromOffsets:toOffset:)` lives in SwiftUI. LocalPodKit avoids a
/// SwiftUI dependency, so its persisted reorder operations use this helper.
extension Array {
    mutating func moveElements(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().compactMap { indices in
            indices < count ? self[indices] : nil
        }
        var remaining = self
        for index in source.sorted(by: >) where index < remaining.count {
            remaining.remove(at: index)
        }
        let removedBeforeDestination = source.filter { $0 < destination }.count
        let insertionIndex = Swift.min(
            Swift.max(destination - removedBeforeDestination, 0),
            remaining.count
        )
        remaining.insert(contentsOf: moving, at: insertionIndex)
        self = remaining
    }
}
