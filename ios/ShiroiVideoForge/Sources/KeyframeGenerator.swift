import CoreGraphics
import CoreML
import Foundation
import StableDiffusion

actor KeyframeGenerator: KeyframeBackend {
    nonisolated let kind: KeyframeBackendKind = .coreMLSD15

    private var pipeline: StableDiffusionPipeline?
    private var loadedDirectory: URL?
    private var loadedReduceMemory: Bool?

    func isReady() async -> Bool {
        await ModelManager.shared.installedModelDirectory() != nil
    }

    func generate(
        request: GenerationRequest,
        capabilities: DeviceCapabilities,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> [CGImage] {
        guard let modelDirectory = await ModelManager.shared.installedModelDirectory() else {
            throw GenerationError.modelMissing
        }

        let profile = capabilities.profile(for: request.quality)
        let pipeline = try pipelineFor(directory: modelDirectory, reduceMemory: profile.reduceMemory)
        let count = profile.keyframes
        var images: [CGImage] = []
        var previous: CGImage?

        for index in 0..<count {
            if Task.isCancelled { throw CancellationError() }

            var config = StableDiffusionPipeline.Configuration(prompt: request.prompt)
            config.negativePrompt = request.negativePrompt
            config.stepCount = profile.steps
            config.guidanceScale = request.quality.guidanceScale
            config.schedulerType = .dpmSolverMultistepScheduler
            config.seed = request.seed &+ UInt32(index * 97)
            config.disableSafety = false

            if let previous, index > 0 {
                config.startingImage = previous
                config.strength = request.motionStrength
            }

            let base = Double(index) / Double(count)
            let result = try pipeline.generateImages(configuration: config) { step in
                let local = Double(step.step + 1) / Double(max(step.stepCount, 1))
                progress(
                    base + local / Double(count),
                    "Core ML keyframe \(index + 1)/\(count) • step \(step.step + 1)/\(step.stepCount)"
                )
                return !Task.isCancelled
            }

            if Task.isCancelled { throw CancellationError() }
            guard let image = result.compactMap({ $0 }).first else {
                throw GenerationError.noImage
            }
            images.append(image)
            previous = image
        }
        return images
    }

    private func pipelineFor(directory: URL, reduceMemory: Bool) throws -> StableDiffusionPipeline {
        if let pipeline,
           loadedDirectory == directory,
           loadedReduceMemory == reduceMemory {
            return pipeline
        }

        pipeline?.unloadResources()

        let configuration = MLModelConfiguration()
        // Allow Core ML to schedule across GPU, Neural Engine and CPU.
        configuration.computeUnits = .all

        let created = try StableDiffusionPipeline(
            resourcesAt: directory,
            controlNet: [],
            configuration: configuration,
            disableSafety: false,
            reduceMemory: reduceMemory
        )
        try created.loadResources()
        pipeline = created
        loadedDirectory = directory
        loadedReduceMemory = reduceMemory
        return created
    }

    enum GenerationError: LocalizedError {
        case modelMissing
        case noImage

        var errorDescription: String? {
            switch self {
            case .modelMissing:
                return "The on-device Core ML model is not installed yet."
            case .noImage:
                return "Core ML completed without returning a usable image."
            }
        }
    }
}
