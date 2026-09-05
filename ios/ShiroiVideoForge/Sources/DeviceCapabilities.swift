import Foundation
import Metal

struct DeviceCapabilities: Sendable {
    enum MemoryClass: String, Sendable {
        case eightGB = "8 GB class"
        case sixteenGB = "16 GB class"
    }

    struct InferenceProfile: Sendable {
        let keyframes: Int
        let steps: Int
        let reduceMemory: Bool
        let bitrate: Int
    }

    let memoryBytes: UInt64
    let cpuCores: Int
    let gpuName: String
    let maxBufferLength: Int
    let lowPowerModeEnabled: Bool
    let thermalState: String

    var memoryGB: Double { Double(memoryBytes) / 1_073_741_824.0 }
    var memoryClass: MemoryClass { memoryBytes >= 12 * 1_073_741_824 ? .sixteenGB : .eightGB }

    func profile(for quality: GenerationQuality) -> InferenceProfile {
        switch (memoryClass, quality) {
        case (.eightGB, .fast):
            return InferenceProfile(keyframes: 2, steps: 8, reduceMemory: true, bitrate: 5_000_000)
        case (.eightGB, .balanced):
            return InferenceProfile(keyframes: 3, steps: 12, reduceMemory: true, bitrate: 7_000_000)
        case (.eightGB, .quality):
            return InferenceProfile(keyframes: 4, steps: 16, reduceMemory: true, bitrate: 9_000_000)
        case (.sixteenGB, .fast):
            return InferenceProfile(keyframes: 3, steps: 10, reduceMemory: false, bitrate: 6_000_000)
        case (.sixteenGB, .balanced):
            return InferenceProfile(keyframes: 5, steps: 18, reduceMemory: false, bitrate: 9_000_000)
        case (.sixteenGB, .quality):
            return InferenceProfile(keyframes: 6, steps: 24, reduceMemory: false, bitrate: 12_000_000)
        }
    }

    static func current() -> DeviceCapabilities {
        let process = ProcessInfo.processInfo
        let device = MTLCreateSystemDefaultDevice()
        return DeviceCapabilities(
            memoryBytes: process.physicalMemory,
            cpuCores: process.processorCount,
            gpuName: device?.name ?? "Metal unavailable",
            maxBufferLength: device?.maxBufferLength ?? 0,
            lowPowerModeEnabled: process.isLowPowerModeEnabled,
            thermalState: thermalLabel(process.thermalState)
        )
    }

    private static func thermalLabel(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}
