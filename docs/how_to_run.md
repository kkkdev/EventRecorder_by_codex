# Event Recorder 実行手順（改訂版）

## 1. 前提
- macOS 13+
- `ffmpeg`（MP3変換で必須）
- Xcodeで開発する場合は Xcode 15+
- Xcode projectは生成物です。リポジトリには `project.yml` を保持し、必要な時に `xcodegen generate` で生成します。

```bash
brew install ffmpeg
```

## 2. ビルド
### 2.1 Xcode を使う場合
```bash
brew install xcodegen
xcodegen generate
open ./EventRecorder.xcodeproj
```

### 2.2 Xcode なしで `.app` を作る場合
```bash
./scripts/build_app.sh
open ./build/EventRecorder.app
```

Bundle ID 変更例:
```bash
BUNDLE_IDENTIFIER=com.example.eventrecorder ./scripts/build_app.sh
```

補足:
- `scripts/build_app.sh` は Bundle ID ベースの designated requirement で署名します。
- macOS権限が壊れた場合でも、公開リポジトリでは自動TCC reset用スクリプトを提供しません。必要な場合は利用者がシステム設定から再許可してください。
- 公開・診断資料共有前には [公開前の検査](publication.md) を実施してください。録画内容、実manifest、イベントURL、生の診断出力は公開しません。

## 3. 初回権限設定
1. アプリ起動。
2. 起動時に `Event Browser` が通常ウィンドウ（`about:blank`）で自動起動します。
3. `権限確認` を押す。
4. macOS の Screen Recording（環境によっては Screen & System Audio Recording）を許可。
5. 通知を使う場合は `通知許可をリクエスト` を押して許可。
6. Teams自動録画を使う場合は `Accessibility権限を確認` を押し、Event Recorderを許可。

## 4. 録画手順（手動）
1. `キャプチャ対象ウィンドウ` を選択。
2. 複数デスクトップ（Spaces）上のウィンドウを選ぶ場合は `全デスクトップを含める` をONにする。
3. `スクショ間隔(秒)`、`JPEG品質`、`音声ビットレート`、`保存先` を設定。
4. ブラウザを全画面化した場合は `対象更新` を押してから開始する（または再選択する）。
5. `開始` を押す。
6. 終了時に `停止` を押す。

出力先:
- `保存先/session_YYYYMMDD_HHMMSS/recording.mp3`（音声sampleがある場合）
- `保存先/session_YYYYMMDD_HHMMSS/recording_tmp.caf`（一時音声。変換失敗時も保持）
- `保存先/session_YYYYMMDD_HHMMSS/images/*.jpg`
- `保存先/session_YYYYMMDD_HHMMSS/manifest.json`

`manifest.json`には次の完了状態と診断が含まれます。

| `completionStatus` | 音声sample | MP3 | 状態 |
| --- | ---: | --- | --- |
| `completed` | 1件以上・非無音 | あり | 完了 |
| `completedWithWarnings` | 1件以上・無音 | あり | 警告付き完了 |
| `completedWithoutAudio` | 0件 | なし | 警告付き部分保存 |

- `audioDiagnostics`: `peakLevelDBFS` / `rmsLevelDBFS` / `nonSilentSampleCount`
- `captureDiagnostics`: video/audio callback数、audio write成功・失敗数、最初・最後のaudio PTS、sanitized error domain/code

また、現在は無音回避のため「選択ウィンドウが属するディスプレイ単位」で収録します。

## 5. Teams会議の自動録画

1. Event Recorderを手動で起動する。
2. Screen Recording、Accessibility、通知の各権限を確認する。
3. 保存先と録画品質を設定する。
4. `Teams会議への参加を検出して自動録画` をONにする。
5. Teamsでscheduled meeting、Meet Now、1対1通話、またはグループ通話へ参加する。
6. 検出後5秒間は `今回の自動録画を取消` で開始を取り消せる。
7. 退出、Teams終了、対象window消失、スリープで自動停止する。UIの `停止` でも停止できる。

自動録画の境界:

- 映像はTeams会議windowだけ。画面全体にはフォールバックしない。
- 音声はScreenCaptureKitがTeams filterへ配信するシステム音声。本人マイク用outputは追加しない。
- 会議名やwindow titleをログへ出さず、自動録画manifestにもwindow titleを保存しない。
- 外部サービスへの送信、Google連携、Notebook連携は行わない。
- 監視状態は保存せず、アプリ起動時は必ずOFF。ログイン項目も登録しない。

