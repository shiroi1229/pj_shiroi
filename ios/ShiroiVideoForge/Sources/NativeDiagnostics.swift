import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import Metal

struct NativeDiagnosticReport: Codable, Sendable {
    let host: String
    let gpu: String
    let cpuCores: Int
    let physicalMemoryBytes: UInt64
    let computeElements: Int
    let computeCorrect: Bool
    let gpuCommandSeconds: Double?
    let exportSeconds: Double
    let decodedFrames: Int
    let durationSeconds: Double
    let outputBytes: Int
    let aiInferenceTested: Bool
}

struct NativeDiagnosticResult: Sendable {
    let report: NativeDiagnosticReport
    let videoURL: URL
    let reportURL: URL
}

/// Tests actual Metal computation and the production video compositor.
/// Synthetic diagnostic frames are NOT AI generated content.
actor NativeDiagnostics {
    func run(directory: URL) async throws -> NativeDiagnosticResult {
        try Task.checkCancellation()
        guard let device = MTLCreateSystemDefaultDevice() else { throw DiagnosticError.metalUnavailable }
        let gpuTime = try await checkCompute(device: device)
        try Task.checkCancellation()
        let frames = try [fixture(offset: 0), fixture(offset: 64)]
        let request = GenerationRequest(prompt: "SYNTHETIC DIAGNOSTIC — NO AI INFERENCE", negativePrompt: "",
                                        duration: 1, fps: 12, width: 256, height: 256, quality: .fast)
        let start = ProcessInfo.processInfo.systemUptime
        let result = try await MetalVideoComposer().compose(keyframes: frames, request: request,
            capabilities: DeviceCapabilities.current(), progress: { _, _ in })
        defer { try? FileManager.default.removeItem(at: result.url) }
        let exportSeconds = ProcessInfo.processInfo.systemUptime - start
        let asset = AVURLAsset(url: result.url)
        let duration = try await asset.load(.duration).seconds
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw DiagnosticError.invalidVideo }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        guard reader.canAdd(output) else { throw DiagnosticError.invalidVideo }
        reader.add(output)
        guard reader.startReading() else { throw DiagnosticError.invalidVideo }
        var count = 0
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let pixel = CMSampleBufferGetImageBuffer(sample),
                  CVPixelBufferGetWidth(pixel) == 256, CVPixelBufferGetHeight(pixel) == 256 else {
                reader.cancelReading(); throw DiagnosticError.invalidVideo
            }
            count += 1
        }
        guard reader.status == .completed, count == 12, abs(duration - 1) < 0.1 else {
            throw DiagnosticError.invalidVideo
        }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let video = directory.appendingPathComponent("diagnostic.mov")
        if fm.fileExists(atPath: video.path) { try fm.removeItem(at: video) }
        try fm.moveItem(at: result.url, to: video)
        #if targetEnvironment(simulator)
        let host = "iOS Simulator — NOT physical iPad"
        #elseif os(iOS)
        let host = "physical iOS/iPadOS device"
        #else
        let host = "macOS host — NOT iPad"
        #endif
        let report = NativeDiagnosticReport(host: host, gpu: device.name,
            cpuCores: ProcessInfo.processInfo.processorCount,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            computeElements: 1_048_576, computeCorrect: true, gpuCommandSeconds: gpuTime,
            exportSeconds: exportSeconds, decodedFrames: count, durationSeconds: duration,
            outputBytes: (try video.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0,
            aiInferenceTested: false)
        let reportURL = directory.appendingPathComponent("diagnostic.json")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: reportURL, options: .atomic)
        return NativeDiagnosticResult(report: report, videoURL: video, reportURL: reportURL)
    }

    private func checkCompute(device: MTLDevice) async throws -> Double? {
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void diagnosticAffine(device const float* input [[buffer(0)]],
                                     device float* output [[buffer(1)]],
                                     uint i [[thread_position_in_grid]]) {
            if (i < 1048576) output[i] = input[i] * 2.0f + 1.0f;
        }
        """
        let library = try device.makeLibrary(source: source, options: nil)
        guard let function = library.makeFunction(name: "diagnosticAffine"),
              let queue = device.makeCommandQueue(), let command = queue.makeCommandBuffer(),
              let input = device.makeBuffer(length: 1_048_576 * 4, options: .storageModeShared),
              let output = device.makeBuffer(length: 1_048_576 * 4, options: .storageModeShared),
              let encoder = command.makeComputeCommandEncoder() else { throw DiagnosticError.computeFailed }
        let pipeline = try device.makeComputePipelineState(function: function)
        let p = input.contents().bindMemory(to: Float.self, capacity: 1_048_576)
        for i in 0..<1_048_576 { p[i] = Float(i % 1024) / 1024 }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(input, offset: 0, index: 0); encoder.setBuffer(output, offset: 0, index: 1)
        encoder.dispatchThreads(MTLSize(width: 1_048_576, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: min(256, pipeline.maxTotalThreadsPerThreadgroup), height: 1, depth: 1))
        encoder.endEncoding()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            command.addCompletedHandler { _ in continuation.resume() }
            command.commit()
        }
        try Task.checkCancellation()
        guard command.status == .completed else { throw DiagnosticError.computeFailed }
        let q = output.contents().bindMemory(to: Float.self, capacity: 1_048_576)
        for i in 0..<1_048_576 {
            guard q[i] == p[i] * 2 + 1 else { throw DiagnosticError.computeFailed }
        }
        let seconds = command.gpuEndTime - command.gpuStartTime
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }

    private func fixture(offset: CGFloat) throws -> CGImage {
        guard let context = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw DiagnosticError.invalidVideo
        }
        context.setFillColor(CGColor(red: 0.12, green: 0.20, blue: 0.35, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
        context.setFillColor(CGColor(red: 0.8, green: 0.9, blue: 1, alpha: 1))
        context.fill(CGRect(x: 40 + offset, y: 80, width: 64, height: 96))
        guard let image = context.makeImage() else { throw DiagnosticError.invalidVideo }
        return image
    }

    enum DiagnosticError: LocalizedError {
        case metalUnavailable, computeFailed, invalidVideo
        var errorDescription: String? {
            switch self {
            case .metalUnavailable: return "This host exposes no Metal device. GPU execution was not tested."
            case .computeFailed: return "Metal computation failed or differed from the CPU reference."
            case .invalidVideo: return "Video export failed frame-count, size, decode or duration validation."
            }
        }
    }
}
