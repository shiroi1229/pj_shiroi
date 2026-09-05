import Foundation
import ZIPFoundation

actor ModelManager {
    static let shared = ModelManager()

    // Apple/Hugging Face 6-bit split_einsum_v2 compiled Core ML archive.
    private let modelURL = URL(string: "https://huggingface.co/apple/coreml-stable-diffusion-v1-5-palettized/resolve/main/coreml-stable-diffusion-v1-5-base-palettized_split_einsum_v2_compiled.zip")!
    private let minimumFreeSpaceBytes: Int64 = 4_000_000_000

    private let requiredResources = [
        "SafetyChecker.mlmodelc",
        "TextEncoder.mlmodelc",
        "Unet.mlmodelc",
        "VAEDecoder.mlmodelc",
        "VAEEncoder.mlmodelc",
        "vocab.json",
        "merges.txt"
    ]

    private var root: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "ShiroiVideoForge/Models/sd15", directoryHint: .isDirectory)
    }

    func installedModelDirectory() -> URL? {
        guard validateResources(at: root) else { return nil }
        return root
    }

    func installBaseModel() async throws -> URL {
        if let existing = installedModelDirectory() { return existing }

        let fm = FileManager.default
        let parent = root.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        try ensureFreeSpace(at: parent)

        let (archiveURL, response) = try await URLSession.shared.download(from: modelURL)
        defer { try? fm.removeItem(at: archiveURL) }

        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            throw ModelError.httpStatus(http.statusCode)
        }

        let staging = fm.temporaryDirectory.appending(
            path: "ShiroiVideoForgeModel-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        try fm.unzipItem(at: archiveURL, to: staging)
        guard let resources = findResourcesDirectory(inside: staging) else {
            throw ModelError.invalidArchive
        }
        guard validateResources(at: resources) else {
            throw ModelError.installationValidationFailed
        }

        let candidate = parent.appending(
            path: "sd15-installing-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fm.removeItem(at: candidate) }
        try fm.copyItem(at: resources, to: candidate)
        guard validateResources(at: candidate) else {
            throw ModelError.installationValidationFailed
        }

        if fm.fileExists(atPath: root.path) {
            try fm.removeItem(at: root)
        }
        try fm.moveItem(at: candidate, to: root)

        var installed = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? installed.setResourceValues(values)

        guard validateResources(at: root) else {
            throw ModelError.installationValidationFailed
        }
        return root
    }

    private func validateResources(at directory: URL) -> Bool {
        requiredResources.allSatisfy {
            FileManager.default.fileExists(atPath: directory.appending(path: $0).path)
        }
    }

    private func ensureFreeSpace(at directory: URL) throws {
        let values = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values.volumeAvailableCapacityForImportantUsage,
           available < minimumFreeSpaceBytes {
            throw ModelError.insufficientDiskSpace(required: minimumFreeSpaceBytes, available: available)
        }
    }

    private func findResourcesDirectory(inside directory: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let url as URL in enumerator {
            if url.lastPathComponent == "TextEncoder.mlmodelc" {
                return url.deletingLastPathComponent()
            }
        }
        return nil
    }

    enum ModelError: LocalizedError {
        case httpStatus(Int)
        case insufficientDiskSpace(required: Int64, available: Int64)
        case invalidArchive
        case installationValidationFailed

        var errorDescription: String? {
            switch self {
            case .httpStatus(let status):
                return "Core ML model download failed with HTTP status \(status)."
            case .insufficientDiskSpace(let required, let available):
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                return "Not enough free storage. Need about \(formatter.string(fromByteCount: required)); available \(formatter.string(fromByteCount: available))."
            case .invalidArchive:
                return "Downloaded Core ML model archive did not contain the expected resources."
            case .installationValidationFailed:
                return "Core ML model installation was incomplete or corrupted."
            }
        }
    }
}
