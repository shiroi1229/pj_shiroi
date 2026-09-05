import CoreGraphics
import Foundation

enum KeyframeBackendKind: String, Sendable {
    case coreMLSD15 = "Core ML SD 1.5"
    case mlxSDXLTurbo = "MLX SDXL Turbo"
}

protocol KeyframeBackend: AnyObject {
    nonisolated var kind: KeyframeBackendKind { get }

    func isReady() async -> Bool

    func generate(
        request: GenerationRequest,
        capabilities: DeviceCapabilities,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> [CGImage]
}
