import Foundation

/// Tracks top-level items in `Documents/Import` across scans and reports only
/// items whose content has stopped changing.
///
/// An item becomes stable when two consecutive observations at least
/// `minimumObservationInterval` apart saw identical recursive metadata and the
/// newest modification date is at least `minimumQuietPeriod` old. A file's
/// metadata is its size and modification date. A folder's metadata is the
/// relative path, size and modification date of every regular file in its
/// tree, so a folder that is still being copied never becomes stable.
///
/// The first observation of an item is never stable. The tracker never
/// deletes or modifies inbox items; callers decide when it is safe to consume
/// a stable URL. State is lock-protected so the app can call it from the main
/// actor, and `now` is injectable so tests do not need wall-clock waits.
public final class ImportInboxStability: @unchecked Sendable {
    public struct Result: Sendable, Equatable {
        public let stableURLs: [URL]
        public let unstableCount: Int

        public init(stableURLs: [URL], unstableCount: Int) {
            self.stableURLs = stableURLs
            self.unstableCount = unstableCount
        }

        public var isEmpty: Bool { stableURLs.isEmpty }
    }

    public let minimumObservationInterval: TimeInterval
    public let minimumQuietPeriod: TimeInterval

    private struct TreeEntry: Equatable {
        let relativePath: String
        let isDirectory: Bool
        let byteSize: Int64
        let modifiedAt: Date?
    }

    private enum Metadata: Equatable {
        case file(byteSize: Int64, modifiedAt: Date?)
        case folder(entries: [TreeEntry])
    }

    private struct Observation {
        let metadata: Metadata
        let newestModificationDate: Date?
    }

    private struct Snapshot {
        let observation: Observation
        /// When the current metadata was first observed. Kept fixed while the
        /// metadata is unchanged so frequent scans cannot postpone stability.
        let unchangedSince: Date
        var isStable: Bool
    }

    private enum StabilityError: Error {
        case unreadableTree(URL)
    }

    private static let topLevelKeys: [URLResourceKey] = [
        .isDirectoryKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .fileSizeKey,
        .contentModificationDateKey
    ]

    private static let treeKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .fileSizeKey,
        .contentModificationDateKey
    ]

    private let lock = NSLock()
    private var snapshots: [String: Snapshot] = [:]

    public init(
        minimumObservationInterval: TimeInterval = 1,
        minimumQuietPeriod: TimeInterval = 2
    ) {
        self.minimumObservationInterval = max(0, minimumObservationInterval)
        self.minimumQuietPeriod = max(0, minimumQuietPeriod)
    }

    /// Observes every visible top-level item in `directoryURL`. Hidden items
    /// (including in-flight staging temporaries) are ignored. Items that
    /// cannot be read are reported as unstable and their previous stable state
    /// is discarded, so an unreadable tree can never be consumed.
    public func evaluate(in directoryURL: URL, now: Date = Date()) throws -> Result {
        let directory = directoryURL.standardizedFileURL
        let fileManager = FileManager.default
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Self.topLevelKeys,
            options: [.skipsHiddenFiles]
        )

        lock.lock()
        defer { lock.unlock() }

        var nextSnapshots: [String: Snapshot] = [:]
        var stableURLs: [URL] = []
        var unstableCount = 0

        for url in urls {
            let item = url.standardizedFileURL
            let key = item.path

            guard let observation = try? Self.observe(item, fileManager: fileManager) else {
                // Symlinks, special files and unreadable items are never
                // stable, and any earlier snapshot must not be reused.
                unstableCount += 1
                continue
            }

            var snapshot: Snapshot
            if var previous = snapshots[key],
               previous.observation.metadata == observation.metadata {
                if !previous.isStable,
                   now.timeIntervalSince(previous.unchangedSince) >= minimumObservationInterval,
                   Self.isQuiet(observation, now: now, minimumQuietPeriod: minimumQuietPeriod) {
                    previous.isStable = true
                }
                snapshot = previous
            } else {
                snapshot = Snapshot(
                    observation: observation,
                    unchangedSince: now,
                    isStable: false
                )
            }

            nextSnapshots[key] = snapshot
            if snapshot.isStable {
                stableURLs.append(item)
            } else {
                unstableCount += 1
            }
        }

        snapshots = nextSnapshots

        stableURLs.sort {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        return Result(stableURLs: stableURLs, unstableCount: unstableCount)
    }

    private static func observe(
        _ url: URL,
        fileManager: FileManager
    ) throws -> Observation? {
        let values = try url.resourceValues(forKeys: Set(topLevelKeys))
        if values.isSymbolicLink == true {
            return nil
        }
        if values.isDirectory == true {
            return try observeFolder(url, rootValues: values, fileManager: fileManager)
        }
        guard values.isRegularFile == true else {
            return nil
        }
        let modifiedAt = values.contentModificationDate
        return Observation(
            metadata: .file(
                byteSize: Int64(values.fileSize ?? 0),
                modifiedAt: modifiedAt
            ),
            newestModificationDate: modifiedAt
        )
    }

    private static func observeFolder(
        _ root: URL,
        rootValues: URLResourceValues,
        fileManager: FileManager
    ) throws -> Observation {
        var entries: [TreeEntry] = []
        var newest = rootValues.contentModificationDate
        var stack: [(url: URL, relativePrefix: String)] = [(root, "")]

        while let (directory, prefix) = stack.popLast() {
            let children: [URL]
            do {
                children = try fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: Array(treeKeys),
                    options: []
                )
            } catch {
                throw StabilityError.unreadableTree(directory)
            }

            for child in children {
                let relativePath = prefix.isEmpty
                    ? child.lastPathComponent
                    : prefix + "/" + child.lastPathComponent

                let values: URLResourceValues
                do {
                    values = try child.resourceValues(forKeys: treeKeys)
                } catch {
                    throw StabilityError.unreadableTree(child)
                }

                if values.isSymbolicLink == true {
                    continue
                }
                if values.isDirectory == true {
                    // Include directories in the metadata so an empty folder
                    // that is still being populated cannot look stable.
                    entries.append(TreeEntry(
                        relativePath: relativePath,
                        isDirectory: true,
                        byteSize: 0,
                        modifiedAt: values.contentModificationDate
                    ))
                    stack.append((child, relativePath))
                    newest = newestDate(newest, values.contentModificationDate)
                } else if values.isRegularFile == true {
                    let modifiedAt = values.contentModificationDate
                    entries.append(TreeEntry(
                        relativePath: relativePath,
                        isDirectory: false,
                        byteSize: Int64(values.fileSize ?? 0),
                        modifiedAt: modifiedAt
                    ))
                    newest = newestDate(newest, modifiedAt)
                }
            }
        }

        entries.sort { $0.relativePath < $1.relativePath }
        return Observation(
            metadata: .folder(entries: entries),
            newestModificationDate: newest
        )
    }

    private static func newestDate(_ current: Date?, _ candidate: Date?) -> Date? {
        guard let candidate else { return current }
        guard let current else { return candidate }
        return max(current, candidate)
    }

    private static func isQuiet(
        _ observation: Observation,
        now: Date,
        minimumQuietPeriod: TimeInterval
    ) -> Bool {
        guard let newest = observation.newestModificationDate else {
            return false
        }
        return now.timeIntervalSince(newest) >= minimumQuietPeriod
    }
}
