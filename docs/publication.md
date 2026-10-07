# 公開前の匿名化・漏えい防止

## 30秒サマリー

公開用ブランチは `main`（旧名 `codex/public-release-sanitized`）。元の24コミットを順序・粒度・日時・件名を保持して匿名化した。匿名化時には元ブランチを保持したが、その後の利用者指示で旧4ブランチを削除し、現在のローカルブランチは `main` のみ。旧ブランチ・タグ・元オブジェクトDBは隔離公開用リポジトリへコピーしていない。調査文書の実セッション識別子、端末固有情報、ローカル操作番号は全履歴で一般化した。

この工程はソース公開準備であり、録画仕様・公開API・manifest形式は変更しない。インストール済みアプリ、TCC、実録画データを変更せず、外部pushもしない。

## 目次

- [設計と前提](#設計と前提)
- [タスク計画](#タスク計画)
- [検査と公開手順](#検査と公開手順)
- [調査根拠](#調査根拠)
- [レビューと検証結果](#レビューと検証結果)

## 設計と前提

| 分類 | 内容 |
| --- | --- |
| Known | 利用者はGit氏名・メールの匿名化を選択。その後、公開用をmainとし旧ブランチを削除する指示へ更新した |
| Blocker | ローカル公開準備に未決定事項なし。push先は未設定で本作業の対象外 |
| Open-ended | 専用secret scannerとフルXcodeの検査は別のリリースゲート |
| Chosen default | 公開リポジトリ相当の厳しさ。匿名名は `EventRecorder contributors`、メールは `contributors@eventrecorder.invalid` |

実現可能性は `Yellow`。ローカルGitと標準ライブラリで履歴を再構成・検査できるが、秘密検出は網羅的な保証ではなく、フルXcodeテストも別途必要。

1. 隔離リポジトリに対象24コミットのtreeをコピーし、文書だけを一般化する。
2. author／committerを固定して親コミットを再接続する。不要な旧refや署名はコピーしない。
3. 記録混入防止と相対パスビルドを追加する。
4. 全公開履歴・ignoreルール・配布バイナリ・停止処理を検査して公開ブランチをローカルへ取り込む。

エラーが出た場合は公開を止める。旧ブランチ削除後もGitオブジェクトは物理消去していないが、GC等で失われる可能性があるため恒久バックアップとは扱わない。実データを検査fixtureへ流用しない。

## タスク計画

| タスク | コミット単位・受け入れ条件 | 利用モデル | effort |
| --- | --- | --- | --- |
| T1 履歴匿名化 | 既存24コミットを再構成し、本資料を1コミットで追加。匿名metadata、文書以外の同一性、元refの保持を検査 | inherit（親設定継承） | inherit（親設定継承） |
| T2 混入防止 | ignore、検査・回帰テスト、公開手順を1コミット。録画等が除外され合成fixtureが残ること | inherit（親設定継承） | inherit（親設定継承） |
| T3 配布ビルド | 相対ソースパス、バイナリ検査、結果を1コミット。arm64ビルドと個人パス・氏名0件 | inherit（親設定継承） | inherit（親設定継承） |
| T4 ローカルブランチ整理 | 利用者指示でmainへ改名し旧4ブランチを削除。文書同期を1コミット。mainのみ・公開検査成功を確認 | inherit（親設定継承） | inherit（親設定継承） |
| 検査 | 各受け入れコマンドを直接実行し、結果だけを集計 | なし（ツール直接） | N/A |

履歴・データ公開の安全性判断を伴うため、親がレビューと受け入れを担当する。実効effort値はホストから取得できないため継承値以上の断定をしない。context-aware-packはSwift非対応で、文書・Gitオブジェクト・バイナリ中心のため不使用。新規依存・CI変更なし。

## 検査と公開手順

実manifestにはウィンドウ名、時刻等、`events.json`にはタイトル・会議URLが含まれ得る。音声、画像、rawデータ、`analyze_session_audio.sh`の生出力はIssue・PR・Releaseへ貼らない。絶対パス、セッション識別子、会議URL、ウィンドウ名を除去した必要最小限の説明と、合成fixtureを利用する。自動録画manifestのwindow titleが空でも、収録内容自体は機密データである。

元リポジトリでは旧ブランチを削除したが、個人情報のある旧Gitオブジェクトが残り得る。送信先を確認するまでpushしない。送信refは `main` に限定し、`git push --all`、`--mirror`、旧タグ送信、`.git`丸ごとの配布は禁止。既存remoteの履歴と共通祖先がない可能性があるのでforce pushで解決しない。

追加コミットも匿名identityを使う。グローバル設定を変更せず、公開用リポジトリのlocal設定か、次の指定でコミットする。

```bash
git -c user.name='EventRecorder contributors' \
    -c user.email='contributors@eventrecorder.invalid' \
    -c commit.gpgsign=false commit
```

```bash
python3 scripts/test_publication.py
python3 scripts/verify_publication.py --ref HEAD
```

指定refの全commit metadata・全blob・各treeの全path、現在のignoreルール、合成fixtureの追跡を検査する。別リポジトリの元identityも検査する場合は `--private-source-repo <local-source-repo>` を追加する。検出値や個人pathは出力せず、categoryとobject IDのみを返す。終了0は検査通過、1は検出、2は検査不能で、1/2とも公開を止める。

検査はコミット後に実行する。未コミット・ignoredデータ、Git reflogや不要ref、未知のtoken形式、画像内の情報は網羅しない。外部へ送るrefを必ず限定し、未検査ファイルをReleaseへ添付しない。

配布アプリの実行ファイルも検査する。元identityも検査する場合は同じ `--private-source-repo` を追加する。

```bash
./scripts/build_app.sh
python3 scripts/verify_publication.py --binary build/EventRecorder.app/Contents/MacOS/EventRecorder
codesign --verify --deep --strict build/EventRecorder.app
```

直接ビルドではソース列挙を相対pathへ変換し、リポジトリをcwdとしてswiftcを呼ぶ。出力先は従来どおり。単なるfile-prefix-mapでは個人pathが残ることを隔離ビルドで確認したため採用しない。署名identifier・macOS 13 target・アーキテクチャ判定は変更しない。Xcodeのビルド・dSYM・その他Release添付物は別途検査し、直接ビルドの結果だけで安全と断定しない。

## 調査根拠

公開データは送信せず、Git公式仕様を確認した。確認日: 2026-10-05。

- [commit-tree](https://git-scm.com/docs/git-commit-tree): metadataと親を指定して新しいcommitを作成する。
- [cat-file](https://git-scm.com/docs/git-cat-file): commitとblobの内容検査。
- [mktree](https://git-scm.com/docs/git-mktree): 元mode・tree構造を保持して再構成。
- [hash-object](https://git-scm.com/docs/git-hash-object): blob同一性の検査。
- [rev-list](https://git-scm.com/docs/git-rev-list): 指定refに到達可能な全履歴を列挙。
- [fetch](https://git-scm.com/docs/git-fetch): 匿名ブランチだけのローカル取り込み。
- [push](https://git-scm.com/docs/git-push): refを限定して公開する。今回pushは未実施。
- [gitignore](https://git-scm.com/docs/gitignore): ignoreは既にtrackedな情報を除去しない。
- [config](https://git-scm.com/docs/git-config): 匿名identityをlocal設定へ限定。
- [update-ref](https://git-scm.com/docs/git-update-ref): 元refを置換せず新refを作る。

## レビューと検証結果

設計レビュー: 1/5 要件整合、2/5 unknown、3/5 入出力・失敗時停止、4/5 検査・DoD、5/5 可読性はいずれもpass。
計画レビュー: 1/5 コミット粒度、2/5 T1→T2→T3の順序、3/5 検査とモデル指定、4/5 調査根拠、5/5 元履歴保持はいずれもpass。

T1: 24コミットを再構成。全24件でauthor／committerを匿名化。文書以外の488オブジェクト比較で変更なし。元ref・作業ツリーは不変。個人値は検査結果へ出力しない。

T1自己レビュー: 1/5 対象履歴の限定、2/5 tree・親・mode保持、3/5 同一性検査、4/5 文書一般化、5/5 目的外差分なしはpass。

Markdownの目次・見出し・表・フェンスを静的確認する。mdtsは環境に見つからず、新規依存を取得しないためブラウザpreviewは未実施。本資料は4項目の番号手順で足りるため新規Mermaid図を設けない。

Context Compression: T1〜T3の実装・ローカル検証完了。元履歴は保持。push・インストール済みアプリ・TCCは対象外。フルXcodeとブラウザpreviewは未達。

T2: 録画セッション・音声動画・鍵証明書・イベント・raw/診断/撮影ディレクトリをignoreに追加。公開画像と合成no-audio manifestは対象外。検査scriptと合成回帰テストを追加した。履歴で削除済みのsecret、非匿名metadata、同一blobの別pathも検査する。

T2自己レビュー: 1/5 設計一致、2/5 過去blobと複数pathの網羅、3/5 合成テストと検出値非出力、4/5 README・運用手順同期、5/5 依存・CI・録画仕様不変はpass。検査用正規表現そのものをpathと誤判定するケースを修正し、自己検査を含むPython回帰8ケース成功。公開前の全履歴検査はコミット後に再実行する。

T3自己レビュー: 1/5 相対ソースpathと既存出力先の維持、2/5 repo外cwdからの呼出し、3/5 旧バイナリを拒否し新バイナリを許可、4/5 README・実行手順同期、5/5 app source・署名identifier・CI不変はpass。ビルド時に検査が失敗した場合は署名前に終了する。

| 実行した検査 | 結果 |
| --- | --- |
| `python3 scripts/test_publication.py` | 8ケース成功 |
| `python3 scripts/verify_publication.py --ref HEAD`（元identity追加検査付き） | 匿名metadata、全公開blob/path、ignore、fixtureの検査成功 |
| `/bin/bash -n scripts/build_app.sh` | 成功 |
| `./scripts/build_app.sh`（repo内・repo外cwd） | 両方成功 |
| 配布バイナリ検査（元identity追加検査付き） | 個人path・氏名・秘密情報の検出0件 |
| 修正前のバイナリ検査 | 個人pathとidentityを検出し、終了1。検出値は非出力 |
| `file build/EventRecorder.app/Contents/MacOS/EventRecorder` | arm64 Mach-O |
| `codesign --verify --deep --strict build/EventRecorder.app` | 成功 |
| `swift build` | 成功 |
| `./scripts/verify_capture_finalization.sh` | 成功 |
| `./scripts/verify_teams_presence.sh` | 成功 |
| `./scripts/verify_teams_automation.sh` | 成功 |
| `swift test` | 終了1、`XCTest not available`。フルXcodeが必要 |
| Markdown fence検査 | 8資料で成功。ブラウザpreviewは未実施 |

最終レビュー: 1/5 対象ゲート、2/5 CLIとビルドの最小実行、3/5 文書と生成appの同期、4/5 未達を含む報告、5/5 秘密検出・Xcode・previewの制限明記はpass。
最終3パス: 要求充足（元履歴保持・公開範囲限定）、技術品質（回帰・ビルド・差分）、セキュリティ/運用（外部pushなし・権限変更なし）を確認した。本作業の検査通過を、実会議回帰やフルXcodeを含む製品全体のリリース合格とは扱わない。

### T4 ローカルブランチ整理

利用者の明示指示に従い、公開用ブランチを `main` へ改名し、`master`、`codex/event-recorder-v0`、`backup/master-before-history-rewrite`、`codex/rewrite-master-readable-history` を削除した。対象ref・commit ID・作業ツリー・worktreeを事前確認した。アプリソース、録画データ、インストール済みアプリ、TCC、リモートは変更していない。旧Gitオブジェクトの物理消去やpruneは実施していない。

自己レビュー: 1/5 指示対象の限定、2/5 main先端の維持、3/5 全公開履歴検査、4/5 ブランチ名の文書同期、5/5 目的外変更なしを確認。文書の目次・見出し・表・フェンスを静的確認し、既存環境制約によりブラウザpreviewは未実施。最終状態はmainのみ、作業ツリーcleanを完了条件とする。
