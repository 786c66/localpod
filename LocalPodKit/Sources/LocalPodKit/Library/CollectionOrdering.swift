import Foundation

/// Pure ordering rules for the items inside one imported folder (a
/// collection). The chosen mode is persisted on `MediaCollection.sortModeRaw`;
/// manual order is persisted per item in `collectionPosition`.
public enum CollectionOrdering {
    /// Source-relative sort key. Shared by copied and linked items: both keep
    /// the path they had inside the imported folder, so a link and a copy of
    /// the same folder order identically.
    public static func sourceKey(for item: MediaItem) -> String {
        guard !item.relativeFolderPath.isEmpty else {
            return item.originalFileName
        }
        return "\(item.relativeFolderPath)/\(item.originalFileName)"
    }

    public static func sorted(
        _ items: [MediaItem],
        by mode: CollectionSortMode
    ) -> [MediaItem] {
        switch mode {
        case .natural:
            return items.sorted {
                let comparison = sourceKey(for: $0).localizedStandardCompare(sourceKey(for: $1))
                if comparison == .orderedSame {
                    return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
                return comparison == .orderedAscending
            }
        case .naturalDescending:
            return sorted(items, by: .natural).reversed()
        case .name:
            return items.sorted {
                let comparison = $0.title.localizedStandardCompare($1.title)
                if comparison == .orderedSame {
                    return sourceKey(for: $0).localizedStandardCompare(sourceKey(for: $1))
                        == .orderedAscending
                }
                return comparison == .orderedAscending
            }
        case .importedAt:
            return items.sorted {
                if $0.addedAt != $1.addedAt {
                    return $0.addedAt < $1.addedAt
                }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        case .manual:
            return items.sorted {
                if $0.collectionPosition != $1.collectionPosition {
                    return $0.collectionPosition < $1.collectionPosition
                }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        }
    }

    /// Rewrites positions from the given order. Callers persist the context.
    public static func assignManualPositions(_ orderedItems: [MediaItem]) {
        for (index, item) in orderedItems.enumerated() {
            item.collectionPosition = index
        }
    }

    /// Applies a List `.onMove` to the *visible* order. Returns the reordered
    /// items so the caller can assign positions and persist.
    public static func moving(
        _ items: [MediaItem],
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) -> [MediaItem] {
        var reordered = items
        reordered.moveElements(fromOffsets: source, toOffset: destination)
        return reordered
    }
}
