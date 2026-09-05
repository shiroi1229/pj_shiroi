# iPad delivery gate — 2026-09-06

## User acceptance criteria
Deliver an installable native iPad app. Inference, GPU composition and video export must run on the iPad. X2 may help prepare models; it is not the video-generation host. Do not ask the user to copy Swift into Playgrounds.

## This patch
- Corrects a wrong model archive filename (`-base-` was not present in the actual artifact listing) and pins revision `04a6a0bdd66fb8da470c14e56d762343ef579d88`.
- Validates ZIP CRC and nonempty resource structure. This is not SHA-256 verification of the complete model.
- Stages model files on the destination volume without an extra 1.57 GB copy, checks storage and rejects overlapping installs.
- Rejects invalid duration, frame rate, dimensions, motion and bitrate before expensive inference.
- Rejects empty keyframes, detects writer failures, times out encoder backpressure, cleans incomplete files and preserves reusable GPU caches.
- Adds 22 executable Foundation regression checks, unsigned Release artifacts, app icon generation, signing-readiness reporting and a manual TestFlight workflow.

## What counts as evidence
| Gate | Evidence required |
| --- | --- |
| Pure Swift checks | Passing test output; no GPU inference implied |
| Apple SDK compile | Success for the exact source commit |
| Model availability | Successful HEAD; not a completed 1.57 GB download |
| Signed binary | Valid archive/export from an authorized Apple team |
| Installability | App Store Connect processing and a tester-accessible build |
| End-to-end iPad | Model installed, prompt submitted, video saved and replayed on the actual device |
| Performance | Repeated measured runs, output quality, memory and thermal results; `.all` does not prove saturation |

## Delivery workflows
`iPad Video Forge Build` runs on affected pull requests and main pushes. It uploads **unsigned evidence only**, explicitly labeled non-installable. On main it separately reports whether the repository contains the following secret names; it never prints their values:

`APPLE_TEAM_ID`, `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, `BUILD_PROVISION_PROFILE_BASE64`, `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_PRIVATE_KEY`.

Apple membership, credentials, team, profile capability matching and App Store Connect app ownership have not been established by this patch. A present secret name is not proof of a valid credential. Never paste private keys into chat or commit them to Git.

`iPad Video Forge TestFlight` is manual, main-only and defaults to **no upload**. With explicit upload enabled and valid repository secrets it prepares an archive, exports a signed IPA and uploads to Apple. It does not publish an App Store release or automatically invite testers. Signed binaries are not uploaded to this public GitHub repository. The upload path has not been exercised without real authorized signing credentials.

Before distribution, review the merged app/SDK privacy manifests, required-reason API declarations, model license obligations and App Store Connect compliance metadata. Upload acceptance and beta review remain Apple's checks, not an assertion made by this code.

## Current engine scope
This remains Stable Diffusion image keyframes + Metal/Vision interpolation, **not temporal video diffusion**. No iPad CPU/GPU/Neural Engine utilization percentage or generation speed is claimed without real measurements. The exact iPad model and RAM must come from runtime/device evidence, not ChatGPT user-agent guesses.

## Official references
- https://huggingface.co/apple/coreml-stable-diffusion-v1-5-palettized/tree/04a6a0bdd66fb8da470c14e56d762343ef579d88
- https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications
- https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases
