import CoreGraphics
import CoreML
import Foundation
import StableDiffusion

actor KeyframeGenerator {
    private var pipeline: StableDiffusionPipeline?
    private var loadedDirectory: URL?

    func generate(request: GenerationRequest, modelDirectory: URL, capabilities: DeviceCapabilities, progress: @escaping @Sendable (Double, String) -> Void) throws -> [CGImage] {
        let pipeline = try pipelineFor(directory: modelDirectory)
        let count = capabilities.recommendedKeyframes
        var images: [CGImage] = []
        var previous: CGImage?

        for index in 0..<count {
            var config = StableDiffusionPipeline.Configuration(prompt: request.prompt)
            config.negativePrompt = request.negativePrompt
            config.stepCount = capabilities.recommendedSteps
            config.guidanceScale = 7.0
            config.schedulerType = .dpmSolverMultistepScheduler
            config.seed = request.seed &+ UInt32(index * 97)
            config.disableSafety = false

            if let previous, index > 0 {
                config.startingImage = previous
                config.strength = capabilities.memoryClass == .sixteenGB ? 0.30 : 0.22
            }

            let base = Double(index) / Double(count)
            let result = try pipeline.generateImages(configuration: config) { step in
                let local = Double(step.step + 1) / Double(max(step.stepCount, 1))
                progress(base + local / Double(count), "AI keyframe \(index + 1)/\(count) • step \(step.step + 1)/\(step.stepCount)")
                return true
            }

            guard let image = result.compactMap({ $0 }).first else {
                throw GenerationError.noImage
            }
            images.append(image)
            previous = image
        }
        return images
    }

    private func pipelineFor(directory: URL) throws -> StableDiffusionPipeline {
        if let pipeline, loadedDirectory == directory { return pipeline }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        let created = try StableDiffusionPipeline(
            resourcesAt: directory,
            controlNet: [],
            configuration: configuration,
            disableSafety: false,
            reduceMemory: true
        )
        try created.loadResources()
        pipeline = created
        loadedDirectory = directory
        return created
    }

    enum GenerationError: LocalizedError {
        case noImage
        var errorDescription: String? { "Core ML completed without returning a usable image." }
    }
}
