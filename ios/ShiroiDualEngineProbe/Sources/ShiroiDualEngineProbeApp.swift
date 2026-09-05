import ShiroiMLXRuntime
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
    private let mlx = ShiroiMLXRuntimeInfo()
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
                    LabeledContent("Module", value: "ShiroiMLXRuntime.framework")
                    LabeledContent("Model", value: mlx.modelID)
                    LabeledContent("Default steps", value: "\(mlx.defaultSteps)")
                    LabeledContent("CFG", value: "\(mlx.defaultCFG)")
                    LabeledContent("Compute", value: mlx.backend)
                }
            }
            .navigationTitle("Dual Engine Probe")
        }
    }
}
