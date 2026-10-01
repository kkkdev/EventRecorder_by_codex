# Teams 会議自動録画 調査ログ

## 参照

- Apple `SCContentFilter(desktopIndependentWindow:)`
  - <https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init%28desktopindependentwindow%3A%29>
- Apple ScreenCaptureKit sample
  - <https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos>
- Apple Meet ScreenCaptureKit
  - <https://developer.apple.com/videos/play/wwdc2022/10156/>
- Apple Accessibility observer
  - <https://developer.apple.com/documentation/applicationservices/1460133-axobservercreate>
- Microsoft Graph attendance report
  - <https://learn.microsoft.com/graph/api/meetingattendancereport-get>

## 影響したポイント

1. `desktopIndependentWindow`は指定windowだけを取得でき、display移動にも適する。
2. ScreenCaptureKitの音声filterはapplication粒度であり、Teams自身の通知音は分離できない可能性がある。
3. Accessibility observerはwindow作成・破棄やvalue変更を検出できるが、Teams UI更新への耐性が必要。
4. Graph attendance reportは会議終了後のartifactであり、リアルタイム参加判定には使わない。
5. 現行実装のdisplay filterはChrome/Meet無音対策として導入されたため、Teams window filterへ切り替える際は相手音声を実機で再検証する。

## ローカル調査

- Microsoft Teams bundle ID: `com.microsoft.teams2`
- 現行EventRecorderはmacOS 13+、48kHz stereo、ffmpeg MP3変換。
- 既存停止処理はstream停止後にscreen/audio outputを解除し、serial queueをdrainする。
- 基準線:
  - `swift build`: 成功。
  - `./scripts/verify_capture_finalization.sh`: 成功。
  - `swift test`: Command Line Tools環境にXCTestがなく未実行。
  - workspace app: arm64。

## 未検証

- Teams各会議種別のAccessibility tree。
- window filter単独でTeams相手音声が取得できるか。
- 他アプリ通知音とTeams自身の通知音の混入。
- full screen、別Space、最小化、再接続時のwindow identity変化。

これらは実機Teams回帰まで成功扱いにしない。
