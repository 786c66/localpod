import Foundation

public struct ImportEngine: Sendable {
    public struct Options: Sendable {
        public var limits: FolderScanner.Limits
        public var chunkSize: Int
        public var chunkDelay: Duration?
        public var cloudRetryCount: Int
        public var generateArtwork: Bool
        /// Locale used for user-facing issue messages. `nil` follows the
        /// process language, which is what the app should use. Tests pass an
        /// explicit locale so assertions do not depend on the host Mac.
        public var locale: Locale?

        public init(
            limits: FolderScanner.Limits = FolderScanner.Limits(),
            chunkSize: Int = 1 << 20,
            chunkDelay: Duration? = nil,
            cloudRetryCount: Int = 1,
            generateArtwork: Bool = true,
            locale: Locale? = nil
        ) {
            self.limits = limits
            self.chunkSize = chunkSize
            self.chunkDelay = chunkDelay
            self.cloudRetryCount = max(0, cloudRetryCount)
            self.generateArtwork = generateArtwork
            self.locale = locale
        }
    }

    private let scanner: any FolderScanning

    public init(scanner: any FolderScanning = FolderScanner()) {
        self.scanner = scanner
    }

    /// Scans a folder (or a single file), copies supported media into staging,
    /// hashes and probes each file, rejects duplicates, then atomically moves
    /// the final files into `mediaRootURL`. The caller owns security-scoped
    /// access and DB writes.
    public func importFolder(
        rootURL: URL,
        source: MediaSource,
        rootName: String,
        sessionID: UUID = UUID(),
        stagingRootURL: URL,
        mediaRootURL: URL,
        artworkRootURL: URL?,
        existingFingerprints: Set<String> = [],
        relinkFingerprints: Set<String> = [],
        options: Options = Options(),
        probe: any MediaProbing = AVMediaProbe(),
        cloudDownloader: any CloudDownloading = ICloudDownloader(),
        progress: @escaping @Sendable (ImportProgress) -> Void = { _ in }
    ) async throws -> ImportRunResult {
        let startedAt = Date()
        progress(ImportProgress(phase: .scanning))

        let scanClock = ContinuousClock()
        let scanStart = scanClock.now
        let scan = try scanner.scan(rootURL: rootURL, limits: options.limits)
        let scanDuration = scanStart.duration(to: scanClock.now)

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: stagingRootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: mediaRootURL, withIntermediateDirectories: true)
        if let artworkRootURL {
            try fileManager.createDirectory(at: artworkRootURL, withIntermediateDirectories: true)
        }

