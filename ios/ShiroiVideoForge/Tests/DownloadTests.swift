import Foundation

@main
enum DownloadTests {
    static func main() async throws {
        setbuf(stdout, nil)
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("download-tests-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let source = URL(string: "http://localhost:18764/model.bin")!
        func downloader(_ name: String) -> ArchiveDownloader {
            ArchiveDownloader(destination: root.appendingPathComponent(name + ".zip"),
                resumeURL: root.appendingPathComponent(name + ".resume"), progress: { _, _ in })
        }
        let before = Task { try await downloader("before").download(from: source) }
        before.cancel()
        do { _ = try await before.value; throw Failure.failed("pre-cancel completed") }
        catch is CancellationError { print("PASS cancel before task startup") }
        let (events, signal) = AsyncStream<Double>.makeStream()
        let attempt = ArchiveDownloader(destination: root.appendingPathComponent("resume.zip"),
            resumeURL: root.appendingPathComponent("resume.resume"), progress: { fraction, _ in
                if fraction >= 0.125 { signal.yield(fraction) }
            })
        let mid = Task {
            defer { signal.finish() }
            do { return try await attempt.download(from: source) }
            catch {
                let ns = error as NSError
                print("Fixture transfer ended: \(ns.domain) code \(ns.code)")
                throw error
            }
        }
        let timeout = Task {
            do { try await Task.sleep(for: .seconds(20)); mid.cancel(); signal.finish() }
            catch { }
        }
        var received = false
        for await _ in events { received = true; mid.cancel(); break }
        signal.finish(); timeout.cancel()
        if !received {
            _ = try await mid.value
            throw Failure.failed("fixture never delivered progress")
        }
        do { _ = try await mid.value; throw Failure.failed("mid-cancel completed") }
        catch is CancellationError { print("PASS in-flight cancel after receiving data") }
        guard let data = try? Data(contentsOf: root.appendingPathComponent("resume.resume")), !data.isEmpty else {
            throw Failure.failed("resumable fixture produced no resume data after body receipt")
        }
        print("PASS opaque resume data saved")
        let file = try await downloader("resume").download(from: source)
        let bytes = try Data(contentsOf: file)
        guard bytes.count == 8 * 1024 * 1024, bytes.allSatisfy({ $0 == 70 }) else {
            throw Failure.failed("resumed file corrupt")
        }
        print("PASS resumed download exact size and contents")
        guard !fm.fileExists(atPath: root.appendingPathComponent("resume.resume").path) else {
            throw Failure.failed("stale resume data after success")
        }
        print("PASS resume state removed after success")
        do {
            _ = try await downloader("404").download(from: URL(string: "http://localhost:18764/missing")!)
            throw Failure.failed("HTTP 404 accepted")
        } catch ArchiveDownloader.DownloadError.http(404) { print("PASS HTTP 404 rejected") }
        let abc = root.appendingPathComponent("hash-fixture")
        try Data("abc".utf8).write(to: abc)
        let knownHash = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        try ArchiveIntegrity.verify(at: abc, expectedBytes: 3, expectedSHA256: knownHash)
        print("PASS known SHA-256 fixture")
        do { try ArchiveIntegrity.verify(at: abc, expectedBytes: 4, expectedSHA256: knownHash); throw Failure.failed("size accepted") }
        catch ArchiveIntegrity.IntegrityError.sizeMismatch { print("PASS wrong size rejected") }
        do { try ArchiveIntegrity.verify(at: abc, expectedBytes: 3, expectedSHA256: String(repeating: "0", count: 64)); throw Failure.failed("hash accepted") }
        catch ArchiveIntegrity.IntegrityError.hashMismatch { print("PASS wrong hash rejected") }
        print("9 download and integrity checks passed against a local HTTP fixture; not an iPad network test.")
    }
    enum Failure: Error { case failed(String) }
}
