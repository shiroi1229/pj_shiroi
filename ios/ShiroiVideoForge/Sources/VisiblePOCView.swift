import AVKit
import SwiftUI
import UIKit

/// A usable native proof of concept, not a mockup or a web-rendered preview.
struct VisiblePOCView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var task: Task<Void, Never>?
    @State private var result: VisiblePOCResult?
    @State private var player: AVPlayer?
    @State private var running = false
    @State private var progress = 0.0
    @State private var stage = "生成ボタンでGPUレンダリングを開始"
    @State private var error: String?
    @State private var autoStarted = false
    private let accent = Color(red: 0.37, green: 0.91, blue: 0.86)
    private let surface = Color(red: 0.065, green: 0.095, blue: 0.14)
    private let autoRun = ProcessInfo.processInfo.arguments.contains("--poc-autostart")
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    preview
                    controls
                    metrics
                    scope
                }
                .frame(maxWidth: 1000)
                .padding(.horizontal, 32).padding(.top, 18).padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
            .background(Color(red: 0.025, green: 0.045, blue: 0.075))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Label("SHIROI / VIDEO FORGE", systemImage: "waveform.path")
                        .font(.subheadline.monospaced().weight(.semibold)).foregroundStyle(accent)
                }
                ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { dismiss() }.disabled(running) }
            }
        }
        .preferredColorScheme(.dark).tint(accent)
        .task {
            guard autoRun, !autoStarted else { return }
            autoStarted = true
            do { try await Task.sleep(for: .seconds(3)); start() } catch {}
        }
        .onDisappear { task?.cancel(); player?.pause(); UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { task?.cancel(); player?.pause(); UIApplication.shared.isIdleTimerDisabled = false }
        }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("NATIVE VIDEO ENGINE").font(.caption.monospaced()).tracking(2).foregroundStyle(accent)
                Spacer()
                Text("POC / 01").font(.caption.monospaced()).padding(.horizontal, 12).padding(.vertical, 6)
                    .background(accent.opacity(0.12), in: Capsule()).foregroundStyle(accent)
            }
            Text("GPUで、映像をつくる。").font(.system(size: 38, weight: .bold))
            Text("描画 → 動画保存 → 再生。すべてネイティブコードで。")
                .font(.title3).foregroundStyle(.secondary)
        }
    }
    private var preview: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if let player { VideoPlayer(player: player) }
                else {
                    VStack(spacing: 16) {
                        Image(systemName: running ? "cpu" : "play.rectangle.on.rectangle")
                            .font(.system(size: 42, weight: .light)).foregroundStyle(accent)
                        Text(running ? "GPUがフレームを描画中" : "ORBITAL / PROCEDURAL SCENE")
                            .font(.headline.monospaced()).foregroundStyle(.white.opacity(0.8))
                        Text("外部素材なし・AIモデル不要の技術デモ").font(.subheadline).foregroundStyle(.secondary)
                        if running { ProgressView().tint(accent) }
                    }
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            HStack {
                Label(result == nil ? "RENDER TARGET" : "LOCAL VIDEO", systemImage: "film")
                Spacer()
                Text("960 × 540  /  24 FPS  /  6 SEC")
            }
            .font(.caption.monospaced()).foregroundStyle(.secondary).padding(14).background(surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.08)))
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Button(action: start) {
                    Label(running ? "生成中…" : (result == nil ? "6秒の映像を生成" : "もう一度生成"), systemImage: "bolt.fill")
                        .font(.headline).padding(.horizontal, 16).padding(.vertical, 9)
                }
                .buttonStyle(.borderedProminent).disabled(running).accessibilityIdentifier("poc.generate")
                if running { Button("中止") { task?.cancel() }.buttonStyle(.bordered) }
                else if let result {
                    Button("再生", systemImage: "play.fill") { player?.seek(to: .zero); player?.play() }.buttonStyle(.bordered)
                    ShareLink(item: result.movie) { Label("動画を保存・共有", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered)
                }
                Spacer(minLength: 0)
                Label("NETWORK  /  OFF", systemImage: "wifi.slash").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            ProgressView(value: progress).tint(accent)
            HStack {
                Image(systemName: result == nil ? "circle.dotted" : "checkmark.circle.fill").foregroundStyle(accent)
                Text(stage).font(.subheadline.monospaced()).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(progress * 100))%").font(.subheadline.monospaced()).foregroundStyle(accent)
            }
            if let error { Text(error).font(.subheadline).foregroundStyle(.orange).textSelection(.enabled) }
        }
    }
    private var metrics: some View {
        HStack(spacing: 12) {
            metric("FRAMES", result.map { "\($0.report.decodedFrames) / \($0.report.frames)" } ?? "—", "読み戻し検査")
            metric("RENDER + ENCODE", result.map { String(format: "%.2f s", $0.report.renderAndEncodeSeconds) } ?? "—", "この実行環境の実測")
            metric("FILE SIZE", result.map { String(format: "%.2f MB", Double($0.report.outputBytes) / 1_000_000) } ?? "—", "HEVC / MOV")
        }
    }
    private func metric(_ title: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption2.monospaced()).tracking(1).foregroundStyle(.secondary)
            Text(value).font(.system(size: 25, weight: .semibold, design: .monospaced)).foregroundStyle(.white)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(surface, in: RoundedRectangle(cornerRadius: 14))
    }
    private var scope: some View {
        VStack(alignment: .leading, spacing: 9) {
            #if targetEnvironment(simulator)
            Label("実行環境：iPad Simulator（Mac上）", systemImage: "desktopcomputer").font(.subheadline.weight(.semibold))
            Text("この画面は起動したアプリの実画面。実機iPadの速度・発熱を示すものではないよ。")
                .font(.caption).foregroundStyle(.secondary)
            #else
            Label("実行環境：このiPad", systemImage: "ipad").font(.subheadline.weight(.semibold))
            #endif
            Text("このPOCはMetalの数式描画。AI動画生成・正典素材の制作とは別の動作検証だよ。")
                .font(.caption).foregroundStyle(.secondary)
            if let result { ShareLink(item: result.json) { Label("実行レポート", systemImage: "doc.text") }.font(.caption) }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(18)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }
    @MainActor private func start() {
        guard !running else { return }
        running = true; progress = 0; result = nil; error = nil
        player?.pause(); player = nil
        stage = "Metalパイプラインを準備中"
        UIApplication.shared.isIdleTimerDisabled = true
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VisiblePOC/\(UUID().uuidString)", isDirectory: true)
        task = Task {
            defer { running = false; task = nil; UIApplication.shared.isIdleTimerDisabled = false }
            do {
                let generated = try await VisiblePOCRenderer().render(to: directory) { value, message in
                    Task { @MainActor in
                        guard running else { return }
                        progress = value; stage = message
                    }
                }
                try Task.checkCancellation()
                result = generated; progress = 1; stage = "144フレームの保存・読み戻しに成功"
                let newPlayer = AVPlayer(url: generated.movie)
                player = newPlayer; newPlayer.play()
            } catch {
                if Task.isCancelled { stage = "中止したよ" }
                else { self.error = error.localizedDescription; stage = "生成に失敗" }
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let failure = ["status": "failed", "message": error.localizedDescription]
                if let data = try? JSONSerialization.data(withJSONObject: failure) {
                    try? data.write(to: directory.appendingPathComponent("poc-failure.json"), options: .atomic)
                }
            }
        }
    }
}
