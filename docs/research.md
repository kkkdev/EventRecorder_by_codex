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
