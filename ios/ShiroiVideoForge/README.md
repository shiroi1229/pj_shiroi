# Shiroi Video Forge

Native iPadOS video generation app designed for M4 iPad Pro. Generation is executed on-device; X2 is not part of the inference path.

## V1 pipeline
1. Prompt is encoded and diffusion keyframes are generated with Apple's `ml-stable-diffusion` Swift/Core ML pipeline.
2. Core ML uses a mobile-optimized 6-bit Stable Diffusion 1.5 model. The iPad profile uses CPU + Neural Engine with reduced-memory loading.
3. Subsequent keyframes use image-to-image from the prior keyframe for temporal continuity.
4. Core Image executes through a Metal-backed context to synthesize the temporal frames.
5. AVFoundation encodes the final MOV with HEVC, using Apple's hardware media path when available.

The shipped model is not committed to Git. The app downloads the public Core ML archive (~1.56 GB) from Apple's Hugging Face model repository and stores it in Application Support on the iPad.

## Hardware adaptation
The app reads physical memory at runtime. 8 GB-class devices default to fewer keyframes and fewer diffusion steps. 16 GB-class devices use a higher quality profile.

## Build
The project is described by `project.yml` and generated with XcodeGen.

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project ShiroiVideoForge.xcodeproj -scheme ShiroiVideoForge -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Actual device installation requires Apple code signing. The repository CI performs an unsigned compile check; TestFlight/device delivery requires an Apple Developer signing setup.

## Next generation engine
V2 will replace the keyframe temporal bridge with a converted temporal/video diffusion Core ML model after on-device memory and thermal profiling on the target M4 iPad Pro. The renderer and encoder are already isolated so that model can be swapped without replacing the app shell.
