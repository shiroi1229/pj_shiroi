import AVKit
import SwiftUI
import UIKit

struct ForgeAppShell: View {
    @EnvironmentObject private var model: ForgeViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showDiagnostics = false

    var body: some View {
        ContentView()
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Text("実験版：AI画像生成＋フレーム補間")
                        .font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button("GPU・動画出力を診断", systemImage: "checkmark.shield") { showDiagnostics = true }
                        .disabled(model.isBusy)
                }
                .padding().background(.regularMaterial)
            }
            .sheet(isPresented: $showDiagnostics) { NativeDiagnosticsView() }
            .onChange(of: model.isBusy) { _, busy in
                UIApplication.shared.isIdleTimerDisabled = busy
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    model.cancelGeneration()
                    UIApplication.shared.isIdleTimerDisabled = false
                } else if phase == .active {
                    UIApplication.shared.isIdleTimerDisabled = model.isBusy
                }
            }
    }
}

private struct NativeDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var task: Task<Void, Never>?
    @State private var result: NativeDiagnosticResult?
    @State private var error: String?
    @State private var running = false
    private let capabilities = DeviceCapabilities.current()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("この端末で実行して検証する")
                        .font(.title2.bold())
                    Text("GPU計算をCPUの正解値と照合し、1秒の診断映像を書き出して全フレームを読み戻すよ。AIモデルは使わないので、AI動画の品質・速度の評価とは別の検査だよ。")
                    GroupBox("端末から取得した情報") {
                        VStack {
                            LabeledContent("GPU", value: capabilities.gpuName)
                            LabeledContent("CPU", value: "\(capabilities.cpuCores) cores")
                            LabeledContent("物理メモリ", value: String(format: "%.1f GB", capabilities.memoryGB))
                        }.padding(.vertical, 6)
                    }
                    Button(running ? "診断を実行中" : "GPU計算・動画出力を検査する") { run() }
                        .buttonStyle(.borderedProminent).disabled(running)
                    if running {
                        ProgressView("この端末で計算・書き出し・検査中…")
                        Button("中止") { task?.cancel() }
                    }
                    if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                    if let result {
                        GroupBox("実行結果") {
                            VStack {
                                LabeledContent("実行環境", value: result.report.host)
                                LabeledContent("GPU計算照合", value: "1,048,576要素が一致")
                                LabeledContent("動画読み戻し", value: "\(result.report.decodedFrames) frames")
                                LabeledContent("出力処理時間", value: String(format: "%.3f s", result.report.exportSeconds))
                                if let seconds = result.report.gpuCommandSeconds {
                                    LabeledContent("GPUコマンド時間", value: String(format: "%.3f ms", seconds * 1000))
                                }
                                Text("この数値は診断処理の実測値。GPU使用率や生成AIの性能を表すものではないよ。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 6)
                        }
                        VideoPlayer(player: AVPlayer(url: result.videoURL))
                            .frame(height: 260)
                        HStack {
                            ShareLink("診断レポートを共有", item: result.reportURL)
                            ShareLink("診断映像を共有", item: result.videoURL)
                        }
                    }
                }.padding(24)
            }
            .navigationTitle("Native Engine Diagnostics")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
        .onDisappear { task?.cancel(); UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { task?.cancel(); UIApplication.shared.isIdleTimerDisabled = false }
        }
    }

    @MainActor private func run() {
        guard !running else { return }
        running = true; error = nil; result = nil
        UIApplication.shared.isIdleTimerDisabled = true
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShiroiDiagnostics/\(UUID().uuidString)", isDirectory: true)
        task = Task {
            defer { running = false; task = nil; UIApplication.shared.isIdleTimerDisabled = false }
            do { result = try await NativeDiagnostics().run(directory: directory) }
            catch is CancellationError { error = "診断を中止したよ。" }
            catch { self.error = error.localizedDescription }
        }
    }
}
