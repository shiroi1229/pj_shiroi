#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
GENERATED_DIR="$ROOT_DIR/.generated"
MLX_DEST="$GENERATED_DIR/MLXStableDiffusionSource"
COREML_DEST="$GENERATED_DIR/CoreMLStableDiffusionSource"
MLX_UPSTREAM="https://github.com/ml-explore/mlx-swift-examples.git"
MLX_REVISION="378f2449c257788c5067b9f8b086731d76b39b33"
COREML_UPSTREAM="https://github.com/apple/ml-stable-diffusion.git"
COREML_REVISION="e12202c1f6405b83918b58a5d097cd61e3e1f702"

prepare_checkout() {
    local dest="$1"
    local upstream="$2"
    local revision="$3"
    shift 3

    rm -rf "$dest"
    mkdir -p "$dest"
    git -C "$dest" init -q
    git -C "$dest" remote add origin "$upstream"
    git -C "$dest" fetch -q --depth 1 origin "$revision"
    git -C "$dest" checkout -q FETCH_HEAD -- "$@"
}

prepare_checkout \
    "$MLX_DEST" \
    "$MLX_UPSTREAM" \
    "$MLX_REVISION" \
    Libraries/StableDiffusion LICENSE

cat > "$MLX_DEST/Package.swift" <<'SWIFT'
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

prepare_checkout \
    "$COREML_DEST" \
    "$COREML_UPSTREAM" \
    "$COREML_REVISION" \
    swift/StableDiffusion LICENSE.md

cat > "$COREML_DEST/Package.swift" <<'SWIFT'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShiroiCoreMLStableDiffusion",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CoreMLStableDiffusion",
            targets: ["CoreMLStableDiffusion"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/huggingface/swift-transformers",
            exact: "1.3.4"
        )
    ],
    targets: [
        .target(
            name: "CoreMLStableDiffusion",
            dependencies: [
                .product(name: "Transformers", package: "swift-transformers")
            ],
            path: "swift/StableDiffusion"
        )
    ]
)
SWIFT

echo "Prepared MLXStableDiffusion from $MLX_REVISION at $MLX_DEST"
echo "Prepared CoreMLStableDiffusion from $COREML_REVISION at $COREML_DEST"
