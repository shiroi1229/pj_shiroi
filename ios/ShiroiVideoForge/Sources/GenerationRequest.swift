import Foundation

enum GenerationQuality: String, CaseIterable, Identifiable, Sendable {
    case fast
    case balanced
    case quality

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: return "Fast"
        case .balanced: return "Balanced"
        case .quality: return "Quality"
        }
    }

    var guidanceScale: Float {
        switch self {
        case .fast: return 6.0
        case .balanced: return 7.0
        case .quality: return 7.5
        }
    }
}

enum TemporalMode: String, CaseIterable, Identifiable, Sendable {
    case dissolve
    case opticalFlow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dissolve: return "Metal Blend"
        case .opticalFlow: return "Vision Flow"
        }
    }
}

struct GenerationRequest: Sendable {
    var prompt: String
    var negativePrompt: String
    var duration: Double = 3.0
    var fps: Int = 24
    var width: Int = 512
    var height: Int = 512
    var seed: UInt32 = 1229
    var quality: GenerationQuality = .balanced
    var motionStrength: Float = 0.26
    var bitrate: Int = 8_000_000
    var temporalMode: TemporalMode = .dissolve
}
