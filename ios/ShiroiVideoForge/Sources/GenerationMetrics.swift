import Foundation

struct GenerationMetrics: Sendable {
    let startedAt: Date
    let totalSeconds: Double
    let coreMLSeconds: Double
    let metalEncodeSeconds: Double
    let saveSeconds: Double
    let outputBytes: Int64
    let keyframes: Int
    let diffusionStepsPerKeyframe: Int
    let outputFrames: Int
    let fps: Int
    let quality: GenerationQuality
    let temporalMode: TemporalMode
    let memoryClass: DeviceCapabilities.MemoryClass
    let thermalBefore: String
    let thermalAfter: String
    let lowPowerModeEnabled: Bool

    var outputMegabytes: Double {
        Double(outputBytes) / 1_048_576.0
    }

    var encodeFramesPerSecond: Double {
        guard metalEncodeSeconds > 0 else { return 0 }
        return Double(outputFrames) / metalEncodeSeconds
    }

    var coreMLSecondsPerKeyframe: Double {
        guard keyframes > 0 else { return 0 }
        return coreMLSeconds / Double(keyframes)
    }

    var realtimeFactor: Double {
        let videoSeconds = Double(outputFrames) / Double(max(fps, 1))
        guard videoSeconds > 0 else { return 0 }
        return totalSeconds / videoSeconds
    }
}

struct GenerationResult: Sendable {
    let url: URL
    let metrics: GenerationMetrics
}
