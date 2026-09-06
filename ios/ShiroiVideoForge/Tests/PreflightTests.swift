import Foundation

@main
enum PreflightTests {
    static func main() throws {
        var passed = 0
        func check(_ name: String, _ condition: @autoclosure () throws -> Bool) throws {
            guard try condition() else { throw Failure.failed(name) }
            passed += 1
            print("PASS \(name)")
        }
        func rejects(_ change: (inout GenerationRequest) -> Void) -> Bool {
            var request = GenerationRequest(prompt: "a city", negativePrompt: "")
            change(&request)
            do { _ = try request.validatedFrameCount(); return false } catch { return true }
        }
        let request = GenerationRequest(prompt: "a city", negativePrompt: "")
        try check("default 3s/24fps has 72 frames", try request.validatedFrameCount() == 72)
        try check("blank prompt", rejects { $0.prompt = " \n " })
        try check("NaN duration", rejects { $0.duration = .nan })
        try check("infinite duration", rejects { $0.duration = .infinity })
        try check("negative duration", rejects { $0.duration = -1 })
        try check("excessive duration", rejects { $0.duration = 31 })
        try check("zero fps", rejects { $0.fps = 0 })
        try check("excessive fps", rejects { $0.fps = Int.max })
        try check("odd width", rejects { $0.width = 511 })
        try check("zero height", rejects { $0.height = 0 })
        try check("oversize width no integer overflow", rejects { $0.width = Int.max })
        try check("pixel budget", rejects { $0.width = 2048; $0.height = 2048 })
        try check("NaN motion", rejects { $0.motionStrength = .nan })
        try check("motion above one", rejects { $0.motionStrength = 1.1 })
        try check("zero bitrate", rejects { $0.bitrate = 0 })
        try check("model URL uses https", ModelManifest.downloadURL.scheme == "https")
        try check("model URL pins immutable revision", ModelManifest.downloadURL.path.contains(ModelManifest.revision))
        try check("model URL has actual filename", !ModelManifest.archiveName.contains("-base-"))
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try check("empty model rejected", !ModelManifest.validateResources(at: root))
        for name in ModelManifest.requiredDirectories {
            let dir = root.appendingPathComponent(name)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data([1]).write(to: dir.appendingPathComponent("test.bin"))
        }
        for name in ModelManifest.requiredFiles { try Data([1]).write(to: root.appendingPathComponent(name)) }
        try check("structurally complete model accepted", ModelManifest.validateResources(at: root))
        try Data().write(to: root.appendingPathComponent("merges.txt"))
        try check("empty tokenizer rejected", !ModelManifest.validateResources(at: root))
        try Data([1]).write(to: root.appendingPathComponent("merges.txt"))
        try fm.removeItem(at: root.appendingPathComponent("Unet.mlmodelc/test.bin"))
        try check("empty compiled model rejected", !ModelManifest.validateResources(at: root))
        try check("automatic compute default", request.computePolicy == .automatic)
        try check("four distinct compute policies", Set(InferenceComputePolicy.allCases.map(\.rawValue)).count == 4)
        print("\(passed) checks passed. No Apple SDK, model inference, or device performance is tested here.")
    }
    enum Failure: Error { case failed(String) }
}
