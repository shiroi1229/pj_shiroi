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
        case metalUnavailable, pixelBufferUnavailable, noKeyframes
        case writerFailed(String)
        var errorDescription: String? {
            switch self {
            case .metalUnavailable: return "Metal GPU is unavailable."
            case .pixelBufferUnavailable: return "Could not allocate a video pixel buffer."
            case .noKeyframes: return "No generated keyframes are available to encode."
            case .writerFailed(let message): return message
            }
        }
    }

    func compose(
        keyframes: [CGImage], request: GenerationRequest, capabilities: DeviceCapabilities,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> CompositionResult {
        let totalFrames = try request.validatedFrameCount()
        guard !keyframes.isEmpty else { throw ComposerError.noKeyframes }
        try Task.checkCancellation()
        guard let device = MTLCreateSystemDefaultDevice() else { throw ComposerError.metalUnavailable }
        let context = CIContext(mtlDevice: device, options: [.cacheIntermediates: true, .priorityRequestLow: false])
        defer { context.clearCaches() }

        var flowInterpolator: OpticalFlowInterpolator?
        var flowSegments: [OpticalFlowSegment] = []
        var fallbackTriggered = false
        if request.temporalMode == .opticalFlow, keyframes.count > 1 {
            progress(0.01, "Vision optical flow • preparing motion fields")
            do {
                let interpolator = try OpticalFlowInterpolator(device: device)
                flowSegments = try interpolator.prepare(keyframes: keyframes, quality: request.quality)
                if flowSegments.count == keyframes.count - 1 { flowInterpolator = interpolator }
                else { flowSegments = []; fallbackTriggered = true }
            } catch is CancellationError { throw CancellationError() }
            catch {
                flowSegments = []
                fallbackTriggered = true
                progress(0.02, "Vision flow unavailable • falling back to Metal blend")
            }
        }

        let output = FileManager.default.temporaryDirectory.appending(path: "ShiroiVideoForge-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: output, fileType: .mov)
        var completed = false
        defer {
            if !completed {
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: output)
            }
        }
        let bitrate = max(request.bitrate, capabilities.profile(for: request.quality).bitrate)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: request.width, AVVideoHeightKey: request.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate, AVVideoExpectedSourceFrameRateKey: request.fps,
                AVVideoMaxKeyFrameIntervalKey: request.fps
            ]
        ]
        guard writer.canApply(outputSettings: settings, forMediaType: .video) else {
            throw ComposerError.writerFailed("HEVC export with these settings is not supported on this device.")
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: request.width, kCVPixelBufferHeightKey as String: request.height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)
        guard writer.canAdd(input) else { throw ComposerError.writerFailed("Video writer rejected its input.") }
        writer.add(input)
        guard writer.startWriting() else { throw ComposerError.writerFailed(writer.error?.localizedDescription ?? "Could not start video writer.") }
        writer.startSession(atSourceTime: .zero)

        let source = keyframes.map { CIImage(cgImage: $0) }
        let extent = CGRect(x: 0, y: 0, width: request.width, height: request.height)
        var opticalFlowHealthy = flowInterpolator != nil
        var flowRenderedFrames = 0

        for frame in 0..<totalFrames {
            try Task.checkCancellation()
            let deadline = ProcessInfo.processInfo.systemUptime + 15
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                guard writer.status == .writing else {
                    throw ComposerError.writerFailed(writer.error?.localizedDescription ?? "Video writer stopped while waiting for a frame.")
                }
                guard ProcessInfo.processInfo.systemUptime < deadline else {
                    throw ComposerError.writerFailed("Video encoder did not accept a frame for 15 seconds. Try a shorter clip.")
                }
                try await Task.sleep(for: .milliseconds(2))
            }
            try Task.checkCancellation()
            let normalized = Double(frame) / Double(totalFrames - 1)
            let position = normalized * Double(source.count - 1)
            let a = min(Int(floor(position)), source.count - 1)
            let b = min(a + 1, source.count - 1)
            let mix = position - floor(position)
            guard let pool = adaptor.pixelBufferPool else { throw ComposerError.pixelBufferUnavailable }
            var buffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard status == kCVReturnSuccess, let buffer else { throw ComposerError.pixelBufferUnavailable }

            var renderedWithFlow = false
            if opticalFlowHealthy, let flowInterpolator, a != b, a < flowSegments.count {
                do {
                    try flowInterpolator.render(segment: flowSegments[a], progress: Float(mix), into: buffer)
                    renderedWithFlow = true
                    flowRenderedFrames += 1
                } catch is CancellationError { throw CancellationError() }
                catch {
                    opticalFlowHealthy = false
                    fallbackTriggered = true
                    progress(Double(frame) / Double(totalFrames), "Vision flow fallback • continuing with Metal blend")
                }
            }
            if !renderedWithFlow {
                // Reclaim per-frame Objective-C objects without evicting reusable GPU caches.
                autoreleasepool {
                    let imageA = animatedFit(source[a], into: extent, globalProgress: normalized, direction: 1)
                    let imageB = animatedFit(source[b], into: extent, globalProgress: normalized, direction: -1)
                    let blended = imageA.applyingFilter("CIDissolveTransition", parameters: [
                        kCIInputTargetImageKey: imageB, kCIInputTimeKey: mix
                    ]).cropped(to: extent)
                    context.render(blended, to: buffer, bounds: extent, colorSpace: CGColorSpaceCreateDeviceRGB())
                }
            }
            let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(request.fps))
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw ComposerError.writerFailed(writer.error?.localizedDescription ?? "Failed while encoding video.")
            }
            let stage = renderedWithFlow ? "Vision Flow + Metal + HEVC" : "Metal compose + HEVC"
            progress(Double(frame + 1) / Double(totalFrames), "\(stage) • \(frame + 1)/\(totalFrames)")
        }

        try Task.checkCancellation()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(totalFrames), timescale: CMTimeScale(request.fps)))
        input.markAsFinished()
        await withTaskCancellationHandler {
            await writer.finishWriting()
        } onCancel: {
            writer.cancelWriting()
        }
        try Task.checkCancellation()
        guard writer.status == .completed else {
            throw ComposerError.writerFailed(writer.error?.localizedDescription ?? "Video encoding did not complete.")
        }
        let temporalPath: TemporalExecutionPath
        if request.temporalMode == .opticalFlow, fallbackTriggered { temporalPath = .visionFlowFallback }
        else if flowRenderedFrames > 0 { temporalPath = .visionFlow }
        else { temporalPath = .metalBlend }
        completed = true
        return CompositionResult(url: output, temporalPath: temporalPath)
    }

    private func animatedFit(_ image: CIImage, into target: CGRect, globalProgress: Double, direction: CGFloat) -> CIImage {
        let baseScale = max(target.width / image.extent.width, target.height / image.extent.height)
        let scale = baseScale * (1.0 + CGFloat(0.035 * sin(globalProgress * .pi)))
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let pan = direction * target.width * 0.018 * CGFloat(globalProgress - 0.5)
        let dx = target.midX - scaled.extent.midX + pan
        let dy = target.midY - scaled.extent.midY
        // Clamp finite source edges before panning; otherwise opaque frames gain black borders.
        return scaled.clampedToExtent()
            .transformed(by: CGAffineTransform(translationX: dx, y: dy)).cropped(to: target)
    }
}
