import Foundation

enum GenerationQuality: String, CaseIterable, Identifiable, Sendable {
    case fast, balanced, quality
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
    case dissolve, opticalFlow
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

    /// Validate before conversion to Int, allocation, inference, or encoder startup.
    @discardableResult
    func validatedFrameCount() throws -> Int {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RequestError.invalid("Enter a prompt before generating.")
        }
        guard duration.isFinite, duration >= 1, duration <= 30,
              (1...60).contains(fps) else {
            throw RequestError.invalid("Duration must be 1–30 seconds and frame rate 1–60 fps.")
        }
        guard (64...2048).contains(width), (64...2048).contains(height),
              width.isMultiple(of: 2), height.isMultiple(of: 2),
              width * height <= 2_097_152 else {
            throw RequestError.invalid("Use even video dimensions within the 2-megapixel export limit.")
        }
        guard motionStrength.isFinite, (0...1).contains(motionStrength),
              (100_000...100_000_000).contains(bitrate) else {
            throw RequestError.invalid("Invalid motion strength or video bitrate.")
        }
        return max(Int((duration * Double(fps)).rounded()), 2)
    }

    enum RequestError: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            switch self { case .invalid(let message): return message }
        }
    }
}
