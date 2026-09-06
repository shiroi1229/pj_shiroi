import Foundation
import ZIPFoundation

actor ModelManager {
    static let shared = ModelManager()
    private let minimumFreeSpaceBytes: Int64 = 5_000_000_000
    private var isInstalling = false
    private var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "ShiroiVideoForge/Models/sd15", directoryHint: .isDirectory)
    }
    func installedModelDirectory() -> URL? {
        ModelManifest.validateResources(at: root) ? root : nil
    }

    func installBaseModel(progress: @escaping @Sendable (Double, String) -> Void = { _, _ in }) async throws -> URL {
        if let installed = installedModelDirectory() { return installed }
        guard !isInstalling else { throw ModelError.installAlreadyRunning }
        isInstalling = true
        defer { isInstalling = false }
        try Task.checkCancellation()
        let fm = FileManager.default
        let parent = root.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        var noBackup = parent
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try noBackup.setResourceValues(values)
        try ensureFreeSpace(at: parent)
        let downloads = parent.appendingPathComponent("download-\(ModelManifest.revision)", isDirectory: true)
        try fm.createDirectory(at: downloads, withIntermediateDirectories: true)
        let cachedArchive = downloads.appendingPathComponent("model.zip")
        let resume = downloads.appendingPathComponent("resume.data")
        let hadResume = fm.fileExists(atPath: resume.path)
        if !fm.fileExists(atPath: cachedArchive.path) {
            let downloadProgress: @Sendable (Double, String) -> Void = { value, message in progress(value * 0.85, message) }
            do {
                _ = try await ArchiveDownloader(destination: cachedArchive, resumeURL: resume, progress: downloadProgress)
                    .download(from: ModelManifest.downloadURL)
            } catch {
                if Task.isCancelled { throw CancellationError() }
                // Old resume data can contain expired temporary CDN URLs.
                guard hadResume else { throw error }
                try? fm.removeItem(at: resume)
                progress(0, "Resume unavailable; restarting from the pinned model source…")
                _ = try await ArchiveDownloader(destination: cachedArchive, resumeURL: resume, progress: downloadProgress)
                    .download(from: ModelManifest.downloadURL)
            }
        }
        try Task.checkCancellation()
        progress(0.86, "Checking model SHA-256 on this device…")
        do {
            try ArchiveIntegrity.verify(at: cachedArchive,
                expectedBytes: ModelManifest.archiveBytes, expectedSHA256: ModelManifest.archiveSHA256)
        } catch {
            if Task.isCancelled { throw CancellationError() }
            try? fm.removeItem(at: cachedArchive)
            throw error
        }
        progress(0.90, "Extracting verified model on this device…")
        let staging = parent.appendingPathComponent("install-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let unzipProgress = Progress()
        do {
            try await withTaskCancellationHandler {
                try fm.unzipItem(at: cachedArchive, to: staging, progress: unzipProgress)
            } onCancel: { unzipProgress.cancel() }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            try? fm.removeItem(at: cachedArchive)
            throw error
        }
        try Task.checkCancellation()
        guard let resources = findResourcesDirectory(inside: staging),
              ModelManifest.validateResources(at: resources) else {
            try? fm.removeItem(at: cachedArchive)
            throw ModelError.invalidArchive
        }
        progress(0.96, "Installing validated model resources…")
        let backup = parent.appendingPathComponent("previous-\(UUID().uuidString)", isDirectory: true)
        let hadPrevious = fm.fileExists(atPath: root.path)
        if hadPrevious { try fm.moveItem(at: root, to: backup) }
        do {
            try fm.moveItem(at: resources, to: root)
            guard ModelManifest.validateResources(at: root) else { throw ModelError.invalidArchive }
        } catch {
            try? fm.removeItem(at: root)
            if hadPrevious { try? fm.moveItem(at: backup, to: root) }
            throw error
        }
        if hadPrevious { try? fm.removeItem(at: backup) }
        try? fm.removeItem(at: downloads)
        progress(1, "Model installed on this device")
        return root
    }

    private func ensureFreeSpace(at directory: URL) throws {
        let values = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let bytes = values.volumeAvailableCapacityForImportantUsage, bytes < minimumFreeSpaceBytes {
            throw ModelError.insufficientSpace
        }
    }
    private func findResourcesDirectory(inside directory: URL) -> URL? {
        if ModelManifest.validateResources(at: directory) { return directory }
        guard let items = FileManager.default.enumerator(at: directory,
            includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in items where url.lastPathComponent == "TextEncoder.mlmodelc" {
            let parent = url.deletingLastPathComponent()
            if ModelManifest.validateResources(at: parent) { return parent }
            items.skipDescendants()
        }
        return nil
    }
    enum ModelError: LocalizedError {
        case installAlreadyRunning, invalidArchive, insufficientSpace
        var errorDescription: String? {
            switch self {
            case .installAlreadyRunning: return "Model installation is already running."
            case .invalidArchive: return "The model archive is incomplete or its compiled resources are invalid."
            case .insufficientSpace: return "At least 5 GB of free storage is required to install the model."
            }
        }
    }
}
