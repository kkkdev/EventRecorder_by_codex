# Event Recorder

macOS 13+ 専用のローカルGUIアプリです。Windows は対象外です。以下を提供します。

- 手動開始/手動停止の録画（自動開始/自動停止なし）
- 対象アプリのウィンドウを選択（録画対象ディスプレイ解決に利用）
- 内部音声を収録し、停止時に MP3 へ変換（`ffmpeg` 必須）
- Meet/Chrome の無音対策として、音声収録は display フォールバックで安定化
- 一定間隔でJPEGスクリーンショット保存（0.5〜120秒）
- 汎用イベント管理（`URL / 開始日時 / 終了日時`）
- イベント開始10分前のローカル通知
- 専用ブラウザウィンドウでURLを開く/全画面表示

## ドキュメント
- 実行手順: `./docs/how_to_run.md`
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

- `recording.mp3`
- `images/img_000001.jpg` 以降
- `manifest.json`
  - `audioDiagnostics`（`peakLevelDBFS` / `rmsLevelDBFS` / `nonSilentSampleCount`）

補足:
- 現在は Chrome Meet の無音回避のため、選択ウィンドウが属するディスプレイ単位で収録します。

既存セッションを診断する場合:
```bash
./scripts/analyze_session_audio.sh /Users/<your-user>/Movies/EventRecorder/session_YYYYMMDD_HHMMSS
```

## 自動テスト
ユニットテスト:
```bash
swift test
```

UIテスト（ローカル実行）:
```bash
xcodegen generate
xcodebuild -project ./EventRecorder.xcodeproj -scheme EventRecorder -destination 'platform=macOS' -only-testing:EventRecorderUITests test
```

## 注意事項
- 画面収録・音声収録・通知は macOS の権限許可が必要です。
- 停止時に無音判定（`audioDiagnostics.isSilent`）が true の場合、エラーメッセージを表示します。
- 録画・録音の実行前に、関係者の同意、法令、サービス利用規約、所属組織のルールを利用者自身で確認してください。
- DRM保護コンテンツやサービス規約で録画・録音が禁止されているコンテンツには使用しないでください。

## ライセンス
MIT Licenseです。詳細は `./LICENSE` を参照してください。
