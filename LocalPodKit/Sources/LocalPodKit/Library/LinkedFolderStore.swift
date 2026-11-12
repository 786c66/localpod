import Foundation
import SwiftData

/// Kit-level errors for linked folders. Each case maps to a localized message
/// through `LocalPodLocalization`; the app surfaces `localizedDescription`.
public enum LinkedFolderError: Error, Sendable, Equatable {
    /// The bookmark no longer resolves: the folder was moved, renamed, or
    /// deleted. The user must re-pick the folder (relink).
    case staleBookmark
    /// The bookmark data could not be turned back into a URL.
    case unreadable
    /// The folder resolved but is not accessible (permissions/iCloud offline).
    case accessDenied

    public var localizedDescription: String {
        switch self {
        case .staleBookmark:
            LocalPodLocalization.string("linkedFolder.error.staleBookmark")
        case .unreadable:
            LocalPodLocalization.string("linkedFolder.error.unreadable")
        case .accessDenied:
            LocalPodLocalization.string("linkedFolder.error.accessDenied")
        }
    }
}

/// What one linked folder learned from a rescan. `removedFiles` is
/// informational: source deletions never delete local copies.
public struct LinkedFolderScanDiff: Sendable, Equatable {
    public let newFiles: [ScannedFile]
    public let removedPaths: [String]

    public init(newFiles: [ScannedFile], removedPaths: [String]) {
        self.newFiles = newFiles
        self.removedPaths = removedPaths
    }
}

/// Pure logic for linking a source folder and rescanning it incrementally.
///
/// All state lives in the `LinkedFolder` SwiftData row (the bookmark plus
/// bookkeeping); this type only supplies stateless helpers so every step can
/// be unit-tested without a document picker or security scope.
public enum LinkedFolderStore {

    // MARK: - Bookmarks

