import AVFoundation
import CoreGraphics
import CoreVideo
import CryptoKit
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

/// Executes the production KeyframeGenerator and MetalVideoComposer without mocks.
/// CPU-only inference on macOS CI is NOT an iPad performance measurement.
@main
enum AIEndToEndProbe {
    static func main() async throws {
        setbuf(stdout, nil)
        guard CommandLine.arguments.count == 3 else { throw Failure.invalidArguments }
        let resources = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
        let generator = KeyframeGenerator(resourceDirectory: resources)
        guard await generator.isReady() else { throw Failure.modelMissing }
        let capabilities = DeviceCapabilities.current()
        let request = GenerationRequest(
            prompt: "a small orange ceramic teapot on a wooden table, soft studio lighting, photographic, detailed",
            negativePrompt: "text, watermark, low quality, distorted", duration: 1, fps: 12,
            width: 512, height: 512, quality: .fast, motionStrength: 0.26,
            temporalMode: .dissolve, computePolicy: .cpuOnly)
        let profile = capabilities.profile(for: request.quality)
        print("HOST: macOS CI, NOT physical iPad. CPU-only inference; \(profile.keyframes) keyframes / \(profile.steps) scheduled steps.")
        let start = ProcessInfo.processInfo.systemUptime
        let images = try await generator.generate(request: request, capabilities: capabilities) { value, stage in
            print(String(format: "%.1f%% %@", value * 100, stage))
        }
        let inferenceSeconds = ProcessInfo.processInfo.systemUptime - start
        guard images.count == profile.keyframes, images.count >= 2 else { throw Failure.missingImages }
        var files: [[String: Any]] = []
        for (index, image) in images.enumerated() {
            guard image.width == 512, image.height == 512 else { throw Failure.invalidImage }
            let url = output.appendingPathComponent("ai-keyframe-\(index + 1).png")
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                throw Failure.invalidImage
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw Failure.invalidImage }
            let data = try Data(contentsOf: url)
            files.append(["file": url.lastPathComponent, "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()])
        }
        print("PASS real text-to-image and image-to-image predictions; \(images.count) PNG keyframes saved")
        guard MTLCreateSystemDefaultDevice() != nil else { throw Failure.metalUnavailable }
        let encodeStart = ProcessInfo.processInfo.systemUptime
        let composed = try await MetalVideoComposer().compose(keyframes: images, request: request,
            capabilities: capabilities, progress: { _, stage in print(stage) })
        defer { try? fm.removeItem(at: composed.url) }
        let exportSeconds = ProcessInfo.processInfo.systemUptime - encodeStart
        let video = output.appendingPathComponent("ai-keyframes-video.mov")
        try fm.copyItem(at: composed.url, to: video)
        let asset = AVURLAsset(url: video)
        let duration = try await asset.load(.duration).seconds
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw Failure.invalidVideo }
        let reader = try AVAssetReader(asset: asset)
        let frames = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        guard reader.canAdd(frames) else { throw Failure.invalidVideo }
        reader.add(frames)
        guard reader.startReading() else { throw Failure.invalidVideo }
        defer { if reader.status == .reading { reader.cancelReading() } }
        var decoded = 0
        while let sample = frames.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let pixel = CMSampleBufferGetImageBuffer(sample),
                  CVPixelBufferGetWidth(pixel) == 512, CVPixelBufferGetHeight(pixel) == 512 else { throw Failure.invalidVideo }
            decoded += 1
        }
        guard reader.status == .completed, decoded == 12, abs(duration - 1) < 0.1 else { throw Failure.invalidVideo }
        let report: [String: Any] = [
            "status": "passed", "host": "macOS CI — NOT physical iPad",
            "source_commit": ProcessInfo.processInfo.environment["GITHUB_SHA"] ?? "local",
            "ai_inference": "real Core ML text-to-image and image-to-image", "compute_policy": request.computePolicy.rawValue,
            "safety_checker_enabled": true, "synthetic_fixture": false,
            "model_revision": ModelManifest.revision, "model_sha256": ModelManifest.archiveSHA256,
            "inference_seconds": inferenceSeconds, "export_seconds": exportSeconds,
            "keyframes": files, "scheduled_steps_per_keyframe": profile.steps,
            "cpu_cores": capabilities.cpuCores, "gpu": capabilities.gpuName,
            "physical_memory_bytes": capabilities.memoryBytes,
            "decoded_frames": decoded, "width": 512, "height": 512, "duration_seconds": duration,
            "pipeline": "AI image keyframes plus interpolation; NOT temporal video diffusion",
            "physical_ipad_tested": false, "signed_delivery": false, "quality_approved": false
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("ai-e2e.json"), options: .atomic)
        print("PASS production Metal/HEVC export and 12-frame decode. NOT an iPad test or quality approval.")
    }
    enum Failure: Error {
        case invalidArguments, modelMissing, missingImages, invalidImage, metalUnavailable, invalidVideo
    }
}
