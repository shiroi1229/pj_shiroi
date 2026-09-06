# Real AI inference and compute-policy controls — 2026-09-06

## Deliverable
A native iPad app that runs its own Core ML prediction and Metal/HEVC composition. No remote-rendering replacement or manual Swift editing is required of the user. Apple signing and target-device validation remain independent delivery gates.

## Changes
The native app now exposes four inference scheduling policies: automatic, CPU+GPU, CPU+Neural Engine, and CPU-only for comparison. The production generator recreates the pipeline when this policy changes, so the interface cannot silently keep the previous configuration. Requested policy is saved with benchmark JSON/CSV; legacy records remain decodable because the new persisted field is optional. A requested processor policy is NOT measured processor utilization, and no fastest mode is asserted before target-device comparison.

Zero motion reuses the first generated keyframe rather than invoking image-to-image with zero denoising. Model-load failures clear the cached pipeline. Cancellation completion has a bounded fallback for URLSession completion races. The diagnostic player survives SwiftUI recomputation.

## Real E2E test
`iPad Video Forge Real AI E2E` builds a native macOS command-line probe from unmodified copies of ten production Swift files. It uses the same pinned StableDiffusion package and model archive as the app. It generates at least two real 512x512 keyframes using the Fast profile, including text-to-image followed by image-to-image, then uses the production Metal-backed compositor to write a one-second HEVC movie and decode all twelve frames.

Safety checking stays enabled. Keyframe PNGs, the movie, hashes, log and JSON report are retained as evidence. The report is only written as passed after predictions, export and decode succeed. CPU-only inference on a macOS CI host is not an iPad benchmark, and this pipeline is still image-keyframe animation, not temporal video diffusion. Eight-step Fast output is not a production-quality approval.

## Review fixes
The model archive test now compares remote metadata and full bytes to the exact size/SHA-256 pinned by the native app. The network-test executable uses `localhost` as an eligible ATS exception hostname; no production network-security exception is added.

## Verification status
Local Foundation checks: 24 passed. Apple SDK compile, download tests, and real E2E execution must be read from the workflow result for the exact commit; creating these scripts alone is not success evidence. Signed installation and real iPad video generation remain unverified.

## Primary references
- https://developer.apple.com/documentation/coreml/mlcomputeunits
- https://github.com/apple/ml-stable-diffusion
