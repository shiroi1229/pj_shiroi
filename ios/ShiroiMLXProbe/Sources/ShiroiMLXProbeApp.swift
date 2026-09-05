import StableDiffusion
import SwiftUI

@main
struct ShiroiMLXProbeApp: App {
    var body: some Scene {
        WindowGroup {
            MLXProbeView()
        }
    }
}

struct MLXProbeView: View {
    private let configuration = StableDiffusionConfiguration.presetSDXLTurbo

    var body: some View {
        NavigationStack {
            List {
                Section("MLX Swift") {
                    LabeledContent("Model", value: configuration.id)
                    LabeledContent("Backend", value: "MLX / Metal GPU")
                    LabeledContent("Target", value: "iPadOS 18+")
                }

                Section("SDXL Turbo API") {
                    let parameters = configuration.defaultParameters()
                    LabeledContent("Default steps", value: "\(parameters.steps)")
                    LabeledContent("CFG", value: String(format: "%.1f", parameters.cfgWeight))
                    Label("Text-to-image API linked", systemImage: "checkmark.circle")
                    Label("Image-to-image API linked", systemImage: "checkmark.circle")
                }
            }
            .navigationTitle("Shiroi MLX Probe")
        }
    }
}
