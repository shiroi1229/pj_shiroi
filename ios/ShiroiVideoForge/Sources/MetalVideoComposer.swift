import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import Metal

enum TemporalExecutionPath: String, Sendable {
    case metalBlend = "Metal Blend"
    case visionFlow = "Vision Flow"
    case visionFlowFallback = "Vision Flow → Blend fallback"
}

struct CompositionResult: Sendable {
    let url: URL
    let temporalPath: TemporalExecutionPath
}

actor MetalVideoComposer {
    enum ComposerError: LocalizedError {
        case metalUnavailable
        case writerFailed(String)
        case pixelBufferUnavailable

        var errorDescription: String? {
            switch self {
            case .metalUnavailable: return "Metal GPU is unavailable."
            case .writerFailed(let message): return message
            case .pixelBufferUnavailable: return "Could not allocate a video pixel buffer."
            }
        }
    }

    func compose(
        keyframes: [CGImage],
        request: GenerationRequest,
        capabilities: DeviceCapabilities,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> CompositionResult {
        guard let device = MTLCreateSystemDefaultDevice() else { throw ComposerError.metalUnavailable }
        let context = CIContext(mtlDevice: device, options: [
            .cacheIntermediates: true,
            .priorityRequestLow: false
        ])

        var flowInterpolator: OpticalFlowInterpolator?
        var flowSegments: [OpticalFlowSegment] = []
        var fallbackTriggered = false
        if request.temporalMode == .opticalFlow {
            progress(0.01, "Vision optical flow • preparing motion fields")
            do {
                let interpolator = try OpticalFlowInterpolator(device: device)
                flowSegments = try interpolator.prepare(keyframes: keyframes, quality: request.quality)
                if flowSegments.count == max(keyframes.count - 1, 0) {
                    flowInterpolator = interpolator
                } else {
                    fallbackTriggered = true
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Optical flow is an experimental quality path. Keep generation robust
                // by falling back to the proven Metal/Core Image blend path.
                flowInterpolator = nil
                flowSegments = []
                fallbackTriggered = true
                progress(0.02, "Vision flow unavailable • falling back to Metal blend")
            }
        }

        let output = FileManager.default.temporaryDirectory.appending(path: "ShiroiVideoForge-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: output, fileType: .mov)
        let bitrate = max(request.bitrate, capabilities.profile(for: request.quality).bitrate)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: request.width,
            AVVideoHeightKey: request.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: request.fps,
                AVVideoMaxKeyFrameIntervalKey: request.fps
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: request.width,
            kCVPixelBufferHeightKey as String: request.height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)
        guard writer.canAdd(input) else { throw ComposerError.writerFailed("AVAssetWriter rejected the video input.") }
        writer.add(input)
        guard writer.startWriting() else { throw ComposerError.writerFailed(writer.error?.localizedDescription ?? "Could not start video writer.") }
        writer.startSession(atSourceTime: .zero)

        let totalFrames = max(Int(request.duration * Double(request.fps)), 2)
        let source = keyframes.map { CIImage(cgImage: $0) }
        let extent = CGRect(x: 0, y: 0, width: request.width, height: request.height)
        var opticalFlowHealthy = flowInterpolator != nil
        var flowRenderedFrames = 0

        for frame in 0..<totalFrames {
            if Task.isCancelled {
                writer.cancelWriting()
                throw CancellationError()
            }

            while !input.isReadyForMoreMediaData {
                if Task.isCancelled {
                    writer.cancelWriting()
                    throw CancellationError()
                }
                try await Task.sleep(for: .milliseconds(2))
            }

            let normalized = Double(frame) / Double(totalFrames - 1)
            let position = normalized * Double(max(source.count - 1, 1))
            let a = min(Int(floor(position)), max(source.count - 1, 0))
            let b = min(a + 1, max(source.count - 1, 0))
            let mix = position - floor(position)

            guard let pool = adaptor.pixelBufferPool else { throw ComposerError.pixelBufferUnavailable }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw ComposerError.pixelBufferUnavailable }

            var renderedWithFlow = false
            if opticalFlowHealthy,
               let flowInterpolator,
               a != b,
               a < flowSegments.count {
                do {
                    try flowInterpolator.render(
                        segment: flowSegments[a],
                        progress: Float(mix),
                        into: buffer
                    )
                    renderedWithFlow = true
                    flowRenderedFrames += 1
                } catch {
                    opticalFlowHealthy = false
                    fallbackTriggered = true
                    progress(
                        Double(frame) / Double(totalFrames),
                        "Vision flow runtime fallback • continuing with Metal blend"
                    )
                }
            }

            if !renderedWithFlow {
                let imageA = animatedFit(source[a], into: extent, globalProgress: normalized, direction: 1)
                let imageB = animatedFit(source[b], into: extent, globalProgress: normalized, direction: -1)
                let blended = imageA.applyingFilter("CIDissolveTransition", parameters: [
                    kCIInputTargetImageKey: imageB,
                    kCIInputTimeKey: mix
                ]).cropped(to: extent)
                context.render(blended, to: buffer, bounds: extent, colorSpace: CGColorSpaceCreateDeviceRGB())
            }

            let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(request.fps))
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw ComposerError.writerFailed(writer.error?.localizedDescription ?? "Failed while encoding video.")
            }

            if frame.isMultiple(of: 12) {
                context.clearCaches()
            }
            let stage = renderedWithFlow ? "Vision Flow + Metal + HEVC" : "Metal compose + HEVC"
            progress(Double(frame + 1) / Double(totalFrames), "\(stage) • \(frame + 1)/\(totalFrames)")
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw ComposerError.writerFailed(writer.error?.localizedDescription ?? "Video encoding did not complete.")
        }

        let temporalPath: TemporalExecutionPath
        if request.temporalMode == .opticalFlow {
            if fallbackTriggered {
                temporalPath = .visionFlowFallback
            } else if flowRenderedFrames > 0 {
                temporalPath = .visionFlow
            } else {
                temporalPath = .metalBlend
            }
        } else {
            temporalPath = .metalBlend
        }

        return CompositionResult(url: output, temporalPath: temporalPath)
    }

    private func animatedFit(
        _ image: CIImage,
        into target: CGRect,
        globalProgress: Double,
        direction: CGFloat
    ) -> CIImage {
        let sx = target.width / image.extent.width
        let sy = target.height / image.extent.height
        let baseScale = max(sx, sy)
        let motionScale = 1.0 + CGFloat(0.035 * sin(globalProgress * .pi))
        let scale = baseScale * motionScale
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let travel = target.width * 0.018
        let pan = direction * travel * CGFloat(globalProgress - 0.5)
        let dx = target.midX - scaled.extent.midX + pan
        let dy = target.midY - scaled.extent.midY
        return scaled
            .transformed(by: CGAffineTransform(translationX: dx, y: dy))
            .cropped(to: target)
    }
}
