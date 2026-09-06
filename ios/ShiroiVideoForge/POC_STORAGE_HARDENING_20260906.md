# POC storage hardening — 2026-09-06

## Confirmed baseline

Branch `ipad-forge-visible-poc-20260906`, parent `9fcb2d5e3ff6313d3080f8db9424f28ae828042e`.
GitHub runs 34013696602 (Build), 34013696562 (Runtime Checks), and 34013696551 (Visible POC) completed successfully. These are the previous revision's results, not verification of this change.
The older downloadable Library Candidate was based on `55a1f25e083b7be09abd70f3c0309a3b803bc5cb`; it must not overwrite the newer store/view-model implementation.

## Reproduced defect and changes

The old store accepted a repeated staging UUID. The new regression test failed against the unmodified store at `duplicate operation ID rejected`.
Every operation now requires a fresh unpublished UUID. Existing pending or saved IDs are rejected without deleting their data. Symlinked or replaced staging parents are rejected before writing. Dangling links count as occupied paths.
Stored reports must describe non-AI POC rendering, even positive dimensions, consistent frame-count/fps/duration and valid nonnegative GPU timing when present. These are structural checks, not another movie decode.

## Local verification

The exact two source files were compiled using Swift in the Linux working container. All 33 storage/profile checks passed (18 prior checks plus 15 added checks). Swift syntax parsing passed. This does not establish an Apple SDK build, GPU render or physical-iPad run for this revision; the existing PR workflows must verify those separately.
No completed user exports were deleted. The old valid report format remains readable. These guards do not claim resistance to an adversarial filesystem swap between every system call.

## Outstanding blockers

Real AI generation remains unverified end-to-end. The diagnostic-only CLIP normalization experiment in PR #17, run 34013241728, still ended `safetyFiltered` after the first keyframe's denoising steps; it did not resolve the failure. No safety threshold or production SDK was changed by this storage work.
Signed distribution and physical-iPad execution remain unverified. The last recorded signing check lacked required CI configuration; this does not establish the user's Apple membership status.
