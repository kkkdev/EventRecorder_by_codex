# 停止時の音声保存失敗 調査ログ

## 30秒サマリー

- 失敗時の直接条件は、最初の正常な音声appendがなく`recording_tmp.caf`が存在しないこと。
- 過去の失敗セッションはdiagnosticsもUnified Loggingも残さないため、無音・framework未配信・書込失敗を区別できない。
- ScreenCaptureKitのfilter、48kHz stereo、AVAudioFile経路は正常セッションで動作しており、全面置換せず停止順序と観測性を修正する。
- ユーザー選択により、音声0件はMP3なしの部分保存＋警告完了とする。

## ローカル証跡

### 検証時 セッション

| session | CAF | MP3 | manifest | 結果 |
| --- | --- | --- | --- | --- |
| `Session-A` | なし | なし | なし | 音声0件相当 |
| `Session-B` | 非空 | 非空 | あり | 正常 |
| `Session-C` | なし | なし | なし | 音声0件相当 |
| `Session-D` | なし | なし | なし | 音声0件相当 |

正常セッション:

- PCM float32 little-endian
- sample rate 48,000Hz
- channels 2
- CAF durationは有限の正数
- `sampleCount > 0`
- `nonSilentSampleCount > 0`
- `peakLevelDBFS`は有限値
- `rmsLevelDBFS`は有限値

### 実行環境

- macOS 13以降の対応環境
- Apple Silicon / arm64
- 実行中`/Applications/EventRecorder.app`: 以前ビルドされたx86_64
- workspace `build/EventRecorder.app`: 実行中アプリとはbinary hashが異なる
- 実行中アプリのstdout/stderr: `/dev/null`
- Swift 5.10 / Command Line Tools
- `swift build`: 調査時成功
- `swift test`: `XCTest not available`

## 一次資料・公式資料

1. Apple: ScreenCaptureKit
   - <https://developer.apple.com/documentation/screencapturekit>
   - streamが画面・音声sampleを`CMSampleBuffer`として渡す基本仕様を確認。
2. Apple: Capturing screen content in macOS
   - <https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos>
   - audio/video出力を個別のsample handler queueへ追加する公式構成を確認。
3. Apple: Meet ScreenCaptureKit, WWDC22
   - <https://developer.apple.com/videos/play/wwdc2022/10156/>
   - `startCapture`後、sampleが利用可能になった時にcallbackされることを確認。
4. Apple: `SCStreamConfiguration`
   - <https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration>
   - capturesAudio、sampleRate、channelCountの責務を確認。
5. Apple: `capturesAudio`
   - <https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/capturesaudio>
   - audio captureが明示的なopt-inであることを確認。現行実装はtrue設定済み。
6. Apple: `channelCount`
   - <https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/channelcount>
   - mono/stereo対応を確認。現行2ch設定は有効。
7. Apple: `stopCapture`
   - <https://developer.apple.com/documentation/screencapturekit/scstream/stopcapture%28completionhandler%3A%29>
   - stop完了が停止エラーを返すAPIであることを確認。
8. Apple: `removeStreamOutput`
   - <https://developer.apple.com/documentation/screencapturekit/scstream/removestreamoutput%28_%3Atype%3A%29>
   - 停止時に出力destinationを明示解除できることを確認。
9. Apple: `SCStreamDelegate`
   - <https://developer.apple.com/documentation/screencapturekit/scstreamdelegate>
   - streamの異常停止をdelegateで受け取る経路を確認。
10. Apple: `CMSampleBufferCopyPCMDataIntoAudioBufferList`
    - <https://developer.apple.com/documentation/coremedia/cmsamplebuffercopypcmdataintoaudiobufferlist%28_%3Aat%3Aframecount%3Ainto%3A%29>
    - PCMでない、data未準備、buffer不整合で失敗し得るため、append failure counterが必要。
11. Apple: `AVAudioFile`
    - <https://developer.apple.com/documentation/avfaudio/avaudiofile>
    - AVAudioPCMBufferを順次書き込む既存方式が適合することを確認。
12. Apple: Generating Log Messages from Your Code
    - <https://developer.apple.com/documentation/os/generating-log-messages-from-your-code>
    - subsystem/category、notice/errorの永続性、privacy指定を確認。
13. Apple: `OSLogPrivacy`
    - <https://developer.apple.com/documentation/os/oslogprivacy>
    - dynamic user dataをprivateにする方針を確認。
14. Chromium: ScreenCaptureKit audio loopback implementation
    - <https://chromium.googlesource.com/chromium/src/+/HEAD/media/audio/mac/audio_loopback_input_mac_impl.mm>
    - display filter、48kHz、serial queue、stopとoutput解除を分離する実装例を確認。

## 今回の設計・実装に影響したポイント