## 6. イベント手順（汎用URL）
1. `タイトル(任意)`、`URL`、`開始日時`、`終了日時` を入力して `イベント追加`。
2. `開始10分前` に通知を受け取る。
3. 通知の `開く` または一覧の `開く` / `全画面で開く` で専用ブラウザを表示。

補足:
- `開始10分前` が過去のイベントは「通知なし」で保存されます。
- URL は `http/https` のみ、`開始 < 終了` が必須です。

## 7. 既知の制限
- TeamsのUI更新や表示言語によりAccessibility判定を更新する必要があります。曖昧な場合は安全側で自動開始しません。
- Teams window filterで相手音声だけが安定して届くこと、他アプリ音が混入しないことは実会議での回帰確認が必要です。
- 音声sampleが届かない場合でも画像とmanifestは保存しますが、根本原因の特定には診断情報とUnified Loggingが必要です。
- DRM保護コンテンツ等は録音できない場合があります。

## 7.1 音声sampleが0件だった場合
停止時に `音声サンプルを取得できなかったため、MP3なしで画像と診断情報を保存しました。` と表示された場合、セッションは`completedWithoutAudio`です。MP3は生成されませんが、画像とmanifestは保存済みです。

この状態だけから「対象アプリで音声が再生されていなかった」とは断定できません。

確認手順:
1. `manifest.json`の`captureDiagnostics.audioSampleBufferCount`が`0`であることを確認する。
2. 同時刻のUnified Loggingでstream開始・停止エラーを確認する。
3. キャプチャ対象と音声再生状態を確認する。
4. 必要に応じてシステム設定からScreen Recording権限を再許可する。

## 7.2 音声sampleはあるが無音だった場合
停止時に `音声サンプルは取得できましたが無音を検出しました...` と表示された場合、MP3とmanifestは保存済みで、状態は`completedWithWarnings`です。

確認手順:
1. `manifest.json`の`captureDiagnostics.audioSampleBufferCount`が1件以上であることを確認する。
2. `audioDiagnostics.peakLevelDBFS`と`audioDiagnostics.nonSilentSampleCount`を確認する。
3. `システム設定 > プライバシーとセキュリティ > 画面収録（または Screen & System Audio Recording）`でEventRecorderを再許可する。
4. Chrome/Meet再起動後に再実行し、必要なら`./scripts/analyze_session_audio.sh <session_dir>`で波形レベルを確認する。

## 7.3 全画面化後に開始失敗する場合
`全画面化などで対象ウィンドウが変化したため開始できません。` と表示される場合は、対象ウィンドウIDが古くなっています。

確認手順:
1. ブラウザを全画面化した後に `対象更新` を押す。
2. `キャプチャ対象ウィンドウ` を再選択する。
3. その状態で `開始` する。

## 7.4 複数デスクトップで候補に出ない場合
別デスクトップ（Spaces）のウィンドウは既定状態では候補に出ないことがあります。

確認手順:
1. `全デスクトップを含める` をONにする。
2. `対象更新` を押して候補を再読み込みする。
3. 対象ウィンドウを再選択して `開始` する。

## 8. 検証コマンド
```bash
swift build
swift test
./scripts/verify_capture_finalization.sh
./scripts/verify_teams_presence.sh
./scripts/verify_teams_automation.sh
xcodegen generate
xcodebuild -project ./EventRecorder.xcodeproj -scheme EventRecorder -destination 'platform=macOS' build
./scripts/build_app.sh
file ./build/EventRecorder.app/Contents/MacOS/EventRecorder
codesign --verify --deep --strict ./build/EventRecorder.app
```

この環境では `swift test` が `XCTest not available` で失敗する場合があります。
また、`xcodebuild` はフルXcodeが選択されている環境で実行してください。

### 8.1 検証時 の音声保存修正確認結果

