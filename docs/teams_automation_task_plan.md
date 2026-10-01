# Teams 会議自動録画 タスク計画

## 30秒サマリー

既存の手動録画と安全なfinalize処理を保ったまま、Teams実参加検出、window限定capture、取消猶予、自動停止を追加する。外部送信、本人マイク、ログイン時常駐は含めない。

## Sources Used

- `docs/teams_automation_design.md`
- 現行capture lifecycleとテスト群
- Apple ScreenCaptureKit / Accessibility API

## タスク一覧

### T1 設計と調査記録

- 設計、決定事項、検証マトリクスを追加する。
- 完了条件: 非対象とYellowリスクが明記されている。
- コミット: `docs(teams): define local-only automatic capture`

### T2 参加判定domain

- AX snapshotから参加状態を判定するpure domainを追加する。
- Teams bundle ID、退出操作、補助証拠、連続判定を扱う。
- prejoin、lobby、home、joined、英語・日本語fixtureを追加する。
- 完了条件: process/calendar単独では参加扱いにならない。
- コミット: `feat(teams): detect confirmed meeting participation`

### T3 window限定capture

- capture modeを導入し、Teams自動モードはdesktop-independent window filterを使用する。
- display fallbackを禁止し、window解像度を使用する。
- manifestへscopeとtriggerをoptional追加する。
- 完了条件: filter選択をpure policyでテストでき、Teamsモードにdisplay fallbackがない。
- コミット: `fix(capture): restrict capture to teams meeting window`

### T4 自動ライフサイクル

- Accessibility adapter、Teams monitor、automation coordinatorを追加する。
- 5秒取消猶予、自動開始、退出・対象消失・Teams終了での自動停止を実装する。
- 手動開始・停止を維持する。
- 完了条件: 二重start/stopを防ぎ、monitor停止時にtaskやobserverが残らない。
- コミット: `feat(teams): automate meeting capture lifecycle`

### T5 UI・権限・回復

- Accessibility権限案内、監視toggle、取消UI、状態表示を追加する。
- login itemは追加しない。
- sleep通知をstopへ接続する。
- 完了条件: 権限拒否時に自動録画せず、手動機能が利用できる。
- コミット: `feat(app): expose teams automation controls`

### T6 運用資料と統合検証

- README、実行手順、診断手順を更新する。
- `swift build`、verifier、app build、静的外部送信検査を実行する。
- 実機Teams検証ができない項目は未達として残す。
- コミット: `docs(teams): document local automation verification`

## 決定的ゲート

- `swift build`
- フルXcode環境で`swift test`
- `./scripts/verify_capture_finalization.sh`
- `./scripts/build_app.sh`
- app binaryがarm64
- `rg`でGoogle、Notebook、Graph、URLSession、外部upload実装が追加されていないこと
- 旧manifest fixtureがdecode可能であること

## 実機ゲート

- scheduled、Meet Now、1対1、グループ通話で開始・停止。
- 参加前、lobby、Teams起動だけでは開始しない。
- 5秒以内の取消でsessionを作らない。
- 画像にTeams会議window外が含まれない。
- 他アプリ通知音が入らない。
- Teams通知音の混入範囲を記録する。
- 退出、window消失、Teams終了、sleepで成果物を保持する。

## ロールバック

- Teams自動録画toggleをOFFにすれば既存の手動録画へ戻れる。
- capture modeはmanual/displayとteams/windowを分離し、既存手動経路を置換しない。
- manifest追加項目はoptionalとし、旧出力との互換性を維持する。

## レビュー 1/5〜5/5

- 1/5 粒度: docs、domain、capture、coordinator、UI、運用の6コミット。
- 2/5 依存: T2→T3→T4→T5、T6は全体後。
- 3/5 テスト: pure domainをSwiftPM対象にし、CLT環境でもbuild可能にする。
- 4/5 安全: fallback禁止、外部送信なし、manual rollbackあり。
- 5/5 完了条件: 自動ゲートと実機ゲートを分離し、未実施を成功扱いにしない。

## Context Compression

6コミットで参加判定、window限定capture、自動ライフサイクル、UI、運用を追加する。既存手動録画をrollback経路として残し、実機Teams音声とUI変動はリリースゲートにする。
