import CoreML
import Foundation

@main
enum ModelLoadProbe {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else { fatalError("Expected resource directory and report path") }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        guard ModelManifest.validateResources(at: root) else { throw ProbeError.invalidLayout }
        var models: [[String: Any]] = []
        for name in ModelManifest.requiredDirectories {
            let info: [String: Any] = try autoreleasepool {
                let configuration = MLModelConfiguration()
                configuration.computeUnits = .cpuOnly
                let model = try MLModel(contentsOf: root.appendingPathComponent(name), configuration: configuration)
                return ["model": name, "load": "passed", "inputs": model.modelDescription.inputDescriptionsByName.keys.sorted(),
                        "outputs": model.modelDescription.outputDescriptionsByName.keys.sorted()]
            }
            models.append(info)
            print("PASS Core ML CPU load: \(name)")
        }
        let result: [String: Any] = ["host": "macOS CI, not iPad", "models": models,
            "inference": "not_tested", "iPadGPU": "not_tested", "signed_delivery": "not_tested"]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
    }
    enum ProbeError: Error { case invalidLayout }
}
