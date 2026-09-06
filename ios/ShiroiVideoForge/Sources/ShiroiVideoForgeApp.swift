import SwiftUI

@main
struct ShiroiVideoForgeApp: App {
    @StateObject private var model = ForgeViewModel()
    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("--poc-autostart") || ProcessInfo.processInfo.arguments.contains("--poc-library-check") {
                VisiblePOCView()
            } else {
                ForgePOCEntry().environmentObject(model)
            }
        }
    }
}

/// Keep the existing AI interface unchanged and add a visible, model-free POC entry.
private struct ForgePOCEntry: View {
    @EnvironmentObject private var model: ForgeViewModel
    @State private var showPOC = false
    var body: some View {
        ForgeAppShell()
            .safeAreaInset(edge: .top) {
                HStack {
                    Text("先にGPU動画生成を試す").font(.subheadline)
                    Spacer()
                    Button("動画生成POC", systemImage: "play.rectangle") { showPOC = true }.disabled(model.isBusy)
                }
                .padding().background(.regularMaterial)
            }
            .fullScreenCover(isPresented: $showPOC) { VisiblePOCView() }
    }
}
