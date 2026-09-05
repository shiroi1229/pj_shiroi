import Foundation
import ZIPFoundation

actor ModelManager {
    static let shared = ModelManager()

    private let modelURL = URL(string: "https://huggingface.co/apple/coreml-stable-diffusion-v1-5-palettized/resolve/main/coreml-stable-diffusion-v1-5-palettized_split_einsum_v2_compiled.zip")!

    private var root: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "ShiroiVideoForge/Models/sd15", directoryHint: .isDirectory)
    }

    func installedModelDirectory() -> URL? {
        let required = ["TextEncoder.mlmodelc", "Unet.mlmodelc", "VAEDecoder.mlmodelc", "vocab.json", "merges.txt"]
        guard required.allSatisfy({ FileManager.default.fileExists(atPath: root.appending(path: $0).path) }) else {
            return nil
        }
        return root
    }

    func installBaseModel() async throws -> URL {
        if let existing = installedModelDirectory() { return existing }

        let fm = FileManager.default
        try fm.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        let (archiveURL, _) = try await URLSession.shared.download(from: modelURL)

        let staging = fm.temporaryDirectory.appending(path: "ShiroiVideoForgeModel-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        try fm.unzipItem(at: archiveURL, to: staging)
        guard let resources = findResourcesDirectory(inside: staging) else {
            throw ModelError.invalidArchive
        }

        if fm.fileExists(atPath: root.path) { try fm.removeItem(at: root) }
        try fm.copyItem(at: resources, to: root)
        return root
    }

    private func findResourcesDirectory(inside directory: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        for case let url as URL in enumerator {
            if url.lastPathComponent == "TextEncoder.mlmodelc" {
                return url.deletingLastPathComponent()
            }
        }
        return nil
    }

    enum ModelError: LocalizedError {
        case invalidArchive
        var errorDescription: String? { "Downloaded Core ML model archive did not contain the expected resources." }
    }
}
