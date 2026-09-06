import Foundation

@main
enum POCStoreTests {
    static func main() async throws {
        setbuf(stdout, nil)
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        defer { try? fm.removeItem(at: root) }
        let store = VisiblePOCStore(root: root)
        var count = 0
        func check(_ condition: Bool, _ label: String) throws {
            guard condition else { throw Failure.failed(label) }
            count += 1; print("PASS \(label)")
        }
        func fixture(at path: URL) throws -> VisiblePOCResult {
            try fm.createDirectory(at: path, withIntermediateDirectories: true)
            let report = VisiblePOCReport(status: "passed", host: "STRUCTURAL TEST ONLY", gpu: "none",
                width: 960, height: 540, fps: 24, frames: 144, decodedFrames: 144,
                durationSeconds: 6, renderAndEncodeSeconds: 1, gpuCommandSeconds: nil,
                outputBytes: 32, aiInference: false, source: "not a real movie; storage test")
            try JSONEncoder().encode(report).write(to: path.appendingPathComponent("poc-result.json"))
            try Data(repeating: 1, count: 32).write(to: path.appendingPathComponent("poc-video.mov"))
            try Data([1]).write(to: path.appendingPathComponent("poc-poster.png"))
            return VisiblePOCResult(directory: path, report: report)
        }
        try check(try await store.list().isEmpty, "empty library")
        let p1 = try await store.stage(id: UUID())
        let f1 = try fixture(at: p1)
        try check(try await store.list().isEmpty, "staged success hidden until commit")
        let saved = try await store.commit(f1)
        try check(!fm.fileExists(atPath: p1.path), "commit removes staging by rename")
        try check(try await store.list().count == 1, "successful result visible")
        let restored = try await VisiblePOCStore(root: root).list()
        try check(restored.first?.id == saved.id, "reopening restores result identity")
        let legacy = root.appendingPathComponent(UUID().uuidString)
        _ = try fixture(at: legacy)
        try check(try await store.list().count == 2, "version-1 result remains accessible")
        let p2 = try await store.stage(id: UUID())
        try Data([1]).write(to: p2.appendingPathComponent("poc-video.mov"))
        try await store.discard(p2)
        try check(!fm.fileExists(atPath: p2.path), "cancelled output removed")
        try check(try await store.list().count == 2, "cancellation preserves earlier successes")
        let broken = root.appendingPathComponent(UUID().uuidString)
        _ = try fixture(at: broken)
        try fm.removeItem(at: broken.appendingPathComponent("poc-video.mov"))
        try check(try await store.list().count == 2, "missing movie is not listed")
        try Data([1]).write(to: broken.appendingPathComponent("poc-video.mov"))
        try check(try await store.list().count == 2, "truncated movie rejected by size")
        let link = root.appendingPathComponent(UUID().uuidString)
        try fm.createSymbolicLink(at: link, withDestinationURL: saved.directory)
        try check(try await store.list().count == 2, "symlink entry excluded")
        let outside = root.appendingPathComponent("unrelated", isDirectory: true)
        let external = try fixture(at: outside)
        do { try await store.delete(external); throw Failure.failed("outside path accepted") }
        catch VisiblePOCStore.StoreError.outsideLibrary { try check(true, "delete path restricted") }
        do { try await store.discard(saved.directory); throw Failure.failed("saved directory discarded") }
        catch VisiblePOCStore.StoreError.outsideLibrary { try check(true, "discard cannot remove saved output") }
        try await store.delete(saved)
        try check(try await store.list().count == 1, "explicit selection deletes one result")
        try check(fm.fileExists(atPath: legacy.path), "unselected result preserved")
        // Regression coverage: every generation owns a fresh staging directory.
        func rejects(_ label: String, _ action: () async throws -> Void) async throws {
            do { try await action() }
            catch { try check(true, label); return }
            throw Failure.failed(label)
        }
        let duplicateID = UUID()
        let duplicate = try await store.stage(id: duplicateID)
        let sentinel = duplicate.appendingPathComponent("sentinel")
        try Data([42]).write(to: sentinel)
        try await rejects("duplicate operation ID rejected") { _ = try await store.stage(id: duplicateID) }
        try check(try Data(contentsOf: sentinel) == Data([42]), "duplicate leaves pending data intact")
        try await store.discard(duplicate)
        let committedID = UUID(uuidString: legacy.lastPathComponent)!
        try await rejects("committed operation ID rejected before rendering") { _ = try await store.stage(id: committedID) }
        try check(fm.fileExists(atPath: legacy.path), "collision leaves saved video intact")

        let attackRoot = root.appendingPathComponent("path-tests")
        let attackStore = VisiblePOCStore(root: attackRoot)
        let externalRoot = root.appendingPathComponent("external")
        try fm.createDirectory(at: externalRoot, withIntermediateDirectories: true)
        try fm.createDirectory(at: attackRoot, withIntermediateDirectories: true)
        let pendingLink = attackRoot.appendingPathComponent(".pending")
        try fm.createSymbolicLink(at: pendingLink, withDestinationURL: externalRoot)
        try await rejects("symlink staging parent rejected before writing") { _ = try await attackStore.stage(id: UUID()) }
        try check(try fm.contentsOfDirectory(atPath: externalRoot.path).isEmpty, "outside directory remains untouched")
        try fm.removeItem(at: pendingLink)
        try fm.removeItem(at: attackRoot)
        try fm.createSymbolicLink(at: attackRoot, withDestinationURL: externalRoot)
        try await rejects("replaced library root rejected before writing") { _ = try await attackStore.stage(id: UUID()) }
        try check(try fm.contentsOfDirectory(atPath: externalRoot.path).isEmpty, "replaced root does not redirect writes")
        try fm.removeItem(at: attackRoot)
        let normal = try await attackStore.stage(id: UUID())
        try await attackStore.discard(normal)
        let danglingID = UUID()
        let dangling = attackRoot.appendingPathComponent(".pending").appendingPathComponent(danglingID.uuidString)
        try fm.createSymbolicLink(at: dangling, withDestinationURL: externalRoot.appendingPathComponent("missing"))
        try await rejects("dangling staging symlink rejected") { _ = try await attackStore.stage(id: danglingID) }
        try check(!fm.fileExists(atPath: externalRoot.appendingPathComponent("missing").path), "dangling target not created")

        // Structural validation is not a substitute for renderer movie decoding.
        let invalidPath = root.appendingPathComponent(UUID().uuidString)
        func mutatedReport(_ key: String, _ value: Any) throws -> VisiblePOCResult {
            let item = try fixture(at: invalidPath)
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: item.json)) as! [String: Any]
            json[key] = value
            try JSONSerialization.data(withJSONObject: json).write(to: item.json)
            return item
        }
        for (key, value) in [("aiInference", true as Any), ("durationSeconds", 5 as Any),
                             ("gpuCommandSeconds", -1 as Any), ("width", 961 as Any)] {
            let item = try mutatedReport(key, value)
            try check(try await store.list().allSatisfy { $0.id != item.id }, "inconsistent \(key) report excluded")
        }
        try fm.removeItem(at: invalidPath)
        let validLegacy = try fixture(at: invalidPath)
        try check(try await store.list().contains { $0.id == validLegacy.id }, "valid old report remains readable")
        for profile in VisiblePOCProfile.allCases {
            try check(profile.width.isMultiple(of: 2) && profile.height.isMultiple(of: 2)
                && profile.width * profile.height <= 1280 * 720, "bounded even profile \(profile.rawValue)")
        }
        print("\(count) storage/profile tests passed. No inference or GPU work executed by these tests.")
    }
    enum Failure: Error { case failed(String) }
}
