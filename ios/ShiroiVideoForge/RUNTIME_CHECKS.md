# Native runtime validation — 2026-09-06

## Goal and boundaries
The deliverable remains a native iPad app that does its own inference and video export. No remote-rendering substitution or manual Swift copy/paste is required of the user. This patch is not signed delivery, and the production model still generates image keyframes plus interpolation rather than temporal video diffusion.

## Verified full model (before this runtime patch)
GitHub Actions run 34004454022 downloaded the complete pinned Apple model, verified SHA-256 and ZIP CRC, and loaded all five compiled Core ML models on a macOS CPU. Its evidence artifact is 9980543107. The actual archive size is 1,565,721,769 bytes and its SHA-256 is 49a6ac1f62e12a2b3e426730d686fa466e30cba11c03b85305775714fb9814ec.

This is a model-format and availability test, NOT image inference, video quality, user-iPad performance, or Neural Engine verification.

## Runtime changes
- Download progress and a cancellable task are now connected to the app's existing controls.
- URLSession resume data is saved on explicit pause and eligible network failures. The server, temporary-file availability and HTTP validators still determine resumability. Expired redirect metadata gets one clean retry from the pinned source.
- The old one-hour transfer ceiling is replaced with a seven-day resource ceiling; this is not a promise of background execution. The app pauses work when backgrounded.
- The downloaded archive is checked against the pinned size and SHA-256 before extraction. Verification streams 4 MiB blocks instead of loading the whole archive into RAM.
- Old progress callbacks cannot change a later operation or overwrite completed state.
- Writer cancellation is routed through its actor. CoreVideo texture wrappers remain alive until GPU completion.
- Required-reason privacy declarations cover app-container file metadata, elapsed-time measurement and free-space checks. No analytics SDK or tracking is introduced. App Store privacy review is still required.

## User-facing native diagnostics
The app includes a Japanese diagnostic sheet. It executes a bounded Metal kernel over 1,048,576 floats, compares every result with a CPU reference, creates a one-second HEVC diagnostic clip using the production compositor, then decodes and checks all 12 frames, dimensions and duration. It reports host identity and GPU command/export timings only when actually measured. The generated fixture is explicitly NOT AI content and is separate from the user's output library.

## Automated evidence
- Existing 22 Foundation regression checks still pass locally.
- New runtime CI tests cancellation before startup, in-flight cancellation, resume-state storage, resumed payload correctness, state cleanup, HTTP errors and known SHA-256 vectors.
- Native diagnostic runs on the CI host only when Metal is available. Lack of a GPU is recorded as NOT TESTED, never a fabricated success.
- Source snapshots and JSON/log evidence are retained with the build. Model weights and signing credentials are excluded.

## Remaining delivery gates
Apple signing setup and TestFlight distribution remain required. No Apple identity, developer membership, certificate or API credential is invented by these changes. Do not store private keys in source or paste them into chat. Until signed installation and successful AI generation/replay on the physical iPad are observed, overall delivery is incomplete.

## Primary references
- https://developer.apple.com/documentation/foundation/pausing-and-resuming-downloads
- https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype
- https://huggingface.co/apple/coreml-stable-diffusion-v1-5-palettized/tree/04a6a0bdd66fb8da470c14e56d762343ef579d88
