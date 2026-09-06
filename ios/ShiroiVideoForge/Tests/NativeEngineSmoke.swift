import Foundation
import Metal

@main
enum NativeEngineSmoke {
    static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard MTLCreateSystemDefaultDevice() != nil else {
            let report = ["status": "not_tested", "reason": "CI host exposes no Metal device", "host": "macOS CI, not user iPad"]
            try JSONSerialization.data(withJSONObject: report, options: .prettyPrinted)
                .write(to: directory.appendingPathComponent("diagnostic.json"))
            print("NOT TESTED: CI has no Metal device. Physical iPad gate remains open.")
            return
        }
        let result = try await NativeDiagnostics().run(directory: directory)
        print("PASS Metal computed \(result.report.computeElements) correct values")
        print("PASS HEVC video decoded \(result.report.decodedFrames) frames, \(result.report.durationSeconds)s")
        print("macOS diagnostic only. AI inference and physical iPad performance were NOT tested.")
    }
}
