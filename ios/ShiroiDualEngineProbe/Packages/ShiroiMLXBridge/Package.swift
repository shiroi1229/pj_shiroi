// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShiroiMLXBridge",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "ShiroiMLXBridge", targets: ["ShiroiMLXBridge"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/ml-explore/mlx-swift-examples.git",
            revision: "378f2449c257788c5067b9f8b086731d76b39b33"
        )
    ],
    targets: [
        .target(
            name: "ShiroiMLXBridge",
            dependencies: [
                .product(
                    name: "StableDiffusion",
                    package: "mlx-swift-examples",
                    moduleAliases: ["StableDiffusion": "MLXStableDiffusion"]
                )
            ]
        )
    ]
)
