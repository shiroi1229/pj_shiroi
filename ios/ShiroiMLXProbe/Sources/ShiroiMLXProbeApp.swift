import Foundation
import MLXStableDiffusion
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
    private let mlxConfiguration = StableDiffusionConfiguration.presetSDXLTurbo

    var body: some View {
        NavigationStack {
            List {
                Section("Coexistence probe") {
                    LabeledContent("Apple module", value: String(describing: StableDiffusionPipeline.self))
                    LabeledContent("MLX module", value: mlxConfiguration.id)
                    Label("Apple Core ML StableDiffusion linked", systemImage: "checkmark.circle")
                    Label("Renamed MLXStableDiffusion linked", systemImage: "checkmark.circle")
                }

                Section("MLX / Metal GPU") {
                    let parameters = mlxConfiguration.defaultParameters()
                    LabeledContent("Model", value: mlxConfiguration.id)
                    LabeledContent("Default steps", value: "\(parameters.steps)")
                    LabeledContent("CFG", value: String(format: "%.1f", parameters.cfgWeight))
                    LabeledContent("Target", value: "iPadOS 18+")
                    Label("Text-to-image API available", systemImage: "sparkles")
                    Label("Image-to-image API available", systemImage: "photo.on.rectangle")
                }
            }
            .navigationTitle("Shiroi Dual Engine Probe")
        }
    }
}
