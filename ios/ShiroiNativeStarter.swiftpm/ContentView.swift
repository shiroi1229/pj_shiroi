import SwiftUI
import Foundation

struct ContentView: View {
    @State private var counter = 0
    @State private var showDetails = false

    private let checks = [
        DevCheck(title: "SwiftUI", detail: "Native UI framework", symbol: "swift"),
        DevCheck(title: "iPadOS", detail: "Native app target", symbol: "ipad"),
        DevCheck(title: "Swift 6", detail: "Language mode", symbol: "chevron.left.forwardslash.chevron.right"),
        DevCheck(title: "GitHub", detail: "Source control ready", symbol: "point.3.connected.trianglepath.dotted")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero
                    checkGrid
                    interactionTest
                }
                .frame(maxWidth: 900, alignment: .leading)
                .padding(24)
            }
            .navigationTitle("Shiroi Native Lab")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("環境情報") {
                        showDetails = true
                    }
                }
            }
            .sheet(isPresented: $showDetails) {
                EnvironmentView()
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Native Dev Ready", systemImage: "checkmark.seal.fill")
                .font(.largeTitle.bold())

            Text("この画面が表示されれば、Swift Playgrounds → SwiftUI → iPadOS ネイティブ実行の最小開発ループは成立してる。")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var checkGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
            ForEach(checks) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: item.symbol)
                        .font(.title2)
                    Text(item.title)
                        .font(.headline)
                    Text(item.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private var interactionTest: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Interaction test")
                .font(.headline)

            Button {
                counter += 1
            } label: {
                Label("Native button test: \(counter)", systemImage: "bolt.fill")
                    .frame(maxWidth: 360)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("ボタンの数値が増えれば、状態更新も正常。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct DevCheck: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let symbol: String
}

private struct EnvironmentView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                LabeledContent("Runtime", value: "SwiftUI / iPadOS")
                LabeledContent("OS", value: ProcessInfo.processInfo.operatingSystemVersionString)
                LabeledContent("Architecture", value: "App Playground (.swiftpm)")
                LabeledContent("Source control", value: "GitHub")
            }
            .navigationTitle("Development Environment")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
