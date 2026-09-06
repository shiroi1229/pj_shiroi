import SwiftUI

@main
struct ShiroiVideoForgeApp: App {
    @StateObject private var model = ForgeViewModel()
    var body: some Scene {
        WindowGroup { ForgeAppShell().environmentObject(model) }
    }
}
