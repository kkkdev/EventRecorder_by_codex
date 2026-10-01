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
- Apple `AXUIElementCopyAttributeValue`
  - <https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue>
- Apple `AXIsProcessTrustedWithOptions`
  - <https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions>
- Apple `CGWindowListCopyWindowInfo`
  - <https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:)>
- Apple `kCGWindowBounds`
  - <https://developer.apple.com/documentation/coregraphics/kcgwindowbounds>
- Apple `NSRunningApplication.runningApplications(withBundleIdentifier:)`
  - <https://developer.apple.com/documentation/appkit/nsrunningapplication/runningapplications(withbundleidentifier:)>
- Apple `NSWorkspace.willSleepNotification`
  - <https://developer.apple.com/documentation/appkit/nsworkspace/willsleepnotification>
- Apple local notification authorization
  - <https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications>
- Apple `UNUserNotificationCenter.add`
  - <https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/add(_:withcompletionhandler:)>
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

## 実装後確認（検証時）

- `SCContentFilter(desktopIndependentWindow:)`で自動録画の映像をTeams windowに限定した。
- Apple sampleと同じくwindowサイズを2倍してstream解像度を構成し、display fallbackを持たせていない。
- `AXIsProcessTrustedWithOptions`のpromptは非同期であり戻り値は即時許可を意味しないため、許可後にユーザーが監視toggleを再度ONにする導線とした。
- `NSWorkspace.shared.notificationCenter`の`willSleepNotification`から共通停止/finalizeへ接続した。
- microphone stream outputは追加せず、不要な`NSMicrophoneUsageDescription`も削除した。
- Accessibility treeの文字列は判定中だけ保持し、manifestやUnified Loggingへ出力しない。

確認済み:

- pure判定fixture: prejoin拒否、日本語/英語/短いLeaveラベル、複数候補拒否、2回連続判定。
- lifecycle fixture: 5秒猶予、取消後の同一会議抑止、二重開始抑止、3回消失後の停止理由。
- 旧manifest/settingsのdecode互換。
- workspace appのarm64ビルドと別PID起動。

未検証:

- 実Teamsのscheduled、Meet Now、1対1、グループ通話。
- Teams UI各版でのAX frameとCGWindow frameの対応。
- window filterによる相手音声、他アプリ通知音、Teams通知音の分離。
- 画面操作基盤がタイムアウトしたため、UIの視覚確認。
