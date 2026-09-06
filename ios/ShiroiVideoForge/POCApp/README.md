# Standalone native iPad POC

The user wants an app, not source-copying steps or a remote monitor. `poc-project.yml` builds a dedicated iPad app that opens the existing GPU generation UI directly. It compiles the same renderer, shader, store and view model but excludes the unfinished AI interface and all external Swift packages/model downloads. This is procedural Metal video rendering, NOT successful AI video generation.

The full AI project stays unchanged. The POC intentionally retains the full app's bundle ID so the same authorized identity can deliver it and later replace it with the full version. Do not install both variants concurrently or call an unsigned bundle installable. The display name is Shiroi Video POC.

## Evidence needed
The new workflow builds the physical iPad target unsigned, then builds and launches an actual simulator app normally (no special landing-page flag), records the screenshot, generates 144 frames at 960x540, decodes them, and verifies saved-history restoration after relaunch. It uploads logs, screenshots and the actual movie only after they exist. A simulator result is not physical-iPad performance. The 540p path does not establish that the HD 720p path is reliable.

The prior head ce4eb030's full-app visible run 34016640850 failed. The downloaded artifact 9984254237 contains a screen showing Encoder backpressure timed out at 5%, no successful movie/report. Its compile passed. This patch does not relabel that HD failure as a success or remove the renderer's timeout checks.

## Installation is still gated
This target cannot be delivered with a source ZIP. TestFlight requires an authorized Apple Developer team and valid signing/App Store Connect setup. The user has stated they are not enrolled. Enrollment, payment, certificates and distribution have not been performed. A free Personal Team/Xcode path requires separate Mac/account/device setup; it is not supplied by this project.

No success of this new target is asserted until its exact-commit workflow is inspected. No real-AI success, signed download, or physical-iPad runtime is claimed.
