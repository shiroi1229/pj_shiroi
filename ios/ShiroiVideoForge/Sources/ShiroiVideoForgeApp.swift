import SwiftUI

@main
struct ShiroiVideoForgeApp: App {
    @StateObject private var model = ForgeViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
    }
}
