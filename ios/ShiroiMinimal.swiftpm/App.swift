import SwiftUI

@main
struct ShiroiMinimalApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                Text("Native Dev Ready")
                    .font(.largeTitle.bold())
                Text("SwiftUI is running natively on iPad.")
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}