- `swift build`: 成功
- `swift test`: 未達（Command Line Tools環境で`XCTest not available`）
- `./scripts/verify_capture_finalization.sh`: 成功
- `xcodegen generate`: 成功
- `xcodebuild -project ./EventRecorder.xcodeproj -scheme EventRecorder -destination 'platform=macOS' build`: 未達（フルXcode未導入）
- `./scripts/build_app.sh`: 成功
- `file ./build/EventRecorder.app/Contents/MacOS/EventRecorder`: `Mach-O 64-bit executable arm64`
- `codesign --verify --deep --strict ./build/EventRecorder.app`: 成功
- workspace appの起動スモーク: 成功
- no-audio fixtureと既存の正常音声セッションに対する診断script: 成功
- Unified Logging predicate: 成功。固定subsystemのエラーをdomain/codeで取得できた
- workspace arm64 appで既知音源を使う10回連続録画: 全10件`completed`、非空MP3/JPEG/manifest、audio write失敗0
- 音を再生しない状態の3回録画: OSが全ゼロsampleを配信し、全3件`completedWithWarnings`、MP3/JPEG/manifest保存
- 停止連打: stop/finalizeが各1回だけ実行され、`completed`
- 対象PIDのUnified Logging監査: error、window title、URL、保存先絶対pathはいずれも0件

未達:

- フルXcode環境でのXCTestとxcodebuild

上記を未達のリリースゲートとして扱い、最終完了とは判定しません。実録画の詳細は`docs/research.md`のT5を参照してください。

### 8.2 検証時 のTeams自動録画確認結果

- `swift build`: 成功
- `./scripts/verify_capture_finalization.sh`: 成功
- `./scripts/verify_teams_presence.sh`: 成功
- `./scripts/verify_teams_automation.sh`: 成功
- `./scripts/build_app.sh`: 成功
- app binary: arm64
- `codesign --verify --deep --strict`: 成功
- `xcodegen generate`: 成功
- `xcodebuild`: 未達（active developer directoryがCommand Line Tools）
- 外部送信、本人マイク、login item実装の静的監査: 該当なし
- workspace appの別PID起動スモーク: 成功
- UI画面取得: 未達（画面操作基盤がタイムアウト）
- `swift test`: 未達（Command Line Tools環境でXCTest利用不可）
- 実Teams会議4種、相手音声、他アプリ音分離: 未達

未達項目は成功扱いにせず、実機リリースゲートとして残します。

## 9. UI自動テスト（ローカル）
UIテストターゲットを含むプロジェクトを生成して実行します。

```bash
xcodegen generate
xcodebuild -project ./EventRecorder.xcodeproj -scheme EventRecorder -destination 'platform=macOS' -only-testing:EventRecorderUITests test
```

対象シナリオ:
- `全画面で開く` のクラッシュ回帰
- URLバリデーションエラー表示
- イベント追加/削除の基本導線

## 10. セッション音声の診断コマンド
既存セッションの無音判定をCLIで確認できます。

```bash
./scripts/analyze_session_audio.sh /Users/<your-user>/Movies/EventRecorder/session_YYYYMMDD_HHMMSS
```

出力される主な指標:
- `mean_volume` / `max_volume`（`volumedetect`）
- `sample_count` / `nonSilentSampleCount`（`manifest.json` の `audioDiagnostics`）
- `completionStatus`
- `videoSampleBufferCount`（描画可能sample）/ `audioSampleBufferCount`（audio callback）
- `audioWriteSuccessCount` / `audioWriteFailureCount`
- `firstAudioSamplePTSSeconds` / `lastAudioSamplePTSSeconds`
- sanitized `audioWriteError` / `streamStopError`

音声ファイルがない`completedWithoutAudio`セッションでも、manifestの診断は表示できます。no-audio fixtureでの確認例:

```bash
./scripts/analyze_session_audio.sh ./scripts/fixtures/no_audio_session
```

Unified Logging:

```bash
log show --last 10m --style compact \
  --predicate 'subsystem == "io.github.eventrecorder.capture"'
```

ログにはウィンドウタイトル、URL、保存先絶対パスを出さず、固定イベント名、整数カウンタ、sanitized error domain/codeだけを記録します。

## 11. 利用上の注意
- 録画・録音の実行前に、関係者の同意、法令、サービス利用規約、所属組織のルールを利用者自身で確認してください。
- DRM保護コンテンツやサービス規約で録画・録音が禁止されているコンテンツには使用しないでください。
