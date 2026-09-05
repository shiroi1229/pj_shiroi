import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import Metal

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
    ) async throws -> URL {
        guard let device = MTLCreateSystemDefaultDevice() else { throw ComposerError.metalUnavailable }
        let context = CIContext(mtlDevice: device, options: [
            .cacheIntermediates: true,
            .priorityRequestLow: false
        ])

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

            let imageA = animatedFit(source[a], into: extent, globalProgress: normalized, direction: 1)
            let imageB = animatedFit(source[b], into: extent, globalProgress: normalized, direction: -1)
            let blended = imageA.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: imageB,
                kCIInputTimeKey: mix
            ]).cropped(to: extent)

            guard let pool = adaptor.pixelBufferPool else { throw ComposerError.pixelBufferUnavailable }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw ComposerError.pixelBufferUnavailable }

            context.render(blended, to: buffer, bounds: extent, colorSpace: CGColorSpaceCreateDeviceRGB())
            let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(request.fps))
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw ComposerError.writerFailed(writer.error?.localizedDescription ?? "Failed while encoding video.")
            }

            if frame.isMultiple(of: 12) {
                context.clearCaches()
            }
            progress(Double(frame + 1) / Double(totalFrames), "Metal compose + HEVC • \(frame + 1)/\(totalFrames)")
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw ComposerError.writerFailed(writer.error?.localizedDescription ?? "Video encoding did not complete.")
        }
        return output
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
