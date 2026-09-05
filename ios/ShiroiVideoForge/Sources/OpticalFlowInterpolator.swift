import CoreGraphics
import CoreVideo
import Foundation
import Metal
import MetalKit
import Vision

struct OpticalFlowSegment {
    let source: MTLTexture
    let target: MTLTexture
    let flow: CVPixelBuffer
}

final class OpticalFlowInterpolator {
    enum FlowError: LocalizedError {
        case commandQueueUnavailable
        case defaultLibraryUnavailable
        case kernelUnavailable
        case textureCacheUnavailable(CVReturn)
        case opticalFlowUnavailable
        case textureCreationFailed
        case commandBufferUnavailable
        case encoderUnavailable
        case gpuFailure

        var errorDescription: String? {
            switch self {
            case .commandQueueUnavailable: return "Metal command queue is unavailable."
            case .defaultLibraryUnavailable: return "Metal shader library is unavailable."
            case .kernelUnavailable: return "Optical-flow Metal kernel is unavailable."
            case .textureCacheUnavailable(let status): return "Metal texture cache failed with status \(status)."
            case .opticalFlowUnavailable: return "Vision did not return an optical-flow field."
            case .textureCreationFailed: return "Could not create a Metal texture for optical flow."
            case .commandBufferUnavailable: return "Could not allocate a Metal command buffer."
            case .encoderUnavailable: return "Could not allocate a Metal compute encoder."
            case .gpuFailure: return "Metal optical-flow frame synthesis failed."
            }
        }
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private let textureLoader: MTKTextureLoader
    private var textureCache: CVMetalTextureCache

    init(device: MTLDevice) throws {
        self.device = device
        guard let commandQueue = device.makeCommandQueue() else {
            throw FlowError.commandQueueUnavailable
        }
        self.commandQueue = commandQueue

        guard let library = device.makeDefaultLibrary() else {
            throw FlowError.defaultLibraryUnavailable
        }
        guard let function = library.makeFunction(name: "opticalFlowWarpBlend") else {
            throw FlowError.kernelUnavailable
        }
        pipeline = try device.makeComputePipelineState(function: function)
        textureLoader = MTKTextureLoader(device: device)

        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        guard status == kCVReturnSuccess, let cache else {
            throw FlowError.textureCacheUnavailable(status)
        }
        textureCache = cache
    }

    func prepare(keyframes: [CGImage], quality: GenerationQuality) throws -> [OpticalFlowSegment] {
        guard keyframes.count >= 2 else { return [] }
        var segments: [OpticalFlowSegment] = []
        segments.reserveCapacity(keyframes.count - 1)

        for index in 0..<(keyframes.count - 1) {
            if Task.isCancelled { throw CancellationError() }
            let sourceImage = keyframes[index]
            let targetImage = keyframes[index + 1]
            let sourceTexture = try makeTexture(from: sourceImage)
            let targetTexture = try makeTexture(from: targetImage)
            let flow = try generateFlow(from: sourceImage, to: targetImage, quality: quality)
            segments.append(OpticalFlowSegment(source: sourceTexture, target: targetTexture, flow: flow))
        }
        return segments
    }

    func render(segment: OpticalFlowSegment, progress: Float, into outputBuffer: CVPixelBuffer) throws {
        guard let flowTexture = texture(from: segment.flow, pixelFormat: .rg32Float),
              let outputTexture = texture(from: outputBuffer, pixelFormat: .bgra8Unorm) else {
            throw FlowError.textureCreationFailed
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw FlowError.commandBufferUnavailable
        }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw FlowError.encoderUnavailable
        }

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(segment.source, index: 0)
        encoder.setTexture(segment.target, index: 1)
        encoder.setTexture(flowTexture, index: 2)
        encoder.setTexture(outputTexture, index: 3)

        var clampedProgress = min(max(progress, 0), 1)
        encoder.setBytes(&clampedProgress, length: MemoryLayout<Float>.size, index: 0)

        let width = pipeline.threadExecutionWidth
        let height = max(1, pipeline.maxTotalThreadsPerThreadgroup / width)
        let threadsPerGroup = MTLSize(width: width, height: height, depth: 1)
        let grid = MTLSize(width: outputTexture.width, height: outputTexture.height, depth: 1)
        encoder.dispatchThreads(grid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            throw FlowError.gpuFailure
        }
    }

    private func generateFlow(from source: CGImage, to target: CGImage, quality: GenerationQuality) throws -> CVPixelBuffer {
        // VNGenerateOpticalFlowRequest reports motion relative to the image handled by
        // VNImageRequestHandler. To obtain the source→target field expected by the Metal
        // warp kernel, target the source image and perform the request on the target image.
        let request = VNGenerateOpticalFlowRequest(targetedCGImage: source, options: [:])
        request.computationAccuracy = quality == .quality ? .high : .medium
        request.outputPixelFormat = kCVPixelFormatType_TwoComponent32Float
        request.keepNetworkOutput = false

        let handler = VNImageRequestHandler(cgImage: target, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first else {
            throw FlowError.opticalFlowUnavailable
        }
        return observation.pixelBuffer
    }

    private func makeTexture(from image: CGImage) throws -> MTLTexture {
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: false,
            .origin: MTKTextureLoader.Origin.topLeft.rawValue,
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue)
        ]
        return try textureLoader.newTexture(cgImage: image, options: options)
    }

    private func texture(from pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            textureCache,
            pixelBuffer,
            nil,
            pixelFormat,
            width,
            height,
            0,
            &cvTexture
        )
        guard status == kCVReturnSuccess,
              let cvTexture,
              let texture = CVMetalTextureGetTexture(cvTexture) else {
            return nil
        }
        return texture
    }
}
