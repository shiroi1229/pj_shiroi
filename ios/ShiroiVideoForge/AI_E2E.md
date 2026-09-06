# Real AI inference and compute-policy controls — 2026-09-06

## Deliverable
A native iPad app that runs its own Core ML prediction and Metal/HEVC composition. No remote-rendering replacement or manual Swift editing is required of the user. Apple signing and target-device validation remain independent delivery gates.

## Changes
Four inference scheduling policies are exposed: automatic, CPU+GPU, CPU+Neural Engine, and CPU-only. The production generator recreates the pipeline when the policy changes. Requested policy is saved with benchmark JSON/CSV; legacy records remain decodable through an optional persisted field. Scheduling permission is NOT measured utilization, and no fastest mode is asserted before target-device comparison.

Zero motion reuses the first generated keyframe. Failed loads clear the cached pipeline. Download cancellation has a bounded completion fallback and ignores late callbacks. Diagnostic playback retains a stable AVPlayer. Model verification compares the exact native app hash/size pins. Only the test executable permits HTTP to localhost.

## Real E2E evidence
The native macOS executable copies ten production Swift source files, uses the same pinned StableDiffusion dependency and verifies the same model bytes. It generates real keyframes, composes HEVC with production code, and decodes all output frames. Safety checking stays enabled, unchanged. No filtered images are exported.

Initial Fast-profile teapot test, seed 1229:
- Run 34006950854: CPU-only completed 8 denoising steps but returned no usable image; the E2E gate failed.
- Run 34007416192: CPU+GPU completed denoising and confirmed `safetyFiltered`; the E2E gate failed. Known synthetic color-block calibration was accepted in both processor modes.
- These are not successes. Nor do these two observations establish that either processor policy is generally broken or that the generation itself was safe.

The next fixed smoke recipe exercises the app's default Balanced quality with a mountain-landscape prompt, seed 42, CPU+GPU permission. The precise recipe is saved before inference. Changing the recipe is not a fix for the earlier filtered output, and does not make that earlier case pass. There is no automatic prompt mutation, filter bypass or threshold relaxation in the app.

A passed JSON report is only written after real images, export and full-frame decoding succeed. Failure JSON/logs are retained. CPU/GPU CI host timings are NOT target-iPad performance. This remains image-keyframe animation, not temporal video diffusion, and a smoke pass is not a quality approval.

## Verification
Foundation checks: 24. Download/integrity checks: 9. Latest exact-commit workflow results control the acceptance gate; script creation and compilation do not prove real AI video generation. Signed installation and physical-iPad generation are still unverified.

## Primary references
- https://developer.apple.com/documentation/coreml/mlcomputeunits
- https://github.com/apple/ml-stable-diffusion
