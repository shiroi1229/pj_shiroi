import Foundation

/// Pin the artifact revision, not the mutable model-card example (which contains a typo).
enum ModelManifest {
    static let revision = "04a6a0bdd66fb8da470c14e56d762343ef579d88"
    static let archiveName = "coreml-stable-diffusion-v1-5-palettized_split_einsum_v2_compiled.zip"
    static let downloadURL = URL(string:
        "https://huggingface.co/apple/coreml-stable-diffusion-v1-5-palettized/resolve/\(revision)/\(archiveName)"
    )!
    static let requiredDirectories = [
        "SafetyChecker.mlmodelc", "TextEncoder.mlmodelc", "Unet.mlmodelc",
        "VAEDecoder.mlmodelc", "VAEEncoder.mlmodelc"
    ]
    static let requiredFiles = ["vocab.json", "merges.txt"]

    /// Structural validation, not a cryptographic model-integrity guarantee.
    static func validateResources(at directory: URL) -> Bool {
        let fm = FileManager.default
        for name in requiredDirectories {
            let url = directory.appendingPathComponent(name, isDirectory: true)
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true,
                  let children = try? fm.contentsOfDirectory(atPath: url.path),
                  !children.isEmpty else { return false }
        }
        for name in requiredFiles {
            let url = directory.appendingPathComponent(name)
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  (values.fileSize ?? 0) > 0 else { return false }
        }
        return true
    }
}
