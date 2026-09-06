import SwiftUI

/// Dedicated native POC entry point. No AI view model, model download or server.
/// Compiled by poc-project.yml, not the full app's project.yml.
@main
struct VideoPOCApp: App {
    var body: some Scene {
        WindowGroup {
            VisiblePOCView()
        }
    }
}
