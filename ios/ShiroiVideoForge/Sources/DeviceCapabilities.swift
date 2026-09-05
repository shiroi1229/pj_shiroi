import Foundation
import Metal

struct DeviceCapabilities: Sendable {
    enum MemoryClass: String, Sendable {
        case eightGB = "8 GB class"
        case sixteenGB = "16 GB class"
    }

    let memoryBytes: UInt64
    let cpuCores: Int
    let gpuName: String
    let maxBufferLength: Int

    var memoryGB: Double { Double(memoryBytes) / 1_073_741_824.0 }
    var memoryClass: MemoryClass { memoryBytes >= 12 * 1_073_741_824 ? .sixteenGB : .eightGB }
    var recommendedKeyframes: Int { memoryClass == .sixteenGB ? 5 : 3 }
    var recommendedSteps: Int { memoryClass == .sixteenGB ? 18 : 12 }

    static func current() -> DeviceCapabilities {
        let device = MTLCreateSystemDefaultDevice()
        return DeviceCapabilities(
            memoryBytes: ProcessInfo.processInfo.physicalMemory,
            cpuCores: ProcessInfo.processInfo.processorCount,
            gpuName: device?.name ?? "Metal unavailable",
            maxBufferLength: device?.maxBufferLength ?? 0
        )
    }
}
