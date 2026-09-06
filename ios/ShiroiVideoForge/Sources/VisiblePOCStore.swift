import Foundation

/// Only validated renders enter the visible library. Nothing successfully saved
/// is silently deleted; removal requires a specific user-selected result.
actor VisiblePOCStore {
    static let shared = VisiblePOCStore()
    private let root: URL
    init(root: URL? = nil) {
        let selected = root ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VisiblePOC", isDirectory: true)
        self.root = selected.resolvingSymlinksInPath().standardizedFileURL
    }
    /// A run must own a fresh directory. Reusing an old run ID is an error,
    /// never permission to overwrite or adopt its files.
    func stage(id: UUID) throws -> URL {
        let fm = FileManager.default
        let pending = root.appendingPathComponent(".pending", isDirectory: true)
        let path = pending.appendingPathComponent(id.uuidString, isDirectory: true)
        for url in [root, pending, path] { try requireUnaliased(url) }
        let saved = root.appendingPathComponent(id.uuidString, isDirectory: true)
        guard !itemExists(path), !itemExists(saved) else { throw StoreError.operationExists }
        try fm.createDirectory(at: pending, withIntermediateDirectories: true)
        for url in [root, pending] { try requireUnaliased(url) }
        try fm.createDirectory(at: path, withIntermediateDirectories: false)
        _ = try validatedID(path, parent: pending)
        return path
    }
    /// Includes dangling symbolic links, unlike fileExists(atPath:) alone.
    private func itemExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
            || (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }
    private func requireUnaliased(_ url: URL) throws {
        guard url.isFileURL,
              url.resolvingSymlinksInPath().path == url.standardizedFileURL.path,
              (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
        else { throw StoreError.outsideLibrary }
    }
    /// Atomically publish a verified result without replacing any prior video.
    func commit(_ result: VisiblePOCResult) throws -> VisiblePOCResult {
        let id = try validatedID(result.directory, parent: root.appendingPathComponent(".pending"))
        guard let stored = try load(result.directory), stored.report.status == "passed" else { throw StoreError.invalidResult }
        let destination = root.appendingPathComponent(id)
        try FileManager.default.moveItem(at: result.directory, to: destination)
        return VisiblePOCResult(directory: destination, report: stored.report)
    }
    /// Removes only the current operation's unpublished directory.
    func discard(_ directory: URL) throws {
        _ = try validatedID(directory, parent: root.appendingPathComponent(".pending"))
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    /// Includes existing version-1 results; no migration or destructive pruning.
    func list() throws -> [VisiblePOCResult] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }
        let directories = try fm.contentsOfDirectory(at: root,
            includingPropertiesForKeys: [.creationDateKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
        return try directories.compactMap { url -> (Date, VisiblePOCResult)? in
            guard UUID(uuidString: url.lastPathComponent) != nil,
                  let value = try load(url) else { return nil }
            let date = try url.resourceValues(forKeys: [.creationDateKey]).creationDate ?? .distantPast
            return (date, value)
        }.sorted { $0.0 > $1.0 }.map { $0.1 }
    }
    /// Rejects paths outside the library, symlink aliases and non-result folders.
    func delete(_ result: VisiblePOCResult) throws {
        _ = try validatedID(result.directory, parent: root)
        guard try load(result.directory) != nil else { throw StoreError.invalidResult }
        try FileManager.default.removeItem(at: result.directory)
    }
    private func validatedID(_ directory: URL, parent: URL) throws -> String {
        let path = directory.standardizedFileURL
        guard UUID(uuidString: path.lastPathComponent) != nil,
              path.deletingLastPathComponent().path == parent.standardizedFileURL.path,
              path.resolvingSymlinksInPath().path == path.path else { throw StoreError.outsideLibrary }
        return path.lastPathComponent
    }
    /// A JSON marker alone is not enough: require nonempty movie and poster too.
    private func load(_ directory: URL) throws -> VisiblePOCResult? {
        guard directory.resolvingSymlinksInPath().path == directory.standardizedFileURL.path,
              (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
        let json = directory.appendingPathComponent("poc-result.json")
        for name in ["poc-result.json", "poc-video.mov", "poc-poster.png"] {
            let url = directory.appendingPathComponent(name)
            guard let info = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  info.isRegularFile == true, info.isSymbolicLink != true, (info.fileSize ?? 0) > 0 else { return nil }
            if name == "poc-result.json", (info.fileSize ?? 0) > 65_536 { return nil }
        }
        guard let report = try? JSONDecoder().decode(VisiblePOCReport.self, from: Data(contentsOf: json)),
              report.status == "passed", report.frames > 0, report.frames == report.decodedFrames,
              report.width > 0, report.height > 0,
              report.width.isMultiple(of: 2), report.height.isMultiple(of: 2),
              !report.aiInference, report.fps > 0, report.durationSeconds.isFinite,
              report.durationSeconds > 0, report.renderAndEncodeSeconds.isFinite,
              report.renderAndEncodeSeconds >= 0,
              abs(report.durationSeconds - Double(report.frames) / Double(report.fps)) <= 0.001,
              report.gpuCommandSeconds.map({ $0.isFinite && $0 >= 0 }) ?? true,
              report.outputBytes == (try directory.appendingPathComponent("poc-video.mov")
                  .resourceValues(forKeys: [.fileSizeKey]).fileSize) else { return nil }
        return VisiblePOCResult(directory: directory, report: report)
    }
    enum StoreError: LocalizedError {
        case outsideLibrary, invalidResult, operationExists
        var errorDescription: String? {
            switch self {
            case .operationExists: return "同じ生成IDの保存データがあるため、上書きせず中止したよ。新しい生成を開始してね。"
            case .outsideLibrary, .invalidResult: return "この動画は保存ライブラリの有効な結果ではないよ。"
            }
        }
    }
}
