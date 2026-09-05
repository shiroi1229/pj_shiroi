import Foundation

actor VideoForgeEngine {
    private let keyframes = KeyframeGenerator()
    private let composer = MetalVideoComposer()

    func generate(
        request: GenerationRequest,
        capabilities: DeviceCapabilities,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> URL {
        if Task.isCancelled { throw CancellationError() }
        progress(0.01, "Checking on-device Core ML model")
        guard let model = await ModelManager.shared.installedModelDirectory() else {
            throw ForgeError.modelMissing
        }

        let generated = try await keyframes.generate(
            request: request,
            modelDirectory: model,
            capabilities: capabilities
        ) { value, message in
            progress(value * 0.78, message)
        }

        if Task.isCancelled { throw CancellationError() }
        let temporary = try await composer.compose(
            keyframes: generated,
            request: request,
            capabilities: capabilities
        ) { value, message in
            progress(0.78 + value * 0.20, message)
        }

        if Task.isCancelled { throw CancellationError() }
        progress(0.99, "Saving video on this iPad")
        return try await OutputStore.shared.persist(temporaryURL: temporary)
    }

    enum ForgeError: LocalizedError {
        case modelMissing

        var errorDescription: String? {
            "The on-device Core ML model is not installed yet."
        }
    }
}
