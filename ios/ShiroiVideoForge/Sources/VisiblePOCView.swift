import AVKit
import SwiftUI
import UIKit

/// A usable native proof of concept, not a mockup or a web-rendered preview.
struct VisiblePOCView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = VisiblePOCViewModel()
    @State private var deleteCandidate: VisiblePOCResult?
    private var result: VisiblePOCResult? { model.result }
    private var player: AVPlayer? { model.player }
    private var running: Bool { model.running }
    private var progress: Double { model.progress }
    private var stage: String { model.stage }
    private var error: String? { model.error }
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
                    history
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
            await model.refresh()
            let args = ProcessInfo.processInfo.arguments
            if let index = args.firstIndex(of: "--poc-profile"), args.indices.contains(index + 1),
               let profile = VisiblePOCProfile(rawValue: args[index + 1]) { model.profile = profile }
            if args.contains("--poc-library-check"), let result = model.result {
                let report: [String: Any] = ["selected_id": result.id, "history_count": model.history.count,
                    "restored_ids": model.history.map(\.id), "render_started": false]
                if let data = try? JSONSerialization.data(withJSONObject: report, options: .sortedKeys) {
                    try? data.write(to: result.directory.appendingPathComponent("poc-reopened.json"), options: .atomic)
                }
            }
            guard autoRun, !autoStarted else { return }
            autoStarted = true
            var id: UUID?
            if let index = args.firstIndex(of: "--poc-run"), args.indices.contains(index + 1) {
                id = UUID(uuidString: args[index + 1])
            }
            do { try await Task.sleep(for: .seconds(3)); model.start(id: id) } catch {}
        }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { model.stop() } }
        .alert("この試作動画を削除する？", isPresented: Binding(
            get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }
        ), presenting: deleteCandidate) { item in
            Button("削除", role: .destructive) { Task { await model.delete(item) } }
            Button("残す", role: .cancel) {}
        } message: { _ in Text("このアプリ内の動画・ポスター・レポートを削除するよ。共有済みのコピーは変更しないよ。") }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("NATIVE VIDEO ENGINE").font(.caption.monospaced()).tracking(2).foregroundStyle(accent)
                Spacer()
                Text("POC / 02").font(.caption.monospaced()).padding(.horizontal, 12).padding(.vertical, 6)
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
            .aspectRatio(result.map { CGFloat($0.report.width) / CGFloat($0.report.height) } ?? (16.0 / 9.0), contentMode: .fit)
            HStack {
                Label(result == nil ? "RENDER TARGET" : "LOCAL VIDEO", systemImage: "film")
                Spacer()
                Text("\(result?.report.width ?? model.profile.width) × \(result?.report.height ?? model.profile.height)  /  24 FPS  /  6 SEC")
            }
            .font(.caption.monospaced()).foregroundStyle(.secondary).padding(14).background(surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.08)))
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("出力サイズ", selection: $model.profile) {
                ForEach(VisiblePOCProfile.allCases) { profile in Text(profile.title).tag(profile) }
            }.pickerStyle(.segmented).disabled(running)
            HStack(spacing: 16) {
                Button(action: start) {
                    Label(running ? "生成中…" : (result == nil ? "6秒の映像を生成" : "もう一度生成"), systemImage: "bolt.fill")
                        .font(.headline).padding(.horizontal, 16).padding(.vertical, 9)
                }
                .buttonStyle(.borderedProminent).disabled(running).accessibilityIdentifier("poc.generate")
                if running { Button("中止") { model.stop() }.buttonStyle(.bordered) }
                else if let result {
                    Button("再生", systemImage: "play.fill") { model.replay() }.buttonStyle(.bordered)
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
    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("保存履歴", systemImage: "clock.arrow.circlepath").font(.headline)
                Spacer()
                Text("\(model.history.count) 本").font(.caption.monospaced()).foregroundStyle(accent)
            }
            if model.history.isEmpty {
                Text("完了した動画はここに残るよ。アプリを開き直しても選べるよ。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.history) { item in
                HStack(spacing: 12) {
                    Image(systemName: item.id == result?.id ? "checkmark.circle.fill" : "film")
                        .foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(item.report.width) × \(item.report.height) / 6秒").font(.subheadline.monospaced())
                        Text("\(item.id.prefix(8))  •  \(String(format: "%.2f MB", Double(item.report.outputBytes) / 1_000_000))")
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("開く") { model.select(item) }.buttonStyle(.bordered)
                    ShareLink(item: item.movie) { Image(systemName: "square.and.arrow.up") }
                    Button(role: .destructive) { deleteCandidate = item } label: { Image(systemName: "trash") }
                        .accessibilityLabel("試作動画を削除")
                }.disabled(running)
            }
            Text("成功した動画は自動で消さないよ。不要なものだけ選んで削除できるよ。")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(18).background(surface, in: RoundedRectangle(cornerRadius: 14))
    }
    @MainActor private func start() { model.start() }
}
