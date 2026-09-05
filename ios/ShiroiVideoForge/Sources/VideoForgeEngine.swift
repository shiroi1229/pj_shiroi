import Foundation

actor VideoForgeEngine {
    private let keyframes = KeyframeGenerator()
    private let composer = MetalVideoComposer()

    func generate(request: GenerationRequest, capabilities: DeviceCapabilities, progress: @escaping @Sendable (Double, String) -> Void) async throws -> URL {
        progress(0.01, "Checking Core ML model")
        guard let model = await ModelManager.shared.installedModelDirectory() else {
            throw ForgeError.modelMissing
        }

        let generated = try await keyframes.generate(request: request, modelDirectory: model, capabilities: capabilities) { value, message in
            progress(value * 0.80, message)
        }
        return try await composer.compose(keyframes: generated, request: request) { value, message in
            progress(0.80 + value * 0.20, message)
        }
    }

    enum ForgeError: LocalizedError {
        case modelMissing
        var errorDescription: String? { "The on-device Core ML model is not installed yet." }
    }
}
