# iPad Native Development Environment

## Goal
Use iPad Pro as a first-class native iPadOS/iOS development workstation without requiring a Mac for day-to-day SwiftUI implementation.

## Base stack
- Device: iPad Pro
- IDE/runtime: Apple Swift Playground
- Language: Swift 6
- UI: SwiftUI
- Project format: App Playground (`.swiftpm`)
- Source control: GitHub (`shiroi1229/pj_shiroi`)
- AI pair development: ChatGPT

## Canonical project
`ios/ShiroiNativeStarter.swiftpm`

## Daily loop
1. Define or revise a feature in ChatGPT.
2. Update canonical Swift source in GitHub.
3. Open/sync the `.swiftpm` project on iPad.
4. Verify App Preview.
5. Run the app full screen on the iPad.
6. Fix compile/runtime/UI issues and commit the correction.

## iPad Git workflow
Swift Playground itself is not the source-control system. For direct Git operations from iPad, use a Git client that integrates with Files, such as Working Copy, and expose/link the `.swiftpm` document package there. GitHub remains the canonical remote.

## Quality gates
Before a feature is considered complete:
- App Preview renders without compiler errors.
- Full-screen app launch succeeds.
- Primary interaction is tested on iPad.
- No secret/token/API key is committed.
- UI works in both portrait and landscape unless intentionally constrained.
- iPad layout is reviewed at large-screen width.

## Distribution
Swift Playground can submit an app to App Store Connect after signing in with an eligible Apple Developer account and configuring the app identity/capabilities. A custom app icon is required for App Store submission.

## Escalation to Xcode
Keep the `.swiftpm` project portable. Move to Xcode only when a feature requires tooling or target configuration not supported by Swift Playground. The same project can later be opened on a Mac with Xcode.
