# Shiroi Video Forge

Native iPadOS app under development. Inference, frame composition and video export execute on the iPad; X2 is not the inference host. An unsigned build is not an installable app. See [DELIVERY.md](DELIVERY.md) for delivery gates and honest verification limits.

## Current pipeline
1. Apple's `ml-stable-diffusion` Swift/Core ML pipeline generates image keyframes using a 6-bit SD 1.5 model.
2. Core ML `computeUnits = .all` permits CPU/GPU/Neural Engine scheduling. It does not prove simultaneous use or maximum utilization.
3. Later keyframes use image-to-image from the prior frame.
4. Metal-backed Core Image blending or experimental Vision optical-flow warping builds intermediate frames.
5. AVFoundation writes a local HEVC MOV. Hardware encoding and end-to-end performance need device verification.

This is **image-keyframe animation**, not a full temporal video diffusion model. The source model is nominally 512x512. Increasing exported pixel dimensions is not higher-resolution AI inference.

The model archive is not stored in Git. `ModelManifest.swift` pins the actual Apple/Hugging Face artifact and revision (~1.57 GB). Installation requires at least 5 GB free storage for downloading, staging and safety margin. CRC and structural checks do not replace full model inference tests.

## Build and evidence
The macOS CI selects a stable Xcode 26+ with an iOS SDK 26+ for current Apple submission requirements. The minimum deployment target is still iPadOS 18. Hardware profiles are derived from runtime memory, not an assumed specific iPad model.

For a maintainer building locally on a Mac with supported Xcode selected:

```bash
cd ios/ShiroiVideoForge
python3 scripts/create_app_icon.py
brew install xcodegen
xcodegen generate
xcodebuild -project ShiroiVideoForge.xcodeproj -scheme ShiroiVideoForge \
  -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Pure Foundation regression tests (no Apple SDK or device required):

```bash
swiftc -swift-version 5 Sources/GenerationRequest.swift Sources/ModelManifest.swift Tests/PreflightTests.swift -o /tmp/forge-preflight
/tmp/forge-preflight
```

## Native app delivery
The user is not expected to edit Swift or use Playgrounds. Delivery is through a properly signed beta. The main-only manual TestFlight workflow defaults to no upload and requires the signing inputs documented in DELIVERY.md. Signing credentials and signed binaries are not committed or published as GitHub artifacts.

Before beta delivery: verify signing, current app/SDK privacy declarations, model license obligations, App Store Connect metadata and Apple's processing/review requirements. Before declaring completion: install on the actual iPad, download the model, generate and replay a video, test cancellation and benchmark sustained performance.