    /// Creates bookmark data for a folder URL. The URL does not need to be
    /// security-scoped (app-internal temp folders work too); for
    /// document-picker URLs the caller keeps the security scope alive until
    /// this call returns.
    public static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData()
    }

    /// Result of resolving bookmark data. `stop` must be called exactly once
    /// (ideally via `withAccess`), regardless of whether the caller still
    /// needs the URL, to release the security scope.
    public struct ResolvedAccess: Sendable {
        public let url: URL
        /// True when the stored bookmark was stale but the URL still resolved.
        /// Callers should persist `refreshedBookmark` so the next launch does
        /// not have to repair it again.
        public let isStale: Bool
        public let refreshedBookmark: Data?
        public let stop: @Sendable () -> Void

        public init(
            url: URL,
            isStale: Bool = false,
            refreshedBookmark: Data? = nil,
            stop: @escaping @Sendable () -> Void
        ) {
            self.url = url
            self.isStale = isStale
            self.refreshedBookmark = refreshedBookmark
            self.stop = stop
        }

        /// Runs `body` with the folder accessible, releasing the security
        /// scope in all paths. Use this instead of touching `url`/`stop`
        /// directly.
        public func withAccess<T>(_ body: (URL) throws -> T) rethrows -> T {
            defer { stop() }
            return try body(url)
        }
    }

    /// Resolves bookmark data back to a folder URL and starts security-scoped
    /// access. A resolve failure is mapped to `.staleBookmark` (a missing
    /// folder and unreadable bookmark data both need the same user action:
    /// re-pick the folder). Callers must consume the result through
    /// `withAccess` (or call `stop`) to release the security scope.
    ///
    /// The stale bit alone is not reliable on every OS: for app-internal
    /// (non-security-scoped) bookmarks some runtimes throw "file doesn't
    /// exist" instead of setting `bookmarkDataIsStale`, and some simulators
    /// never set the flag at all. An existence check therefore has the final
    /// word on staleness in both directions.
    public static func resolve(_ bookmarkData: Data) -> Result<ResolvedAccess, LinkedFolderError> {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            guard FileManager.default.fileExists(atPath: url.path) else {
                // The source was moved, renamed, or deleted. The bookmark may
                // not flag this on every runtime, so existence has the final
                // word.
                return .failure(.staleBookmark)
            }

            let didStart = url.startAccessingSecurityScopedResource()
            let stop: @Sendable () -> Void
            if didStart {
                stop = { url.stopAccessingSecurityScopedResource() }
            } else {
                stop = {}
            }

            // Bookmark resolved but access was refused (or none was needed).
            // App-internal URLs legitimately return false here and remain
            // readable, so probe before reporting a denial.
            if !didStart, !FileManager.default.isReadableFile(atPath: url.path) {
                return .failure(.accessDenied)
            }

            // A stale bookmark that still resolves is repaired here: creating
            // fresh bookmark data while the security scope is active gives the
            // caller something durable to persist (the "re-authorize" path
            // that does not require the user to re-pick the folder).
            var refreshed: Data?
            if isStale {
                refreshed = try? url.bookmarkData()
            }

            return .success(ResolvedAccess(
                url: url,
                isStale: isStale,
                refreshedBookmark: refreshed,
                stop: stop
            ))
        } catch {
            return .failure(.staleBookmark)
        }
    }

    // MARK: - Incremental diff

    /// Keys for the incremental rescan. Imported files are COPIES: a
    /// `MediaItem.relativePath` points into the app sandbox (`Media/<uuid>.<ext>`),
    /// so it can never match a source path. The stable link between a library
    /// item and its source file is therefore
    /// `relativeFolderPath + "/" + originalFileName` — the path the file had
    /// inside the source folder when it was imported.
    ///
    /// - `existingSourceKeys`: one key per library item that came from this
    ///   folder (see `existingSourceKey(relativeFolderPath:originalFileName:)`).
    /// - `scannedFiles`: the current scan of the source folder, whose
    ///   `relativePath` values are source-relative.
    ///
    /// - Returns: files to import this pass, and source-relative paths that
    ///   disappeared. A renamed/moved file appears in both lists (old name
    ///   removed, new name new) and re-imports as a new item.
    public static func diff(
        existingSourceKeys: Set<String>,
        scannedFiles: [ScannedFile]
    ) -> LinkedFolderScanDiff {
        var scannedKeys = Set<String>()
        var newFiles: [ScannedFile] = []
        for file in scannedFiles {
            let key = sourceKey(
                relativeFolderPath: file.relativeFolderPath,
                fileName: file.originalFileName
            )
            scannedKeys.insert(key)
            if !existingSourceKeys.contains(key) {
                newFiles.append(file)
            }
        }
        let removedPaths = existingSourceKeys
            .subtracting(scannedKeys)
            .sorted()
        return LinkedFolderScanDiff(newFiles: newFiles, removedPaths: removedPaths)
    }

    /// Builds the source key for a library item from its persisted fields.
    /// Both inputs are the values stored on `MediaItem` at import time.
    public static func existingSourceKey(
        relativeFolderPath: String,
        originalFileName: String
    ) -> String {
        sourceKey(relativeFolderPath: relativeFolderPath, fileName: originalFileName)
    }

    private static func sourceKey(relativeFolderPath: String, fileName: String) -> String {
        guard !relativeFolderPath.isEmpty else { return fileName }
        return "\(relativeFolderPath)/\(fileName)"
    }

    // MARK: - Row bookkeeping

    /// Source keys of the items that reference `folderID` in place. This is
    /// the precise ownership set for linked folders (folder names may repeat).
    public static func existingSourceKeys(
        forLinkedFolderID folderID: UUID,
        in context: ModelContext
    ) throws -> Set<String> {
        let items = try context.fetch(FetchDescriptor<MediaItem>(
            predicate: #Predicate { $0.linkedFolderID == folderID }
        ))
        return Set(items.map {
            existingSourceKey(
                relativeFolderPath: $0.relativeFolderPath,
                originalFileName: $0.originalFileName
            )
        })
    }

    /// Builds the set of source keys a folder still "owns" in the library.
    ///
    /// Ownership is matched on `folderName == rootName` plus the source key
    /// (`relativeFolderPath` + `originalFileName`). Folder names can collide
    /// between separately imported folders, but the combination stays correct
    /// for the diff: worst case an unchanged file with the same name+path is
    /// treated as already imported, which is exactly what SHA-256 dedup would
    /// do anyway.
    public static func existingSourceKeys(
        forLinkedFolderNamed rootName: String,
        in context: ModelContext
    ) throws -> Set<String> {
        let items = try context.fetch(FetchDescriptor<MediaItem>())
        var keys = Set<String>()
        for item in items where item.folderName == rootName {
            keys.insert(existingSourceKey(
                relativeFolderPath: item.relativeFolderPath,
                originalFileName: item.originalFileName
            ))
        }
        return keys
    }

    /// Records one completed (not cancelled) rescan on the row. `removedCount`
    /// is informational: source deletions never remove local copies.
    public static func recordScan(
        _ folder: LinkedFolder,
        importedCount: Int,
        removedCount: Int,
        scannedAt: Date = Date()
    ) {
        folder.lastScannedAt = scannedAt
        folder.lastImportedCount = importedCount
        folder.lastRemovedCount = removedCount
        folder.isStale = false
    }

    /// Marks the link stale after a failed bookmark resolve.
    public static func markStale(_ folder: LinkedFolder) {
        folder.isStale = true
    }

    /// Replaces the bookmark after the user re-picked the folder and clears
    /// the stale flag.
    public static func relink(
        _ folder: LinkedFolder,
        bookmarkData: Data
    ) {
        folder.bookmarkData = bookmarkData
        folder.isStale = false
    }
}
