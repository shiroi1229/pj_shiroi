import Combine
import Foundation

@MainActor
final class ForgeViewModel: ObservableObject {
    @Published var prompt = "a post-apocalyptic orbital city at dusk, cinematic, subtle camera motion"
    @Published var negativePrompt = "text, watermark, low quality, distorted"
    @Published var duration = 3.0
    @Published var fps = 24
    @Published var quality: GenerationQuality = .balanced
    @Published var motionStrength = 0.26
    @Published var seedText = "1229"

    @Published var status = "Ready"
    @Published var progress = 0.0
    @Published var isBusy = false
    @Published var modelInstalled = false
    @Published var outputURL: URL?
    @Published var outputs: [URL] = []
    @Published var errorMessage: String?
    @Published var capabilities = DeviceCapabilities.current()
    @Published var lastMetrics: GenerationMetrics?
    @Published var benchmarkHistory: [BenchmarkRecord] = []
    @Published var benchmarkCSVURL: URL?

    private let engine = VideoForgeEngine()
    private var generationTask: Task<Void, Never>?

    init() {
        Task {
            await refreshModelState()
            await refreshOutputs()
            await refreshBenchmarks()
        }
    }

    func refreshDeviceState() {
        capabilities = DeviceCapabilities.current()
    }

    func refreshModelState() async {
        modelInstalled = await ModelManager.shared.installedModelDirectory() != nil
    }

    func refreshOutputs() async {
        do {
            outputs = try await OutputStore.shared.listOutputs()
            if outputURL == nil {
                outputURL = outputs.first
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshBenchmarks() async {
        do {
            benchmarkHistory = try await BenchmarkStore.shared.load()
        } catch {
            errorMessage = error.localizedDescription
        }
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
                status = "Model installed on this iPad"
                progress = 1
            } catch {
                errorMessage = error.localizedDescription
                status = "Model install failed"
            }
            isBusy = false
        }
    }

    func generate() {
        guard !isBusy, modelInstalled else { return }
        refreshDeviceState()

        isBusy = true
        progress = 0
        errorMessage = nil
        lastMetrics = nil
        status = "Starting on-device generation"

        let safeSeed = UInt32(seedText) ?? 1229
        let profile = capabilities.profile(for: quality)
        let request = GenerationRequest(
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            negativePrompt: negativePrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            duration: duration,
            fps: fps,
            width: 512,
            height: 512,
            seed: safeSeed,
            quality: quality,
            motionStrength: Float(motionStrength),
            bitrate: profile.bitrate
        )
        let capabilities = capabilities

        generationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isBusy = false
                self.generationTask = nil
            }

            do {
                let result = try await self.engine.generate(
                    request: request,
                    capabilities: capabilities
                ) { [weak self] value, message in
                    Task { @MainActor in
                        self?.progress = value
                        self?.status = message
                    }
                }

                self.outputURL = result.url
                self.lastMetrics = result.metrics
                self.progress = 1
                self.status = String(
                    format: "Finished locally • %.1f s total • %.1f MB",
                    result.metrics.totalSeconds,
                    result.metrics.outputMegabytes
                )
                self.refreshDeviceState()
                await self.refreshOutputs()
                do {
                    self.benchmarkHistory = try await BenchmarkStore.shared.append(result.metrics)
                    self.benchmarkCSVURL = nil
                } catch {
                    self.errorMessage = "Video completed, but benchmark history could not be saved: \(error.localizedDescription)"
                }
            } catch is CancellationError {
                self.status = "Generation cancelled"
                self.progress = 0
            } catch {
                self.errorMessage = error.localizedDescription
                self.status = "Generation failed"
            }
        }
    }

    func cancelGeneration() {
        guard isBusy else { return }
        status = "Cancelling…"
        generationTask?.cancel()
    }

    func selectOutput(_ url: URL) {
        outputURL = url
    }

    func deleteOutput(_ url: URL) {
        Task {
            do {
                try await OutputStore.shared.delete(url)
                if outputURL == url { outputURL = nil }
                await refreshOutputs()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func prepareBenchmarkCSV() {
        Task {
            do {
                benchmarkCSVURL = try await BenchmarkStore.shared.exportCSV()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func clearBenchmarkHistory() {
        Task {
            do {
                try await BenchmarkStore.shared.clear()
                benchmarkHistory = []
                benchmarkCSVURL = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