1. `startCapture()`の成功を音声sample受信成功として扱わない。
2. ScreenCaptureKitのoutput callback queueとwriter queueを停止時に明示的にdrainする。
3. callback受信数とappend成功・失敗数を分け、CAF不在の理由を次回から分類可能にする。
4. display filterと48kHz stereoは公式・実装例・正常セッションに整合するため維持する。
5. `print`ではFinder起動時にログが失われるため、Unified Loggingのnotice/errorへ移行する。
6. ログにはwindow title、URL、絶対pathを含めず、domain/codeと整数カウンタだけを残す。
7. 音声0件を無音MP3へ変換せず、manifestの明示statusで部分保存する。

## タスク別追記

### T1 設計・タスク計画

- 上記14資料とローカル証跡を設計へ反映した。
- Blockerはなく、FeasibilityはXCTest制約を理由にYellowとした。
- ユーザー選択の「部分保存＋警告」を保存契約へ固定した。

### T2 診断基盤とmanifest後方互換

- `CaptureManifest.audioFileName`をoptional化し、旧JSONで欠ける新フィールドもdecodeできる設計にした。
- callback数、audio write成功・失敗、最初・最後の有限PTS、最初のwrite/stop errorを保持する診断型を追加した。
- errorはlocalized descriptionを保存せず、文字種と長さを制限したdomainとcodeだけへ変換する。
- capture経路の`print`を固定subsystem/categoryのUnified Loggingへ置換した。
- `swift build`: 成功。
- `./scripts/build_app.sh`: 成功。
- `swift test`: Command Line Tools環境のため`XCTest not available`。追加テストは未実行であり、フルXcode環境のリリースゲートとして残る。

### T3 停止排他・queue drain・部分保存

- `CaptureState.canStop`とfinalization gateにより、停止開始を`.capturing`中の1回へ限定した。
- `SCStream.stopCapture`後にscreen/audio outputを解除し、両方のserial sample queueをdrainしてからcallbackとwriterを閉じる。
- audio sample 0件はtranscodeせず、`audioFileName: nil`、`completedWithoutAudio`のmanifestを保存する。
- silent sampleはMP3を生成して`completedWithWarnings`、非無音は`completed`とする。
- 最初のappend errorをstream/no-audio判断より優先し、実エラー時もCAF・画像を削除せずbest-effort manifestを残す。
- user stop、append、stream、finalizeのログは固定メッセージとsanitized domain/code、整数カウンタだけを使用する。
- `swift build`: 成功。
- `./scripts/build_app.sh`: 成功。現行scriptが`/usr/bin/env bash`からx86_64 Homebrew bashを選ぶため生成物はx86_64となり、arm64化はT4の検証script修正で対応する。
- `swift test`: `XCTest not available`のため未実行。

### T4 運用資料・診断script・結合確認

- `scripts/build_app.sh`をnative `/bin/bash`へ固定し、Bash 3互換のsource列挙へ変更した。
- 変更後の直接buildはarm64、ad-hoc署名のidentifierは`io.github.eventrecorder.EventRecorder`、`codesign --verify --deep --strict`は成功した。
- workspace appを別プロセスで起動し、3秒以上生存することを確認後、そのPIDだけをTERMで終了した。
- `scripts/analyze_session_audio.sh`はoptional `audioFileName`、`completionStatus`、`captureDiagnostics`を表示し、音声ファイルがないセッションではffmpegを要求しない。
- no-audio fixture: `completedWithoutAudio`、audio callback/write 0、音声ファイルなしを表示して成功した。
- 既存正常セッション`Session-B`: 旧manifestを読めた。CAFは48kHz stereo、非無音sample、MP3は非空で診断成功した。
- `/usr/bin/log show --last 10m --style compact --predicate 'subsystem == "io.github.eventrecorder.capture"'`: 成功。起動スモーク時のScreenCaptureKit errorをsanitized domain/codeで取得し、title、URL、保存先pathは含まれなかった。
- `swift build`: 成功。
- `swift test`: 未達。`XCTest not available`。
- `xcodegen generate`: 成功。
- `xcodebuild ... build`: 未達。active developer directoryがCommand Line Toolsで、フルXcodeが存在しない。
- `./scripts/build_app.sh`: 成功。
- `file ./build/EventRecorder.app/Contents/MacOS/EventRecorder`: `Mach-O 64-bit executable arm64`。
- `codesign --verify --deep --strict ./build/EventRecorder.app`: 成功。
- 実録画回帰: 未達。起動スモーク時にScreenCaptureKitのpermission error code `-3801`を確認しており、TCC権限変更は自動実行していない。
- リリース判定: Yellowのまま。フルXcodeの自動テストと実音声/TCCを使う回帰が完了するまで、計画上の完了扱いにしない。
