import Foundation

actor VideoForgeEngine {
    private let keyframes: any KeyframeBackend
    private let composer = MetalVideoComposer()
    init(keyframes: any KeyframeBackend = KeyframeGenerator()) { self.keyframes = keyframes }

    func generate(request: GenerationRequest, capabilities: DeviceCapabilities,
                  progress: @escaping @Sendable (Double, String) -> Void) async throws -> GenerationResult {
        let outputFrames = try request.validatedFrameCount()
        try Task.checkCancellation()
        let startedAt = Date()
        let totalStart = ProcessInfo.processInfo.systemUptime
        let thermalBefore = DeviceCapabilities.current().thermalState
        let profile = capabilities.profile(for: request.quality)
        let backendKind = keyframes.kind
        progress(0.01, "Checking \(backendKind.rawValue) backend")
        guard await keyframes.isReady() else { throw ForgeError.backendNotReady(backendKind) }
        let inferenceStart = ProcessInfo.processInfo.systemUptime
        let generated = try await keyframes.generate(request: request, capabilities: capabilities) { value, message in
            progress(value * 0.78, message)
        }
        let inferenceSeconds = ProcessInfo.processInfo.systemUptime - inferenceStart
        try Task.checkCancellation()
        let metalStart = ProcessInfo.processInfo.systemUptime
        let composition = try await composer.compose(keyframes: generated, request: request, capabilities: capabilities) { value, message in
            progress(0.78 + value * 0.20, message)
        }
        defer { try? FileManager.default.removeItem(at: composition.url) }
        let metalEncodeSeconds = ProcessInfo.processInfo.systemUptime - metalStart
        try Task.checkCancellation()
        progress(0.99, "Saving video on this iPad")
        let saveStart = ProcessInfo.processInfo.systemUptime
        let finalURL = try await OutputStore.shared.persist(temporaryURL: composition.url)
        let saveSeconds = ProcessInfo.processInfo.systemUptime - saveStart
        let fileSize = Int64((try? finalURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let metrics = GenerationMetrics(
            startedAt: startedAt, totalSeconds: ProcessInfo.processInfo.systemUptime - totalStart,
            coreMLSeconds: inferenceSeconds, metalEncodeSeconds: metalEncodeSeconds, saveSeconds: saveSeconds,
            outputBytes: fileSize, keyframes: generated.count, diffusionStepsPerKeyframe: profile.steps,
            outputFrames: outputFrames, fps: request.fps, quality: request.quality, keyframeBackend: backendKind,
            requestedTemporalMode: request.temporalMode, actualTemporalPath: composition.temporalPath,
            memoryClass: capabilities.memoryClass, thermalBefore: thermalBefore,
            thermalAfter: DeviceCapabilities.current().thermalState, lowPowerModeEnabled: capabilities.lowPowerModeEnabled,
            requestedComputePolicy: request.computePolicy
        )
        return GenerationResult(url: finalURL, metrics: metrics)
    }
    enum ForgeError: LocalizedError {
        case backendNotReady(KeyframeBackendKind)
        var errorDescription: String? {
            switch self { case .backendNotReady(let kind): return "The \(kind.rawValue) keyframe backend is not ready yet." }
        }
    }
}
