# Visible native POC

The user's request is to see the native iPad app, even as a POC. This patch adds a model-free **GPU video rendering** screen to the existing iPad application. It is not a replacement for the requested AI generation feature.

## What it executes
A bundled Metal compute shader calculates every pixel of a non-canon orbital test scene. The app exports 144 frames at 960x540 / 24 fps into a six-second HEVC MOV, reads back every frame and verifies size/count/duration before declaring success. The app supports start, cancel, replay and sharing the video/report. No network request, external image or AI model is used in this POC.

## Evidence
The visible-poc workflow builds the actual iOS Simulator target, installs and launches it in an available iPad Pro simulator, records the framebuffer, captures a screenshot, and collects the app's own MOV/PNG/JSON. No screenshot is mocked or drawn by a separate design tool. The exact simulated model comes from the runtime, not an assumption about the user's device.

The `--poc-autostart` argument opens and starts the same native view for capture; users can open the POC from the normal app and press the button. A simulator result is not physical-iPad performance and not a signed installable IPA. The separate AI-generation E2E remains unresolved in PR #15. Apple signing/TestFlight and real-device tests remain necessary for delivery.

## Acceptance
Do not report success until simulator launch, Metal execution, HEVC export and decode, real screenshot, and screen recording are present. A code commit or unsigned build alone is insufficient. GPU command timings may be absent when the runtime does not report them; no utilization percentage is fabricated.
