import AVFoundation
import CoreImage
import CoreVideo
import Foundation
import Metal

struct VisiblePOCReport: Codable, Sendable {
    let status: String
    let host: String
    let gpu: String
    let width: Int
    let height: Int
    let fps: Int
    let frames: Int
    let decodedFrames: Int
    let durationSeconds: Double
    let renderAndEncodeSeconds: Double
    let gpuCommandSeconds: Double?
    let outputBytes: Int
    let aiInference: Bool
    let source: String
}
struct VisiblePOCResult: Sendable {
    let directory: URL
    let report: VisiblePOCReport
    var movie: URL { directory.appendingPathComponent("poc-video.mov") }
    var poster: URL { directory.appendingPathComponent("poc-poster.png") }
    var json: URL { directory.appendingPathComponent("poc-result.json") }
}

/// Bounded native GPU/encoder POC. No model, network, or external image assets.
/// All writer access stays on this actor. Completion markers follow decode checks.
actor VisiblePOCRenderer {
    static let width = 960, height = 540, fps = 24, frames = 144
    private var activeWriter: AVAssetWriter?
    private var operationID: UUID?
    private func cancelWriter(_ id: UUID) {
        if operationID == id { activeWriter?.cancelWriting() }
    }
    func render(to directory: URL,
                progress: @escaping @Sendable (Double, String) -> Void) async throws -> VisiblePOCResult {
        guard operationID == nil else { throw POCError.failed("A render is already active.") }
        let id = UUID(); operationID = id
        defer { operationID = nil; activeWriter = nil }
        try Task.checkCancellation()
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let function = device.makeDefaultLibrary()?.makeFunction(name: "forgePOCFrame") else {
            throw POCError.failed("Metal device or POC shader unavailable.")
        }
        let pipeline = try await device.makeComputePipelineState(function: function)
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess,
              let cache else { throw POCError.failed("Texture cache unavailable.") }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let movie = directory.appendingPathComponent("poc-video.mov")
        let writer = try AVAssetWriter(outputURL: movie, fileType: .mov)
        activeWriter = writer
        var completed = false
        defer {
            if !completed {
                writer.cancelWriting()
                try? fm.removeItem(at: movie)
            }
        }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Self.width, AVVideoHeightKey: Self.height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 5_000_000,
                AVVideoExpectedSourceFrameRateKey: Self.fps, AVVideoMaxKeyFrameIntervalKey: Self.fps]
        ]
        guard writer.canApply(outputSettings: settings, forMediaType: .video) else {
            throw POCError.failed("This runtime does not accept HEVC export.")
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Self.width, kCVPixelBufferHeightKey as String: Self.height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        guard writer.canAdd(input) else { throw POCError.failed("Writer input unavailable.") }
        writer.add(input)
        guard writer.startWriting() else { throw POCError.failed(writer.error?.localizedDescription ?? "Writer failed.") }
        writer.startSession(atSourceTime: .zero)
        let context = CIContext(mtlDevice: device)
        defer { context.clearCaches() }
        let started = ProcessInfo.processInfo.systemUptime
        var gpuSeconds = 0.0, gpuTimes = 0
        for frame in 0..<Self.frames {
            try Task.checkCancellation()
            let deadline = ProcessInfo.processInfo.systemUptime + 20
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                guard writer.status == .writing, ProcessInfo.processInfo.systemUptime < deadline else {
                    throw POCError.failed(writer.error?.localizedDescription ?? "Encoder backpressure timed out.")
                }
                try await Task.sleep(for: .milliseconds(5))
            }
            guard let pool = adaptor.pixelBufferPool else { throw POCError.failed("Pixel pool unavailable.") }
            var pixel: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixel) == kCVReturnSuccess,
                  let pixel else { throw POCError.failed("Pixel allocation failed.") }
            var cvTexture: CVMetalTexture?
            guard CVMetalTextureCacheCreateTextureFromImage(nil, cache, pixel, nil, .bgra8Unorm,
                    Self.width, Self.height, 0, &cvTexture) == kCVReturnSuccess,
                  let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture),
                  let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else {
                throw POCError.failed("GPU frame resources unavailable.")
            }
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(texture, index: 0)
            var time = Float(frame) / Float(Self.fps)
            encoder.setBytes(&time, length: MemoryLayout<Float>.size, index: 0)
            let tw = pipeline.threadExecutionWidth
            let th = min(8, max(1, pipeline.maxTotalThreadsPerThreadgroup / tw))
            encoder.dispatchThreads(MTLSize(width: Self.width, height: Self.height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: tw, height: th, depth: 1))
            encoder.endEncoding()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                command.addCompletedHandler { _ in continuation.resume() }
                command.commit()
            }
            withExtendedLifetime(cvTexture) {}
            try Task.checkCancellation()
            guard command.status == .completed else { throw POCError.failed("GPU execution failed.") }
            let measured = command.gpuEndTime - command.gpuStartTime
            if measured.isFinite && measured > 0 { gpuSeconds += measured; gpuTimes += 1 }
            if frame == 0 {
                try context.writePNGRepresentation(of: CIImage(cvPixelBuffer: pixel),
                    to: directory.appendingPathComponent("poc-poster.png"), format: .RGBA8,
                    colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
            }
            guard adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: Int32(Self.fps))) else {
                throw POCError.failed(writer.error?.localizedDescription ?? "Frame append failed.")
            }
            progress(Double(frame + 1) / Double(Self.frames) * 0.95, "GPU → HEVC  \(frame + 1) / \(Self.frames)")
        }
        writer.endSession(atSourceTime: CMTime(value: Int64(Self.frames), timescale: Int32(Self.fps)))
        input.markAsFinished()
        let timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)); await self?.cancelWriter(id) } catch {}
        }
        defer { timeout.cancel() }
        await withTaskCancellationHandler { await writer.finishWriting() }
            onCancel: { Task { await self.cancelWriter(id) } }
        try Task.checkCancellation()
        guard writer.status == .completed else { throw POCError.failed(writer.error?.localizedDescription ?? "Finalization failed.") }
        let renderSeconds = ProcessInfo.processInfo.systemUptime - started
        progress(0.97, "保存した動画を読み戻して検証中")
        let asset = AVURLAsset(url: movie)
        let duration = try await asset.load(.duration).seconds
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw POCError.failed("No video track.") }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        guard reader.canAdd(output) else { throw POCError.failed("Reader unavailable.") }
        reader.add(output)
        guard reader.startReading() else { throw POCError.failed("Reader start failed.") }
        defer { if reader.status == .reading { reader.cancelReading() } }
        var decoded = 0
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let buffer = CMSampleBufferGetImageBuffer(sample),
                  CVPixelBufferGetWidth(buffer) == Self.width, CVPixelBufferGetHeight(buffer) == Self.height else {
                throw POCError.failed("Decoded frame dimensions do not match.")
            }
            decoded += 1
        }
        guard reader.status == .completed, decoded == Self.frames, abs(duration - 6) < 0.05 else {
            throw POCError.failed("Decoded frame count or duration did not match.")
        }
        #if targetEnvironment(simulator)
        let host = "iPad Simulator on macOS; not physical iPad"
        #else
        let host = "physical iPadOS device"
        #endif
        let report = VisiblePOCReport(status: "passed", host: host, gpu: device.name,
            width: Self.width, height: Self.height, fps: Self.fps, frames: Self.frames,
            decodedFrames: decoded, durationSeconds: duration, renderAndEncodeSeconds: renderSeconds,
            gpuCommandSeconds: gpuTimes == Self.frames ? gpuSeconds : nil,
            outputBytes: (try movie.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0,
            aiInference: false, source: "procedural Metal shader; no external assets; non-canon test scene")
        let json = JSONEncoder(); json.outputFormatting = [.prettyPrinted, .sortedKeys]
        try json.encode(report).write(to: directory.appendingPathComponent("poc-result.json"), options: .atomic)
        completed = true
        progress(1, "144フレームの保存・読み戻しに成功")
        return VisiblePOCResult(directory: directory, report: report)
    }
    enum POCError: LocalizedError {
        case failed(String)
        var errorDescription: String? { switch self { case .failed(let message): return message } }
    }
}
