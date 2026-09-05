import Foundation

actor OutputStore {
    static let shared = OutputStore()

    private var outputDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appending(path: "ShiroiVideoForge/Outputs", directoryHint: .isDirectory)
    }

    func persist(temporaryURL: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "forge-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(6)).mov"
        let destination = outputDirectory.appending(path: name)
        try fm.copyItem(at: temporaryURL, to: destination)
        try? fm.removeItem(at: temporaryURL)
        return destination
    }

    func listOutputs(limit: Int = 12) throws -> [URL] {
        let fm = FileManager.default
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        let urls = try fm.contentsOfDirectory(at: outputDirectory, includingPropertiesForKeys: Array(keys))
            .filter { $0.pathExtension.lowercased() == "mov" }

        return urls.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
            return l > r
        }
        .prefix(limit)
        .map { $0 }
    }

    func delete(_ url: URL) throws {
        let standardized = url.standardizedFileURL
        guard standardized.path.hasPrefix(outputDirectory.standardizedFileURL.path) else { return }
        try FileManager.default.removeItem(at: standardized)
    }
}
