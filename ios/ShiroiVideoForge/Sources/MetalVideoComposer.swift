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

    func compose(keyframes: [CGImage], request: GenerationRequest, progress: @escaping @Sendable (Double, String) -> Void) async throws -> URL {
        guard let device = MTLCreateSystemDefaultDevice() else { throw ComposerError.metalUnavailable }
        let context = CIContext(mtlDevice: device, options: [.cacheIntermediates: true])

        let output = FileManager.default.temporaryDirectory.appending(path: "ShiroiVideoForge-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: output, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: request.width,
            AVVideoHeightKey: request.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoExpectedSourceFrameRateKey: request.fps
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: request.width,
            kCVPixelBufferHeightKey as String: request.height,
            kCVPixelBufferMetalCompatibilityKey as String: true
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
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(2))
            }

            let normalized = Double(frame) / Double(totalFrames - 1)
            let position = normalized * Double(max(source.count - 1, 1))
            let a = min(Int(floor(position)), max(source.count - 1, 0))
            let b = min(a + 1, max(source.count - 1, 0))
            let mix = position - floor(position)

            let imageA = fit(source[a], into: extent)
            let imageB = fit(source[b], into: extent)
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
            progress(Double(frame + 1) / Double(totalFrames), "Metal temporal compose • \(frame + 1)/\(totalFrames)")
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw ComposerError.writerFailed(writer.error?.localizedDescription ?? "Video encoding did not complete.")
        }
        return output
    }

    private func fit(_ image: CIImage, into target: CGRect) -> CIImage {
        let sx = target.width / image.extent.width
        let sy = target.height / image.extent.height
        let scale = max(sx, sy)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let dx = target.midX - scaled.extent.midX
        let dy = target.midY - scaled.extent.midY
        return scaled.transformed(by: CGAffineTransform(translationX: dx, y: dy)).cropped(to: target)
    }
}
