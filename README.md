# Event Recorder

macOS 13+ 専用のローカルGUIアプリです。Windows は対象外です。以下を提供します。

- 手動開始/手動停止の録画（自動開始/自動停止なし）
- 対象アプリのウィンドウを選択（録画対象ディスプレイ解決に利用）
- 内部音声を収録し、sampleがある場合は停止時に MP3 へ変換（`ffmpeg` 必須）
- 音声sampleが0件でも、画像と診断manifestを警告付きで部分保存
- Meet/Chrome の無音対策として、音声収録は display フォールバックで安定化
- 一定間隔でJPEGスクリーンショット保存（0.5〜120秒）
- 汎用イベント管理（`URL / 開始日時 / 終了日時`）
- イベント開始10分前のローカル通知
- 専用ブラウザウィンドウでURLを開く/全画面表示

## ドキュメント
- 実行手順: `./docs/how_to_run.md`
- Teams自動録画設計: `./docs/teams_automation_design.md`
- Teams自動録画タスク計画: `./docs/teams_automation_task_plan.md`
- Teams自動録画調査: `./docs/teams_automation_research.md`
- 脆弱性報告: `./SECURITY.md`
- コントリビューション: `./CONTRIBUTING.md`

## クイックスタート
```bash
brew install ffmpeg xcodegen
xcodegen generate
open ./EventRecorder.xcodeproj
```

## Xcode なしでビルド
```bash
./scripts/build_app.sh
open ./build/EventRecorder.app
```

Bundle ID を変更する場合:
```bash
BUNDLE_IDENTIFIER=com.example.eventrecorder ./scripts/build_app.sh
```

## 出力構造
`保存先/session_YYYYMMDD_HHMMSS/`

- `recording.mp3`（音声sampleがある場合）
- `recording_tmp.caf`（音声の一時ファイル。変換失敗時も削除しません）
- `images/img_000001.jpg` 以降
- `manifest.json`
  - `completionStatus`
    - `completed`: 音声あり・MP3保存完了
    - `completedWithWarnings`: sampleはあるが無音・MP3保存完了
    - `completedWithoutAudio`: sampleが0件・MP3なしの部分保存
  - `audioDiagnostics`（`peakLevelDBFS` / `rmsLevelDBFS` / `nonSilentSampleCount`）
  - `captureDiagnostics`（描画可能video sample数、audio callback数、audio write成否、audio PTS、sanitized error）

補足:
- 現在は Chrome Meet の無音回避のため、選択ウィンドウが属するディスプレイ単位で収録します。
- `completedWithoutAudio`は「音声が再生されていなかった」とは断定しません。`captureDiagnostics`とUnified Loggingで、sample未配信と書込失敗を切り分けてください。

既存セッションを診断する場合:
```bash
./scripts/analyze_session_audio.sh /Users/<your-user>/Movies/EventRecorder/session_YYYYMMDD_HHMMSS
```

## 自動テスト
ユニットテスト:
```bash
swift test
```

Command Line Toolsだけでも実行できる停止/finalize検証:
```bash
./scripts/verify_capture_finalization.sh
```

UIテスト（ローカル実行）:
```bash
xcodegen generate
xcodebuild -project ./EventRecorder.xcodeproj -scheme EventRecorder -destination 'platform=macOS' -only-testing:EventRecorderUITests test
```

## 注意事項
- 画面収録・音声収録・通知は macOS の権限許可が必要です。
- sampleありの無音は失敗にせず、MP3を保存して警告を表示します。
- sampleが0件の場合も失敗にせず、MP3なしで画像とmanifestを保存して警告を表示します。
- append、stream停止、ffmpeg、manifest書込の実エラーは失敗のまま扱い、生成済みCAF・画像を保持します。
- 録画・録音の実行前に、関係者の同意、法令、サービス利用規約、所属組織のルールを利用者自身で確認してください。
- DRM保護コンテンツやサービス規約で録画・録音が禁止されているコンテンツには使用しないでください。

## ライセンス
MIT Licenseです。詳細は `./LICENSE` を参照してください。
