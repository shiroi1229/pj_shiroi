// swift-tools-version: 6.0
// WARNING:
// This file follows the Swift Playgrounds App Playground package pattern.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "Shiroi Minimal",
    platforms: [
        .iOS("16.0")
    ],
    products: [
        .iOSApplication(
            name: "Shiroi Minimal",
            targets: ["AppModule"],
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
            path: "."
        )
    ],
    swiftLanguageVersions: [.version("6")]
)
