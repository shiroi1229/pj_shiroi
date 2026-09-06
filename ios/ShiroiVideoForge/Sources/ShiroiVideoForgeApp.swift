import SwiftUI

@main
struct ShiroiVideoForgeApp: App {
    @StateObject private var model = ForgeViewModel()
    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("--poc-autostart") {
                VisiblePOCView()
            } else {
                ForgePOCEntry().environmentObject(model)
            }
        }
    }
}

/// Keep the existing AI interface unchanged and add a visible, model-free POC entry.
private struct ForgePOCEntry: View {
    @State private var showPOC = false
    var body: some View {
        ForgeAppShell()
            .safeAreaInset(edge: .top) {
                HStack {
                    Text("先にGPU動画生成を試す").font(.subheadline)
                    Spacer()
                    Button("動画生成POC", systemImage: "play.rectangle") { showPOC = true }
                }
                .padding().background(.regularMaterial)
            }
            .fullScreenCover(isPresented: $showPOC) { VisiblePOCView() }
    }
}
