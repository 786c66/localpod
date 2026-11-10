import Foundation

public struct ImportEngine: Sendable {
    public struct Options: Sendable {
        public var limits: FolderScanner.Limits
        public var chunkSize: Int

        public init(
            limits: FolderScanner.Limits = FolderScanner.Limits(),
            chunkSize: Int = 1 << 20
        ) {
            self.limits = limits
            self.chunkSize = chunkSize
        }
    }

    private let scanner: FolderScanner
    private let copier: ChunkedFileCopier

    public init(
        scanner: FolderScanner = FolderScanner(),
        copier: ChunkedFileCopier = ChunkedFileCopier()
    ) {
        self.scanner = scanner
        self.copier = copier
    }

    /// Scans a folder (or a single file) and copies supported media into a
    /// fresh destination. Files are copied to a `.part` file first and moved
    /// into place atomically. The caller owns the security-scoped access.
    public func scanAndImport(
        rootURL: URL,
        destinationRootURL: URL,
        options: Options = Options(),
        progress: @escaping @Sendable (ImportProgress) -> Void = { _ in }
    ) async throws -> ImportRunResult {
        let startedAt = Date()
        progress(ImportProgress(phase: .scanning))

        let scanClock = ContinuousClock()
        let scanStart = scanClock.now
        let scan = try scanner.scan(rootURL: rootURL, limits: options.limits)
        let scanDuration = scanStart.duration(to: scanClock.now)

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationRootURL, withIntermediateDirectories: true)

        var importedFiles: [ImportedFile] = []
        var issues = scan.issues
        var completedBytes: Int64 = 0
        var cancelled = false
        let copyClock = ContinuousClock()
        let copyStart = copyClock.now

        for file in scan.files {
            if Task.isCancelled {
                cancelled = true
                break
            }

            let destinationURL: URL
            do {
                destinationURL = try Self.uniqueDestination(
                    for: file.relativePath,
                    under: destinationRootURL,
                    fileManager: fileManager
                )
            } catch {
                issues.append(ScanIssue(
                    relativePath: file.relativePath,
                    message: error.localizedDescription
                ))
                continue
            }

            let partURL = destinationURL
                .deletingLastPathComponent()
                .appendingPathComponent(".\(destinationURL.lastPathComponent).part-\(UUID().uuidString)")

            progress(ImportProgress(
                phase: .copying,
                totalFiles: scan.files.count,
                completedFiles: importedFiles.count,
                totalBytes: scan.totalBytes,
                copiedBytes: completedBytes,
                currentFileName: file.relativePath,
                currentFileBytes: 0,
                currentFileTotalBytes: file.byteSize
            ))

            do {
                let baseBytes = completedBytes
                let completedCount = importedFiles.count
                let totalCount = scan.files.count
                let totalBytes = scan.totalBytes
                let relativePath = file.relativePath
                let fileSize = file.byteSize
                let copied = try copier.copy(
                    from: file.url,
                    to: partURL,
                    onChunk: { fileBytes in
                        progress(ImportProgress(
                            phase: .copying,
                            totalFiles: totalCount,
                            completedFiles: completedCount,
                            totalBytes: totalBytes,
                            copiedBytes: baseBytes + fileBytes,
                            currentFileName: relativePath,
                            currentFileBytes: fileBytes,
                            currentFileTotalBytes: fileSize
                        ))
                    }
                )

                try fileManager.moveItem(at: partURL, to: destinationURL)
                Self.applyFileProtection(to: destinationURL)

                completedBytes += copied
                importedFiles.append(ImportedFile(
                    sourceURL: file.url,
                    destinationURL: destinationURL,
                    sourceRelativePath: file.relativePath,
                    byteSize: copied,
                    kind: file.kind,
                    displayName: file.displayName
                ))
            } catch is CancellationError {
                try? fileManager.removeItem(at: partURL)
                cancelled = true
                break
            } catch {
                try? fileManager.removeItem(at: partURL)
                issues.append(ScanIssue(
                    relativePath: file.relativePath,
                    message: error.localizedDescription
                ))
            }

            progress(ImportProgress(
                phase: .copying,
                totalFiles: scan.files.count,
                completedFiles: importedFiles.count,
                totalBytes: scan.totalBytes,
                copiedBytes: completedBytes,
                currentFileName: nil,
                currentFileBytes: 0,
                currentFileTotalBytes: 0
            ))
        }

        let copyDuration = copyStart.duration(to: copyClock.now)
        let finishedAt = Date()
        progress(ImportProgress(
            phase: cancelled ? .cancelled : .finished,
            totalFiles: scan.files.count,
            completedFiles: importedFiles.count,
            totalBytes: scan.totalBytes,
            copiedBytes: completedBytes
        ))

        return ImportRunResult(
            importedFiles: importedFiles,
            issues: issues,
            skippedUnsupportedCount: scan.skippedUnsupportedCount,
            truncated: scan.truncated,
            totalBytes: scan.totalBytes,
            copiedBytes: completedBytes,
            scanDuration: scanDuration,
            copyDuration: copyDuration,
            cancelled: cancelled,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
    }

    private static func uniqueDestination(
        for relativePath: String,
        under root: URL,
        fileManager: FileManager
    ) throws -> URL {
        let sanitized = PathSanitizer.sanitizeRelativePath(relativePath)
        let base = root.appendingPathComponent(sanitized)
        let directory = base.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        guard fileManager.fileExists(atPath: base.path) else {
            return base
        }

        let ext = base.pathExtension
        let stem = base.deletingPathExtension().lastPathComponent
        var index = 2
        while true {
            let name = ext.isEmpty ? "\(stem)-\(index)" : "\(stem)-\(index).\(ext)"
            let candidate = directory.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private static func applyFileProtection(to url: URL) {
        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }
}
