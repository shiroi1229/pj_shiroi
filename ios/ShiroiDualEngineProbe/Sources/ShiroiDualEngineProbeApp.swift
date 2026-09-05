import ShiroiMLXBridge
import StableDiffusion
import SwiftUI

@main
struct ShiroiDualEngineProbeApp: App {
    var body: some Scene {
        WindowGroup {
            DualEngineProbeView()
        }
    }
}

struct DualEngineProbeView: View {
    private let mlx = ShiroiMLXCapabilities()
    private let coreMLConfig = StableDiffusionPipeline.Configuration(prompt: "dual engine compile probe")

    var body: some View {
        NavigationStack {
            List {
                Section("Core ML engine") {
                    LabeledContent("Module", value: "Apple StableDiffusion")
                    LabeledContent("Prompt API", value: coreMLConfig.prompt)
                    LabeledContent("Compute", value: "Core ML / GPU / ANE / CPU")
                }

                Section("MLX engine") {
                    LabeledContent("Module", value: "ShiroiMLXBridge → MLXStableDiffusion")
                    LabeledContent("Model", value: mlx.modelID)
                    LabeledContent("Default steps", value: "\(mlx.defaultSteps)")
                    LabeledContent("CFG", value: "\(mlx.defaultCFG)")
                    LabeledContent("Compute", value: "MLX / Metal GPU")
                }
            }
            .navigationTitle("Dual Engine Probe")
        }
    }
}
