import CoreGraphics
import CoreML
import Foundation
import StableDiffusion

actor KeyframeGenerator: KeyframeBackend {
    nonisolated let kind: KeyframeBackendKind = .coreMLSD15
    private let resourceDirectory: URL?
    private var pipeline: StableDiffusionPipeline?
    private var loadedDirectory: URL?
    private var loadedReduceMemory: Bool?
    private var loadedComputePolicy: InferenceComputePolicy?
    init(resourceDirectory: URL? = nil) { self.resourceDirectory = resourceDirectory }
    private func resolveDirectory() async -> URL? {
        if let resourceDirectory {
            return ModelManifest.validateResources(at: resourceDirectory) ? resourceDirectory : nil
        }
        return await ModelManager.shared.installedModelDirectory()
    }
    func isReady() async -> Bool { await resolveDirectory() != nil }
    func generate(request: GenerationRequest, capabilities: DeviceCapabilities,
                  progress: @escaping @Sendable (Double, String) -> Void) async throws -> [CGImage] {
        try request.validatedFrameCount()
        try Task.checkCancellation()
        guard let directory = await resolveDirectory() else { throw GenerationError.modelMissing }
        let profile = capabilities.profile(for: request.quality)
        progress(0, "Loading Core ML resources • \(request.computePolicy.title)")
        let pipeline = try pipelineFor(directory: directory, reduceMemory: profile.reduceMemory, policy: request.computePolicy)
        let count = profile.keyframes
        var images: [CGImage] = []
        var previous: CGImage?
        for index in 0..<count {
            try Task.checkCancellation()
            if let previous, request.motionStrength == 0 {
                images.append(previous)
                progress(Double(index + 1) / Double(count), "Zero motion • reusing generated keyframe")
                continue
            }
            var config = StableDiffusionPipeline.Configuration(prompt: request.prompt)
            config.negativePrompt = request.negativePrompt
            config.stepCount = profile.steps
            config.guidanceScale = request.quality.guidanceScale
            config.schedulerType = .dpmSolverMultistepScheduler
            config.seed = request.seed &+ UInt32(index * 97)
            config.disableSafety = false
            // Report the same denoised representation consumed by the final decoder.
            config.useDenoisedIntermediates = true
            if let previous { config.startingImage = previous; config.strength = request.motionStrength }
            let base = Double(index) / Double(count)
            var invalidNumerics = false
            let result = try pipeline.generateImages(configuration: config) { step in
                let health = step.currentLatentSamples.map { InferenceNumerics.inspect($0.scalars) }
                if health.isEmpty || health.contains(where: { !$0.isValid }) {
                    invalidNumerics = true
                    progress(base, "Core ML aborted: empty or non-finite latent tensor")
                    return false
                }
                if step.step + 1 == step.stepCount {
                    let magnitude = health.map(\.maximumAbsoluteValue).max() ?? 0
                    progress(base, String(format: "Final latent health: finite • max |value| %.4f", magnitude))
                }
                let local = Double(step.step + 1) / Double(max(step.stepCount, 1))
                progress(base + local / Double(count), "Core ML keyframe \(index + 1)/\(count) • step \(step.step + 1)/\(step.stepCount)")
                return !Task.isCancelled
            }
            try Task.checkCancellation()
            if invalidNumerics { throw GenerationError.invalidNumerics }
            guard !result.isEmpty else { throw GenerationError.noImage }
            guard let image = result.compactMap({ $0 }).first else {
                // The pinned Apple pipeline replaces decoded, filtered images with nil.
                throw GenerationError.safetyFiltered
            }
            images.append(image); previous = image
        }
        return images
    }
    /// Reload resources whenever scheduling policy changes; do not reuse a different policy.
    private func pipelineFor(directory: URL, reduceMemory: Bool, policy: InferenceComputePolicy) throws -> StableDiffusionPipeline {
        if let pipeline, loadedDirectory == directory, loadedReduceMemory == reduceMemory, loadedComputePolicy == policy { return pipeline }
        pipeline?.unloadResources()
        pipeline = nil; loadedDirectory = nil; loadedReduceMemory = nil; loadedComputePolicy = nil
        let configuration = MLModelConfiguration()
        switch policy {
        case .automatic: configuration.computeUnits = .all
        case .cpuAndGPU: configuration.computeUnits = .cpuAndGPU
        case .cpuAndNeuralEngine: configuration.computeUnits = .cpuAndNeuralEngine
        case .cpuOnly: configuration.computeUnits = .cpuOnly
        }
        let created = try StableDiffusionPipeline(resourcesAt: directory, controlNet: [], configuration: configuration,
            disableSafety: false, reduceMemory: reduceMemory)
        do { try created.loadResources() }
        catch { created.unloadResources(); throw error }
        pipeline = created; loadedDirectory = directory; loadedReduceMemory = reduceMemory; loadedComputePolicy = policy
        return created
    }
    enum GenerationError: LocalizedError {
        case modelMissing, noImage, safetyFiltered, invalidNumerics
        var errorDescription: String? {
            switch self {
            case .modelMissing: return "The on-device Core ML model is not installed yet."
            case .invalidNumerics: return "Core ML produced an empty or non-finite latent tensor. No video was exported."
            case .noImage: return "Core ML returned no image samples."
            case .safetyFiltered: return "The safety checker filtered this generated image. No image or video was saved."
            }
        }
    }
}
