import AVKit
import Combine
import Foundation

/// Owns tasks, playback and history across SwiftUI redraws. Progress is accepted
/// only from the active operation; cancellation never erases a previous result.
@MainActor
final class VisiblePOCViewModel: ObservableObject {
    @Published var result: VisiblePOCResult?
    @Published var player: AVPlayer?
    @Published var history: [VisiblePOCResult] = []
    @Published var profile: VisiblePOCProfile = .preview
    @Published var running = false
    @Published var progress = 0.0
    @Published var stage = "生成ボタンでGPUレンダリングを開始"
    @Published var error: String?
    private let store = VisiblePOCStore.shared
    private let idleOwner = UUID()
    private var operation: UUID?
    private var task: Task<Void, Never>?

    func refresh() async {
        do {
            history = try await store.list()
            if result == nil, let first = history.first { select(first) }
        } catch { self.error = error.localizedDescription }
    }
    func select(_ item: VisiblePOCResult) {
        guard !running else { return }
        player?.pause()
        result = item
        player = AVPlayer(url: item.movie)
        progress = 1
        stage = "保存済みの動画を選択したよ"
    }
    func replay() {
        player?.seek(to: .zero)
        player?.play()
    }
    func stop() { task?.cancel(); player?.pause() }
    func delete(_ item: VisiblePOCResult) async {
        guard !running else { return }
        do {
            if result?.id == item.id { player?.pause(); player = nil; result = nil }
            try await store.delete(item)
            await refresh()
            if result == nil { progress = 0; stage = "削除したよ。次の映像を生成できるよ" }
        } catch { self.error = error.localizedDescription }
    }
    func start(id suppliedID: UUID? = nil) {
        guard !running else { return }
        let id = suppliedID ?? UUID(), chosen = profile
        operation = id; running = true; progress = 0; error = nil
        player?.pause(); stage = "Metalパイプラインを準備中"
        IdleTimerCoordinator.shared.setActive(owner: idleOwner, active: true)
        task = Task { [weak self] in
            guard let self else { return }
            var pending: URL?
            defer {
                self.operation = nil; self.running = false; self.task = nil
                IdleTimerCoordinator.shared.setActive(owner: self.idleOwner, active: false)
            }
            do {
                let directory = try await self.store.stage(id: id)
                pending = directory
                try Task.checkCancellation()
                let generated = try await VisiblePOCRenderer().render(to: directory, profile: chosen) { [weak self] value, message in
                    Task { @MainActor in
                        guard let self, self.operation == id, self.running,
                              self.task?.isCancelled != true else { return }
                        self.progress = max(self.progress, min(value, 1)); self.stage = message
                    }
                }
                try Task.checkCancellation()
                let saved = try await self.store.commit(generated)
                pending = nil
                // Once committed, the result remains accessible even if cancellation raced.
                self.operation = nil
                self.result = saved; self.progress = 1
                self.stage = "保存・全144フレームの読み戻しに成功"
                self.player = AVPlayer(url: saved.movie)
                self.history = try await self.store.list()
                if !Task.isCancelled { self.player?.play() }
            } catch {
                self.operation = nil
                if let pending { try? await self.store.discard(pending) }
                if Task.isCancelled || error is CancellationError { self.stage = "中止したよ。以前の動画は履歴に残っているよ" }
                else { self.error = error.localizedDescription; self.stage = "生成に失敗。以前の動画は保護されているよ" }
            }
        }
    }
}
