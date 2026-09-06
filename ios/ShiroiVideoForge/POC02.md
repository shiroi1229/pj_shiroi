# POC 02: reusable native GPU video workspace

## User goal
Continue the native iPad video app. This patch advances the visible Metal renderer, not the unresolved AI model path. It does not supply a signed IPA or prove physical-iPad performance.

## Implemented
- Three bounded GPU render profiles: 960x540, 1280x720 and 720x1280; 24 fps, six seconds.
- Persistent, selectable output history and sharing after app relaunch.
- Explicitly confirmed deletion of selected videos only. Successfully saved videos are never silently pruned.
- Same-volume staging and commit so partial/cancelled attempts do not appear as completed videos. Cancellation cleans the current staging directory and preserves prior outputs.
- Main-actor view model, retained player, operation-scoped progress callbacks, centralized app sleep leases and disabled POC launch while the AI view is busy.
- Fresh dedicated simulator and a unique render ID for each capture, eliminating acceptance of another run's outputs.
- Recording container/sample validation and a second app launch that must restore the exact saved result without regeneration.

## Executed locally
18 Foundation storage/profile checks passed under Swift 6.2.1 in Swift 5 mode. Swift parse and shell syntax checks passed. These tests use structural fixture files and are not media/GPU/inference execution.

## Native acceptance
The exact-commit CI must compile and run the iPad app, export all 144 HD frames, decode them, produce a screenshot and screen recording, and restore the same result after relaunch. The portrait profile is implemented and covered by dimension constraints but not considered visually tested unless a dedicated capture exists.

## Boundaries
The scene is procedural mathematics, not AI video diffusion or canon content. Simulator timings do not represent the user's iPad. Apple signing, TestFlight availability, actual device installation and real AI generation remain independent unfinished gates. Abrupt process termination may leave staging files; this patch cleans cooperative cancellations, not all possible crash recovery scenarios.
