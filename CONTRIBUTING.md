# Contributing

Event Recorderへのコントリビューションありがとうございます。

## 開発環境
- macOS 13+
- Swift 5.10+
- `ffmpeg`
- Xcode projectを使う場合は `xcodegen`

```bash
brew install ffmpeg xcodegen
swift build
swift test
xcodegen generate
```

## 変更前に確認すること
- 録画・録音機能はmacOS権限、同意、法令、サービス利用規約に関わります。仕様変更時はREADMEと実行手順の注意事項も更新してください。
- 秘密情報、個人情報、ローカル絶対パス、録画成果物、調査用rawデータをコミットしないでください。
- 生成物の `EventRecorder.xcodeproj/`、`.build/`、`build/` はコミット対象外です。

## Pull Request
1. 目的を1つに絞ってください。
2. 変更理由、確認コマンド、影響範囲を書いてください。
3. 可能な範囲で以下を実行してください。

```bash
swift build
swift test
xcodegen generate
xcodebuild -project ./EventRecorder.xcodeproj -scheme EventRecorder -destination 'platform=macOS' build
```

## Security
脆弱性や秘密情報漏えいの疑いは公開Issueに書かず、`SECURITY.md` の手順に従って報告してください。
