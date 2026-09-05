#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
GENERATED_DIR="$ROOT_DIR/.generated"
DEST="$GENERATED_DIR/MLXStableDiffusionSource"
UPSTREAM="https://github.com/ml-explore/mlx-swift-examples.git"
REVISION="378f2449c257788c5067b9f8b086731d76b39b33"

rm -rf "$DEST"
mkdir -p "$DEST"
git -C "$DEST" init -q
git -C "$DEST" remote add origin "$UPSTREAM"
git -C "$DEST" fetch -q --depth 1 origin "$REVISION"
git -C "$DEST" checkout -q FETCH_HEAD -- Libraries/StableDiffusion LICENSE

cat > "$DEST/Package.swift" <<'SWIFT'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShiroiMLXStableDiffusion",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MLXStableDiffusion",
            targets: ["MLXStableDiffusion"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/ml-explore/mlx-swift",
            exact: "0.31.4"
        ),
        .package(
            url: "https://github.com/huggingface/swift-transformers",
            exact: "1.3.4"
        )
    ],
    targets: [
        .target(
            name: "MLXStableDiffusion",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "Transformers", package: "swift-transformers")
            ],
            path: "Libraries/StableDiffusion",
            exclude: ["README.md"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
SWIFT

echo "Prepared MLXStableDiffusion from $REVISION at $DEST"