        let sessionStagingURL = stagingRootURL
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: sessionStagingURL, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: sessionStagingURL)
        }

        let copier = ChunkedFileCopier(
            chunkSize: options.chunkSize,
            chunkDelay: options.chunkDelay
        )

        var importedFiles: [ImportedFile] = []
        var duplicateIssues: [ImportIssue] = []
        var failureIssues: [ImportIssue] = scan.issues.map {
            ImportIssue(
                relativePath: $0.relativePath,
                kind: .scanError,
                message: $0.message
            )
        }
        let unsupportedIssues = scan.unsupportedFiles.map {
            ImportIssue(
                relativePath: $0.relativePath,
                kind: .unsupported,
                message: $0.message(locale: options.locale)
            )
        }
        if scan.truncated {
            failureIssues.append(ImportIssue(
                relativePath: "",
                kind: .other,
                message: LocalPodLocalization.string(
                    "error.import.truncated",
                    locale: options.locale
                )
            ))
        }

        let totalCandidates = max(scan.totalCandidates, scan.files.count + scan.unsupportedFiles.count)
        var completedFiles = scan.unsupportedFiles.count
        var copiedBytes: Int64 = 0
        var cancelled = false
        var seenFingerprints = existingFingerprints
        let copyClock = ContinuousClock()
        let copyStart = copyClock.now

        progress(ImportProgress(
            phase: .copying,
            totalFiles: totalCandidates,
            completedFiles: completedFiles,
            totalBytes: scan.totalBytes,
            copiedBytes: 0
        ))

        fileLoop: for file in scan.files {
            if Task.isCancelled {
                cancelled = true
                break
            }

            let currentFileName = file.relativePath
            let currentFileSize = file.byteSize
            let completedSnapshot = completedFiles
            let copiedSnapshot = copiedBytes
            let totalFilesSnapshot = totalCandidates
            let totalBytesSnapshot = scan.totalBytes

            if file.cloudState.needsDownload {
                var attempt = 0
                while true {
                    do {
                        try await cloudDownloader.ensureDownloaded(
                            at: file.url,
                            progress: { fraction in
                                progress(Self.makeProgress(
                                    phase: .downloading,
                                    totalFiles: totalFilesSnapshot,
                                    completedFiles: completedSnapshot,
                                    totalBytes: totalBytesSnapshot,
                                    copiedBytes: copiedSnapshot,
                                    currentFileName: currentFileName,
                                    currentFileBytes: 0,
                                    currentFileTotalBytes: currentFileSize,
                                    downloadFraction: fraction
                                ))
                            }
                        )
                        break
                    } catch is CancellationError {
                        cancelled = true
                        break fileLoop
                    } catch {
                        if attempt < options.cloudRetryCount {
                            attempt += 1
                            continue
                        }
                        failureIssues.append(ImportIssue(
                            relativePath: file.relativePath,
                            kind: .cloudDownloadFailed,
                            message: error.localizedDescription
                        ))
                        completedFiles += 1
                        progress(Self.makeProgress(
                            phase: .copying,
                            totalFiles: totalCandidates,
                            completedFiles: completedFiles,
                            totalBytes: scan.totalBytes,
                            copiedBytes: copiedBytes
                        ))
                        continue fileLoop
                    }
                }
            }

            progress(Self.makeProgress(
                phase: .copying,
                totalFiles: totalCandidates,
                completedFiles: completedFiles,
                totalBytes: scan.totalBytes,
                copiedBytes: copiedBytes,
                currentFileName: currentFileName,
                currentFileTotalBytes: currentFileSize
            ))

            // Keep the source extension on the staged file: AVFoundation infers
            // the container format from the path extension, so a generic ".part"
            // name makes every probe fail. Crash leftovers are still contained by
            // the per-session staging directory and removed by reconciliation.
            let stagedExtension = MediaStorage.safeExtension(file.url.pathExtension)
            let stagedName = stagedExtension.isEmpty
                ? UUID().uuidString
                : "\(UUID().uuidString).\(stagedExtension)"
            let partURL = sessionStagingURL.appendingPathComponent(stagedName)
            let copyResult: CopyResult
            do {
                let baseBytes = copiedBytes
                let completed = completedFiles
                let total = totalCandidates
                let totalBytes = scan.totalBytes
                let relativePath = file.relativePath
                let fileSize = file.byteSize
                copyResult = try await copier.copyHashing(
                    from: file.url,
                    to: partURL,
                    onChunk: { fileBytes in
                        progress(ImportProgress(
                            phase: .copying,
                            totalFiles: total,
                            completedFiles: completed,
                            totalBytes: totalBytes,
                            copiedBytes: baseBytes + fileBytes,
                            currentFileName: relativePath,
                            currentFileBytes: fileBytes,
                            currentFileTotalBytes: fileSize
                        ))
                    }
                )
            } catch is CancellationError {
                try? fileManager.removeItem(at: partURL)
                cancelled = true
                break
            } catch {
                try? fileManager.removeItem(at: partURL)
                failureIssues.append(ImportIssue(
                    relativePath: file.relativePath,
                    kind: .copyFailed,
                    message: error.localizedDescription
                ))
                completedFiles += 1
                progress(Self.makeProgress(phase: .copying, totalFiles: totalCandidates, completedFiles: completedFiles, totalBytes: scan.totalBytes, copiedBytes: copiedBytes))
                continue
            }

            // The scan size is a snapshot, not a guarantee: a file can grow or
            // shrink while it is being copied (Finder/iCloud). Cheap defense:
            // compare the bytes we actually hashed with the scanned size. A
            // mismatch means the staged bytes are not the scanned file.
            if copyResult.byteCount != file.byteSize {
                try? fileManager.removeItem(at: partURL)
                failureIssues.append(ImportIssue(
                    relativePath: file.relativePath,
                    kind: .copyFailed,
                    message: LocalPodLocalization.format(
                        "error.import.sizeChanged",
                        locale: options.locale,
                        file.byteSize,
                        copyResult.byteCount
                    )
                ))
                completedFiles += 1
                progress(Self.makeProgress(phase: .copying, totalFiles: totalCandidates, completedFiles: completedFiles, totalBytes: scan.totalBytes, copiedBytes: copiedBytes))
                continue
            }

            progress(Self.makeProgress(phase: .probing, totalFiles: totalCandidates, completedFiles: completedFiles, totalBytes: scan.totalBytes, copiedBytes: copiedBytes, currentFileName: currentFileName, currentFileTotalBytes: currentFileSize))

            let probed: ProbedMedia
            do {
                probed = try await probe.probe(url: partURL, kindHint: file.kind)
            } catch is CancellationError {
                try? fileManager.removeItem(at: partURL)
                cancelled = true
                break
            } catch {
                try? fileManager.removeItem(at: partURL)
                failureIssues.append(ImportIssue(
                    relativePath: file.relativePath,
                    kind: .probeFailed,
                    message: error.localizedDescription
                ))
                completedFiles += 1
                progress(Self.makeProgress(phase: .copying, totalFiles: totalCandidates, completedFiles: completedFiles, totalBytes: scan.totalBytes, copiedBytes: copiedBytes))
                continue
            }

            let fingerprint = copyResult.sha256
            let isRelink = relinkFingerprints.contains(fingerprint)
            if seenFingerprints.contains(fingerprint), !isRelink {
                try? fileManager.removeItem(at: partURL)
                duplicateIssues.append(ImportIssue(
                    relativePath: file.relativePath,
                    kind: .duplicate,
                    message: LocalPodLocalization.format(
                        "error.import.duplicate",
                        locale: options.locale,
                        String(fingerprint.prefix(12))
                    )
                ))
                completedFiles += 1
                progress(Self.makeProgress(phase: .copying, totalFiles: totalCandidates, completedFiles: completedFiles, totalBytes: scan.totalBytes, copiedBytes: copiedBytes))
                continue
            }
            seenFingerprints.insert(fingerprint)

            let itemID = UUID()
            let ext = stagedExtension
            let destinationURL = mediaRootURL.appendingPathComponent(
                ext.isEmpty ? itemID.uuidString : "\(itemID.uuidString).\(ext)",
                isDirectory: false
            )
            do {
                try fileManager.moveItem(at: partURL, to: destinationURL)
            } catch {
                try? fileManager.removeItem(at: partURL)
                failureIssues.append(ImportIssue(
                    relativePath: file.relativePath,
                    kind: .moveFailed,
                    message: error.localizedDescription
                ))
                completedFiles += 1
                progress(Self.makeProgress(phase: .copying, totalFiles: totalCandidates, completedFiles: completedFiles, totalBytes: scan.totalBytes, copiedBytes: copiedBytes))
                continue
            }
            Self.applyFileProtection(to: destinationURL)

            var artworkKey: String?
            if options.generateArtwork,
               let artworkData = probed.artworkJPEGData,
               let artworkRootURL {
                let key = "\(itemID.uuidString).jpg"
                let artworkURL = artworkRootURL.appendingPathComponent(key)
                if (try? artworkData.write(to: artworkURL, options: .atomic)) != nil {
                    artworkKey = key
                }
            }

            let title = probed.title?.isEmpty == false ? probed.title! : file.displayName
            copiedBytes += copyResult.byteCount
            importedFiles.append(ImportedFile(
                id: itemID,
                sourceURL: file.url,
                destinationURL: destinationURL,
                sourceRelativePath: file.relativePath,
                relativeFolderPath: file.relativeFolderPath,
                title: title,
                originalFileName: file.originalFileName,
                fileExtension: ext.lowercased(),
                byteSize: copyResult.byteCount,
                kind: probed.hasVideoTrack ? .video : .audio,
                durationSeconds: probed.durationSeconds,
                fingerprint: fingerprint,
                artworkKey: artworkKey,
                isRelink: isRelink
            ))
            completedFiles += 1
            progress(Self.makeProgress(phase: .copying, totalFiles: totalCandidates, completedFiles: completedFiles, totalBytes: scan.totalBytes, copiedBytes: copiedBytes))
        }

        let copyDuration = copyStart.duration(to: copyClock.now)
        let finishedAt = Date()
        progress(ImportProgress(
            phase: cancelled ? .cancelled : .finished,
            totalFiles: totalCandidates,
            completedFiles: completedFiles,
            totalBytes: scan.totalBytes,
            copiedBytes: copiedBytes
        ))

        return ImportRunResult(
            sessionID: sessionID,
            source: source,
            rootName: rootName,
            importedFiles: importedFiles,
            duplicateIssues: duplicateIssues,
            unsupportedIssues: unsupportedIssues,
            failureIssues: failureIssues,
            scanIssues: scan.issues,
            truncated: scan.truncated,
            totalCandidates: totalCandidates,
            supportedFiles: scan.files.count,
            totalBytes: scan.totalBytes,
            copiedBytes: copiedBytes,
            scanDuration: scanDuration,
            copyDuration: copyDuration,
            cancelled: cancelled,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
    }

    /// In-place (linked) folder import. Scans the user's folder, downloads
    /// iCloud placeholders when needed, fingerprints and probes each file in
    /// place, and returns `ImportedFile`s that point at the source URL. No
    /// bytes are written into the container; the caller persists the folder
    /// bookmark separately.
    public func importLinkedFolder(
        rootURL: URL,
        source: MediaSource,
        rootName: String,
        sessionID: UUID = UUID(),
        linkedFolderID: UUID,
        artworkRootURL: URL?,
        existingFingerprints: Set<String> = [],
        relinkFingerprints: Set<String> = [],
        options: Options = Options(),
        probe: any MediaProbing = AVMediaProbe(),
        cloudDownloader: any CloudDownloading = ICloudDownloader(),
        progress: @escaping @Sendable (ImportProgress) -> Void = { _ in }
    ) async throws -> ImportRunResult {
        let startedAt = Date()
        progress(ImportProgress(phase: .scanning))

        let scanClock = ContinuousClock()
        let scanStart = scanClock.now
        let scan = try scanner.scan(rootURL: rootURL, limits: options.limits)
        let scanDuration = scanStart.duration(to: scanClock.now)

        let fileManager = FileManager.default
        if let artworkRootURL {
            try fileManager.createDirectory(at: artworkRootURL, withIntermediateDirectories: true)
        }

        var importedFiles: [ImportedFile] = []
        var duplicateIssues: [ImportIssue] = []
        var failureIssues: [ImportIssue] = scan.issues.map {
            ImportIssue(relativePath: $0.relativePath, kind: .scanError, message: $0.message)
        }
        let unsupportedIssues = scan.unsupportedFiles.map {
            ImportIssue(
                relativePath: $0.relativePath,
                kind: .unsupported,
                message: $0.message(locale: options.locale)
            )
        }
        if scan.truncated {
            failureIssues.append(ImportIssue(
                relativePath: "",
                kind: .other,
                message: LocalPodLocalization.string("error.import.truncated", locale: options.locale)
            ))
        }

        let totalCandidates = max(scan.totalCandidates, scan.files.count + scan.unsupportedFiles.count)
        var completedFiles = scan.unsupportedFiles.count
        var cancelled = false
        var seenFingerprints = existingFingerprints
        let linkClock = ContinuousClock()
        let linkStart = linkClock.now

        progress(ImportProgress(
            phase: .linking,
            totalFiles: totalCandidates,
            completedFiles: completedFiles,
            totalBytes: scan.totalBytes,
            copiedBytes: 0
        ))

        fileLoop: for file in scan.files {
            if Task.isCancelled {
                cancelled = true
                break
            }

            if file.cloudState.needsDownload {
                var attempt = 0
                let completedSnapshot = completedFiles
                while true {
                    do {
                        try await cloudDownloader.ensureDownloaded(
                            at: file.url,
                            progress: { fraction in
                                progress(Self.makeProgress(
                                    phase: .downloading,
                                    totalFiles: totalCandidates,
                                    completedFiles: completedSnapshot,
                                    totalBytes: scan.totalBytes,
                                    copiedBytes: 0,
                                    currentFileName: file.relativePath,
                                    currentFileTotalBytes: file.byteSize,
                                    downloadFraction: fraction
                                ))
                            }
                        )
                        break
                    } catch is CancellationError {
                        cancelled = true
                        break fileLoop
                    } catch {
                        if attempt < options.cloudRetryCount {
                            attempt += 1
                            continue
                        }
                        failureIssues.append(ImportIssue(
                            relativePath: file.relativePath,
                            kind: .cloudDownloadFailed,
                            message: error.localizedDescription
                        ))
                        completedFiles += 1
                        progress(Self.makeProgress(
                            phase: .linking,
                            totalFiles: totalCandidates,
                            completedFiles: completedFiles,
                            totalBytes: scan.totalBytes,
                            copiedBytes: 0
                        ))
                        continue fileLoop
                    }
                }
            }

            progress(Self.makeProgress(
                phase: .linking,
                totalFiles: totalCandidates,
                completedFiles: completedFiles,
                totalBytes: scan.totalBytes,
                copiedBytes: 0,
                currentFileName: file.relativePath,
                currentFileTotalBytes: file.byteSize
            ))

            let fingerprint: String
            do {
                fingerprint = try FileFingerprint.sha256(of: file.url)
            } catch is CancellationError {
                cancelled = true
                break
            } catch {
                failureIssues.append(ImportIssue(
                    relativePath: file.relativePath,
                    kind: .copyFailed,
                    message: error.localizedDescription
                ))
                completedFiles += 1
                progress(Self.makeProgress(
                    phase: .linking,
                    totalFiles: totalCandidates,
                    completedFiles: completedFiles,
                    totalBytes: scan.totalBytes,
                    copiedBytes: 0
                ))
                continue
            }

            let isRelink = relinkFingerprints.contains(fingerprint)
            if seenFingerprints.contains(fingerprint), !isRelink {
                duplicateIssues.append(ImportIssue(
                    relativePath: file.relativePath,
                    kind: .duplicate,
                    message: LocalPodLocalization.format(
                        "error.import.duplicate",
                        locale: options.locale,
                        String(fingerprint.prefix(12))
                    )
                ))
                completedFiles += 1
                progress(Self.makeProgress(
                    phase: .linking,
                    totalFiles: totalCandidates,
                    completedFiles: completedFiles,
                    totalBytes: scan.totalBytes,
                    copiedBytes: 0
                ))
                continue
            }
            seenFingerprints.insert(fingerprint)

            let probed: ProbedMedia
            do {
                probed = try await probe.probe(url: file.url, kindHint: file.kind)
            } catch is CancellationError {
                cancelled = true
                break
            } catch {
                failureIssues.append(ImportIssue(
                    relativePath: file.relativePath,
                    kind: .probeFailed,
                    message: error.localizedDescription
                ))
                completedFiles += 1
                progress(Self.makeProgress(
                    phase: .linking,
                    totalFiles: totalCandidates,
                    completedFiles: completedFiles,
                    totalBytes: scan.totalBytes,
                    copiedBytes: 0
                ))
                continue
            }

            let itemID = UUID()
            var artworkKey: String?
            if options.generateArtwork,
               let artworkData = probed.artworkJPEGData,
               let artworkRootURL {
                let key = "\(itemID.uuidString).jpg"
                let artworkURL = artworkRootURL.appendingPathComponent(key)
                if (try? artworkData.write(to: artworkURL, options: .atomic)) != nil {
                    artworkKey = key
                }
            }

            let title = probed.title?.isEmpty == false ? probed.title! : file.displayName
            let ext = MediaStorage.safeExtension(file.url.pathExtension)
            importedFiles.append(ImportedFile(
                id: itemID,
                sourceURL: file.url,
                destinationURL: file.url,
                sourceRelativePath: file.relativePath,
                relativeFolderPath: file.relativeFolderPath,
                title: title,
                originalFileName: file.originalFileName,
                fileExtension: ext,
                byteSize: file.byteSize,
                kind: probed.hasVideoTrack ? .video : .audio,
                durationSeconds: probed.durationSeconds,
                fingerprint: fingerprint,
                artworkKey: artworkKey,
                isRelink: isRelink,
                isLinked: true,
                linkedFolderID: linkedFolderID
            ))
            completedFiles += 1
            progress(Self.makeProgress(
                phase: .linking,
                totalFiles: totalCandidates,
                completedFiles: completedFiles,
                totalBytes: scan.totalBytes,
                copiedBytes: 0
            ))
        }

        let linkDuration = linkStart.duration(to: linkClock.now)
        let finishedAt = Date()
        progress(ImportProgress(
            phase: cancelled ? .cancelled : .finished,
            totalFiles: totalCandidates,
            completedFiles: completedFiles,
            totalBytes: scan.totalBytes,
            copiedBytes: 0
        ))

        return ImportRunResult(
            sessionID: sessionID,
            source: source,
            rootName: rootName,
            importedFiles: importedFiles,
            duplicateIssues: duplicateIssues,
            unsupportedIssues: unsupportedIssues,
            failureIssues: failureIssues,
            scanIssues: scan.issues,
            truncated: scan.truncated,
            totalCandidates: totalCandidates,
            supportedFiles: scan.files.count,
            totalBytes: scan.totalBytes,
            copiedBytes: 0,
            scanDuration: scanDuration,
            copyDuration: linkDuration,
            cancelled: cancelled,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
    }

    private static func makeProgress(
        phase: ImportPhase,
        totalFiles: Int,
        completedFiles: Int,
        totalBytes: Int64,
        copiedBytes: Int64,
        currentFileName: String? = nil,
        currentFileBytes: Int64 = 0,
        currentFileTotalBytes: Int64 = 0,
        downloadFraction: Double? = nil
    ) -> ImportProgress {
        ImportProgress(
            phase: phase,
            totalFiles: totalFiles,
            completedFiles: completedFiles,
            totalBytes: totalBytes,
            copiedBytes: copiedBytes,
            currentFileName: currentFileName,
            currentFileBytes: currentFileBytes,
            currentFileTotalBytes: currentFileTotalBytes,
            currentFileDownloadFraction: downloadFraction
        )
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
