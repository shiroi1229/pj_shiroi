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
    @Published var temporalMode: TemporalMode = .dissolve
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
    private var operationID: UUID?
    private var acceptsProgress = false

    init() {
        Task { await refreshModelState(); await refreshOutputs(); await refreshBenchmarks() }
    }
    func refreshDeviceState() { capabilities = DeviceCapabilities.current() }
    func refreshModelState() async { modelInstalled = await ModelManager.shared.installedModelDirectory() != nil }
    func refreshOutputs() async {
        do {
            outputs = try await OutputStore.shared.listOutputs()
            if outputURL == nil { outputURL = outputs.first }
        } catch { errorMessage = error.localizedDescription }
    }
    func refreshBenchmarks() async {
        do { benchmarkHistory = try await BenchmarkStore.shared.load() }
        catch { errorMessage = error.localizedDescription }
    }
    private func begin(_ message: String) -> UUID {
        let id = UUID(); operationID = id; acceptsProgress = true
        isBusy = true; progress = 0; errorMessage = nil; status = message
        return id
    }
    private func end(_ id: UUID) {
        guard operationID == id else { return }
        isBusy = false; generationTask = nil; operationID = nil; acceptsProgress = false
    }
    private func callback(for id: UUID) -> @Sendable (Double, String) -> Void {
        { [weak self] value, message in
            Task { @MainActor in
                guard let self, self.operationID == id, self.isBusy, self.acceptsProgress,
                      self.generationTask?.isCancelled != true else { return }
                self.progress = min(max(value, 0), 1)
                self.status = message
            }
        }
    }
    func installModel() {
        guard !isBusy else { return }
        let id = begin("Preparing model download…")
        let update = callback(for: id)
        generationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.end(id) }
            do {
                _ = try await ModelManager.shared.installBaseModel(progress: update)
                try Task.checkCancellation()
                self.acceptsProgress = false
                self.modelInstalled = true; self.progress = 1
                self.status = "Model installed on this iPad"
            } catch {
                self.acceptsProgress = false
                if Task.isCancelled || error is CancellationError {
                    self.status = "Installation paused. Tap Install to resume when supported."
                } else {
                    self.errorMessage = error.localizedDescription
                    self.status = "Install interrupted. Tap Install to retry."
                }
                await self.refreshModelState()
            }
        }
    }
    func generate() {
        guard !isBusy, modelInstalled else { return }
        refreshDeviceState()
        let profile = capabilities.profile(for: quality)
        let request = GenerationRequest(prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            negativePrompt: negativePrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            duration: duration, fps: fps, width: 512, height: 512,
            seed: UInt32(seedText) ?? 1229, quality: quality,
            motionStrength: Float(motionStrength), bitrate: profile.bitrate, temporalMode: temporalMode)
        do { try request.validatedFrameCount() }
        catch { errorMessage = error.localizedDescription; return }
        let id = begin("Starting on-device generation")
        lastMetrics = nil
        let update = callback(for: id); let capabilities = capabilities
        generationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.end(id) }
            do {
                let result = try await self.engine.generate(request: request, capabilities: capabilities, progress: update)
                self.acceptsProgress = false
                self.outputURL = result.url; self.lastMetrics = result.metrics; self.progress = 1
                self.status = String(format: "Finished locally • %.1f s total • %.1f MB", result.metrics.totalSeconds, result.metrics.outputMegabytes)
                self.refreshDeviceState()
                await self.refreshOutputs()
                do {
                    self.benchmarkHistory = try await BenchmarkStore.shared.append(result.metrics)
                    self.benchmarkCSVURL = nil
                } catch { self.errorMessage = "Video saved; benchmark log failed: \(error.localizedDescription)" }
            } catch {
                self.acceptsProgress = false
                if Task.isCancelled || error is CancellationError {
                    self.status = "Generation cancelled"; self.progress = 0
                } else { self.errorMessage = error.localizedDescription; self.status = "Generation failed" }
            }
        }
    }
    /// Also cancels installation; its URLSession task preserves resumable state.
    func cancelGeneration() {
        guard isBusy else { return }
        generationTask?.cancel(); status = "Cancelling…"
    }
    func selectOutput(_ url: URL) { outputURL = url }
    func deleteOutput(_ url: URL) {
        Task {
            do {
                try await OutputStore.shared.delete(url)
                if outputURL == url { outputURL = nil }
                await refreshOutputs()
            } catch { errorMessage = error.localizedDescription }
        }
    }
    func prepareBenchmarkCSV() {
        Task {
            do { benchmarkCSVURL = try await BenchmarkStore.shared.exportCSV() }
            catch { errorMessage = error.localizedDescription }
        }
    }
    func clearBenchmarkHistory() {
        Task {
            do { try await BenchmarkStore.shared.clear(); benchmarkHistory = []; benchmarkCSVURL = nil }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
