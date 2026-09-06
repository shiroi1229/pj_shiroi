import SwiftUI

/// Stores the requested scheduling policy in the generation request, not a global
/// Core ML setting. The generator reloads resources when this policy changes.
struct EngineComputeControls: View {
    @EnvironmentObject private var model: ForgeViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("AI推論の実行設定", selection: $model.computePolicy) {
                ForEach(InferenceComputePolicy.allCases) { policy in
                    Text(policy.title).tag(policy)
                }
            }
            .pickerStyle(.menu)
            .disabled(model.isBusy)
            Text("演算器の使用を許可する設定だよ。実際の割り当てはCore MLが決める。最速の設定は端末で測って比較するよ。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
