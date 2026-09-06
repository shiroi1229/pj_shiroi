import AVFoundation
import Foundation

/// Validate the actual recording container and video samples, not a file's name.
@main
enum CaptureRecordingCheck {
    static func main() async throws {
        guard CommandLine.arguments.count == 3 else { throw CheckError.invalid }
        let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 3, duration < 480,
              let track = try await asset.loadTracks(withMediaType: .video).first else { throw CheckError.invalid }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard reader.canAdd(output) else { throw CheckError.invalid }
        reader.add(output)
        guard reader.startReading() else { throw CheckError.invalid }
        var count = 0
        while let buffer = output.copyNextSampleBuffer() {
            guard CMSampleBufferGetNumSamples(buffer) > 0 else { throw CheckError.invalid }
            count += CMSampleBufferGetNumSamples(buffer)
        }
        guard reader.status == .completed, count > 12 else { throw CheckError.invalid }
        let report: [String: Any] = ["container_and_samples": "passed", "samples": count,
            "duration_seconds": duration, "full_pixel_decode": "not_tested_here"]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
        print("PASS actual screen recording: \(count) samples, \(duration)s")
    }
    enum CheckError: Error { case invalid }
}
