# Shiroi Native Lab

iPadの **Swift Playground** でそのまま開くための、ネイティブ SwiftUI App Playground。

## Target
- Swift 6 language mode
- SwiftUI
- iPadOS / iOS 18+
- iPad / iPhone family
- Swift Package Manager compatible App Playground
- External dependencies: none

## First run on iPad
1. Apple純正 **Swift Playground** をインストール。
2. `ShiroiNativeStarter.swiftpm.zip` を「ファイル」に保存して展開。
3. `ShiroiNativeStarter.swiftpm` をタップして Swift Playground で開く。
4. App Preview に `Native Dev Ready` が表示されることを確認。
5. 「Appを実行」で独立ウインドウ実行。
6. `Native button test` を押し、数値が増えれば最小ネイティブ開発ループ完成。

## Source control
Canonical source is stored in GitHub under `shiroi1229/pj_shiroi`.
For direct Git operations from iPad, Working Copy can expose a Git repository through the Files app so the `.swiftpm` document package can be opened from Swift Playground.

## Security baseline
- APIキー、トークン、パスワードをソースコードへ直書きしない。
- 公開GitHubへ秘密情報をcommitしない。
- OpenAI等の秘密APIキーが必要な本番アプリは、原則として自前backend経由にする。

## Next architecture
FeatureごとにSwiftファイルを分割し、必要になった時点で以下を追加する。
- REST / WebSocket client
- SwiftData persistence
- Core ML / Vision
- Camera / Photos
- Bluetooth
- Notifications
- X2 / SSP client
