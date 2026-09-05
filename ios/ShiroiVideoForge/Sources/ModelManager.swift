import Foundation
import ZIPFoundation

actor ModelManager {
    static let shared = ModelManager()
    private let minimumFreeSpaceBytes: Int64 = 5_000_000_000
    private var isInstalling = false

    private var root: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "ShiroiVideoForge/Models/sd15", directoryHint: .isDirectory)
    }

    func installedModelDirectory() -> URL? {
        ModelManifest.validateResources(at: root) ? root : nil
    }

    func installBaseModel() async throws -> URL {
        if let existing = installedModelDirectory() { return existing }
        guard !isInstalling else { throw ModelError.installAlreadyRunning }
        isInstalling = true
        defer { isInstalling = false }
        try Task.checkCancellation()

        let fm = FileManager.default
        let parent = root.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        try ensureFreeSpace(at: parent)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (archiveURL, response) = try await session.download(from: ModelManifest.downloadURL)
        defer { try? fm.removeItem(at: archiveURL) }
        guard let http = response as? HTTPURLResponse else { throw ModelError.invalidArchive }
        guard (200...299).contains(http.statusCode) else { throw ModelError.httpStatus(http.statusCode) }
        try Task.checkCancellation()

        // Staging beside the destination permits a rename instead of a second 1.57 GB copy.
        let staging = parent.appending(path: "install-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        // ZIPFoundation checks CRC32 by default. Do not disable it.
        try fm.unzipItem(at: archiveURL, to: staging)
        try Task.checkCancellation()
        guard let resources = findResourcesDirectory(inside: staging),
              ModelManifest.validateResources(at: resources) else { throw ModelError.invalidArchive }

        let backup = parent.appending(path: "previous-\(UUID().uuidString)", directoryHint: .isDirectory)
        let hadPrevious = fm.fileExists(atPath: root.path)
        if hadPrevious { try fm.moveItem(at: root, to: backup) }
        do {
            try fm.moveItem(at: resources, to: root)
            guard ModelManifest.validateResources(at: root) else { throw ModelError.installationValidationFailed }
        } catch {
            try? fm.removeItem(at: root)
            if hadPrevious { try? fm.moveItem(at: backup, to: root) }
            throw error
        }
        if hadPrevious { try? fm.removeItem(at: backup) }
        var installed = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? installed.setResourceValues(values)
        return root
    }

    private func ensureFreeSpace(at directory: URL) throws {
        let values = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values.volumeAvailableCapacityForImportantUsage, available < minimumFreeSpaceBytes {
            throw ModelError.insufficientDiskSpace(required: minimumFreeSpaceBytes, available: available)
        }
    }

    private func findResourcesDirectory(inside directory: URL) -> URL? {
        if ModelManifest.validateResources(at: directory) { return directory }
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let url as URL in enumerator {
            if url.lastPathComponent == "TextEncoder.mlmodelc" {
                let candidate = url.deletingLastPathComponent()
                if ModelManifest.validateResources(at: candidate) { return candidate }
                enumerator.skipDescendants()
            }
        }
        return nil
    }

    enum ModelError: LocalizedError {
        case httpStatus(Int), insufficientDiskSpace(required: Int64, available: Int64)
        case invalidArchive, installationValidationFailed, installAlreadyRunning
        var errorDescription: String? {
            switch self {
            case .httpStatus(let status): return "Core ML model download failed with HTTP status \(status)."
            case .insufficientDiskSpace(let required, let available):
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                return "Not enough free storage. Need \(formatter.string(fromByteCount: required)); available \(formatter.string(fromByteCount: available))."
            case .invalidArchive: return "The model archive is incomplete or does not contain valid Core ML resources."
            case .installationValidationFailed: return "Core ML model installation failed validation."
            case .installAlreadyRunning: return "A model installation is already running."
            }
        }
    }
}
