import Foundation

struct VisiblePOCReport: Codable, Sendable {
    let status: String
    let host: String
    let gpu: String
    let width: Int
    let height: Int
    let fps: Int
    let frames: Int
    let decodedFrames: Int
    let durationSeconds: Double
    let renderAndEncodeSeconds: Double
    let gpuCommandSeconds: Double?
    let outputBytes: Int
    let aiInference: Bool
    let source: String
}
struct VisiblePOCResult: Identifiable, Sendable {
    var id: String { directory.lastPathComponent }
    let directory: URL
    let report: VisiblePOCReport
    var movie: URL { directory.appendingPathComponent("poc-video.mov") }
    var poster: URL { directory.appendingPathComponent("poc-poster.png") }
    var json: URL { directory.appendingPathComponent("poc-result.json") }
}

/// Fixed, bounded profiles; resolution means GPU render output, not AI inference.
enum VisiblePOCProfile: String, CaseIterable, Identifiable, Sendable {
    case preview, hd, portrait
    var id: String { rawValue }
    var width: Int { switch self { case .preview: return 960; case .hd: return 1280; case .portrait: return 720 } }
    var height: Int { switch self { case .preview: return 540; case .hd: return 720; case .portrait: return 1280 } }
    var title: String { switch self { case .preview: return "軽量 540p"; case .hd: return "HD 720p"; case .portrait: return "縦型 720p" } }
    var fps: Int { 24 }
    var frames: Int { 144 }
}
