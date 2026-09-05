import Combine
import Foundation

@MainActor
final class ForgeViewModel: ObservableObject {
    @Published var prompt = "a post-apocalyptic orbital city at dusk, cinematic, subtle camera motion"
    @Published var negativePrompt = "text, watermark, low quality, distorted"
    @Published var status = "Ready"
    @Published var progress = 0.0
    @Published var isBusy = false
    @Published var modelInstalled = false
    @Published var outputURL: URL?
    @Published var errorMessage: String?

    let capabilities = DeviceCapabilities.current()
    private let engine = VideoForgeEngine()

    init() {
        Task { await refreshModelState() }
    }

    func refreshModelState() async {
        modelInstalled = await ModelManager.shared.installedModelDirectory() != nil
    }

    func installModel() {
        guard !isBusy else { return }
        isBusy = true
        progress = 0
        status = "Downloading Apple Core ML model (~1.56 GB)…"
        errorMessage = nil

        Task {
            do {
                _ = try await ModelManager.shared.installBaseModel()
                modelInstalled = true
                status = "Model installed on iPad"
                progress = 1
            } catch {
                errorMessage = error.localizedDescription
                status = "Model install failed"
            }
            isBusy = false
        }
    }

    func generate() {
        guard !isBusy else { return }
        isBusy = true
        progress = 0
        outputURL = nil
        errorMessage = nil
        status = "Starting on-device generation"

        let request = GenerationRequest(prompt: prompt, negativePrompt: negativePrompt)
        let capabilities = capabilities
        Task {
            do {
                let url = try await engine.generate(request: request, capabilities: capabilities) { [weak self] value, message in
                    Task { @MainActor in
                        self?.progress = value
                        self?.status = message
                    }
                }
                outputURL = url
                progress = 1
                status = "Finished • generated entirely on this iPad"
            } catch {
                errorMessage = error.localizedDescription
                status = "Generation failed"
            }
            isBusy = false
        }
    }
}
