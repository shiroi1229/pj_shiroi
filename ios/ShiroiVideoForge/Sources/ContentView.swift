import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: ForgeViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hardwareCard
                    promptCard
                    modelCard
                    generationCard
                }
                .frame(maxWidth: 980, alignment: .leading)
                .padding(24)
            }
            .navigationTitle("Shiroi Video Forge")
        }
    }

    private var hardwareCard: some View {
        GroupBox("This iPad") {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                GridRow { Text("GPU").foregroundStyle(.secondary); Text(model.capabilities.gpuName) }
                GridRow { Text("CPU cores").foregroundStyle(.secondary); Text("\(model.capabilities.cpuCores)") }
                GridRow { Text("RAM").foregroundStyle(.secondary); Text(String(format: "%.1f GB • %@", model.capabilities.memoryGB, model.capabilities.memoryClass.rawValue)) }
                GridRow { Text("AI path").foregroundStyle(.secondary); Text("Core ML → Neural Engine / CPU") }
                GridRow { Text("Video path").foregroundStyle(.secondary); Text("Metal GPU → HEVC media engine") }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        }
    }

    private var promptCard: some View {
        GroupBox("Video prompt") {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $model.prompt)
                    .frame(minHeight: 110)
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                TextField("Negative prompt", text: $model.negativePrompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.top, 6)
        }
    }

    private var modelCard: some View {
        GroupBox("On-device model") {
            HStack(spacing: 14) {
                Image(systemName: model.modelInstalled ? "checkmark.seal.fill" : "arrow.down.circle")
                    .font(.title2)
                VStack(alignment: .leading) {
                    Text(model.modelInstalled ? "Core ML model installed" : "Model download required")
                        .font(.headline)
                    Text("Apple/Hugging Face 6-bit Stable Diffusion 1.5 Core ML • about 1.56 GB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !model.modelInstalled {
                    Button("Install") { model.installModel() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isBusy)
                }
            }
            .padding(.top, 6)
        }
    }

    private var generationCard: some View {
        GroupBox("On-device generation") {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    model.generate()
                } label: {
                    Label("Generate 3-second video on this iPad", systemImage: "sparkles.tv")
                        .frame(maxWidth: 420)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isBusy || !model.modelInstalled || model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if model.isBusy || model.progress > 0 {
                    ProgressView(value: model.progress)
                    Text(model.status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let error = model.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                if let output = model.outputURL {
                    ShareLink(item: output) {
                        Label("Share generated video", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .padding(.top, 6)
        }
    }
}
