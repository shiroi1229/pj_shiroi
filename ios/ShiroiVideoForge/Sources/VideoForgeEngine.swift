import Foundation

actor VideoForgeEngine {
    private let keyframes = KeyframeGenerator()
    private let composer = MetalVideoComposer()

    func generate(
        request: GenerationRequest,
        capabilities: DeviceCapabilities,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> GenerationResult {
        let startedAt = Date()
        let totalStart = ProcessInfo.processInfo.systemUptime
        let thermalBefore = DeviceCapabilities.current().thermalState
        let profile = capabilities.profile(for: request.quality)

        if Task.isCancelled { throw CancellationError() }
        progress(0.01, "Checking on-device Core ML model")
        guard let model = await ModelManager.shared.installedModelDirectory() else {
            throw ForgeError.modelMissing
        }

        let coreMLStart = ProcessInfo.processInfo.systemUptime
        let generated = try await keyframes.generate(
            request: request,
            modelDirectory: model,
            capabilities: capabilities
        ) { value, message in
            progress(value * 0.78, message)
        }
        let coreMLSeconds = ProcessInfo.processInfo.systemUptime - coreMLStart

        if Task.isCancelled { throw CancellationError() }
        let metalStart = ProcessInfo.processInfo.systemUptime
        let temporary = try await composer.compose(
            keyframes: generated,
            request: request,
            capabilities: capabilities
        ) { value, message in
            progress(0.78 + value * 0.20, message)
        }
        let metalEncodeSeconds = ProcessInfo.processInfo.systemUptime - metalStart

        if Task.isCancelled { throw CancellationError() }
        progress(0.99, "Saving video on this iPad")
        let saveStart = ProcessInfo.processInfo.systemUptime
        let finalURL = try await OutputStore.shared.persist(temporaryURL: temporary)
        let saveSeconds = ProcessInfo.processInfo.systemUptime - saveStart

        let fileSize = Int64(
            (try? finalURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        )
        let totalSeconds = ProcessInfo.processInfo.systemUptime - totalStart
        let thermalAfter = DeviceCapabilities.current().thermalState
        let outputFrames = max(Int(request.duration * Double(request.fps)), 2)

        let metrics = GenerationMetrics(
            startedAt: startedAt,
            totalSeconds: totalSeconds,
            coreMLSeconds: coreMLSeconds,
            metalEncodeSeconds: metalEncodeSeconds,
            saveSeconds: saveSeconds,
            outputBytes: fileSize,
            keyframes: generated.count,
            diffusionStepsPerKeyframe: profile.steps,
            outputFrames: outputFrames,
            fps: request.fps,
            quality: request.quality,
            memoryClass: capabilities.memoryClass,
            thermalBefore: thermalBefore,
            thermalAfter: thermalAfter,
            lowPowerModeEnabled: capabilities.lowPowerModeEnabled
        )
        return GenerationResult(url: finalURL, metrics: metrics)
    }

    enum ForgeError: LocalizedError {
        case modelMissing

        var errorDescription: String? {
            "The on-device Core ML model is not installed yet."
        }
    }
}
