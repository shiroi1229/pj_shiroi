// swift-tools-version: 6.0
//
// Swift Playgrounds app package for iPad/iPhone.
// Swift Playgrounds may regenerate this file when project settings change.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "Shiroi Native Lab",
    platforms: [
        .iOS("18.0")
    ],
    products: [
        .iOSApplication(
            name: "Shiroi Native Lab",
            targets: ["AppModule"],
            bundleIdentifier: "com.shiroi1229.nativeLab",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .pencil),
            accentColor: .presetColor(.cyan),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: ".",
            exclude: ["README.md"]
        )
    ],
    swiftLanguageVersions: [.version("6")]
)
