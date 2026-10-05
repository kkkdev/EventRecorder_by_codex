# 公開前の匿名化・漏えい防止

## 30秒サマリー

公開用ブランチは `codex/public-release-sanitized`。元の24コミットを順序・粒度・日時・件名を保持して匿名化した。元履歴はローカルに保持し、旧ブランチ・タグ・元オブジェクトDBは公開用リポジトリへコピーしていない。調査文書の実セッション識別子、端末固有情報、ローカル操作番号は全履歴で一般化した。

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
| Known | 利用者はGit氏名・メールの匿名化と元履歴の保持を選択した |
| Blocker | ローカル公開準備に未決定事項なし。push先は未設定で本作業の対象外 |
| Open-ended | 専用secret scannerとフルXcodeの検査は別のリリースゲート |
| Chosen default | 公開リポジトリ相当の厳しさ。匿名名は `EventRecorder contributors`、メールは `contributors@eventrecorder.invalid` |

実現可能性は `Yellow`。ローカルGitと標準ライブラリで履歴を再構成・検査できるが、秘密検出は網羅的な保証ではなく、フルXcodeテストも別途必要。

1. 隔離リポジトリに対象24コミットのtreeをコピーし、文書だけを一般化する。
2. author／committerを固定して親コミットを再接続する。不要な旧refや署名はコピーしない。
3. 記録混入防止と相対パスビルドを追加する。
4. 全公開履歴・ignoreルール・配布バイナリ・停止処理を検査して公開ブランチをローカルへ取り込む。

エラーが出た場合は公開を止める。元履歴は変更しないため、それを再調査元として保持できる。実データを検査fixtureへ流用しない。

## タスク計画

| タスク | コミット単位・受け入れ条件 | 利用モデル | effort |
| --- | --- | --- | --- |
| T1 履歴匿名化 | 既存24コミットを再構成し、本資料を1コミットで追加。匿名metadata、文書以外の同一性、元refの保持を検査 | inherit（親設定継承） | inherit（親設定継承） |
| T2 混入防止 | ignore、検査・回帰テスト、公開手順を1コミット。録画等が除外され合成fixtureが残ること | inherit（親設定継承） | inherit（親設定継承） |
| T3 配布ビルド | 相対ソースパス、バイナリ検査、結果を1コミット。arm64ビルドと個人パス・氏名0件 | inherit（親設定継承） | inherit（親設定継承） |
| 検査 | 各受け入れコマンドを直接実行し、結果だけを集計 | なし（ツール直接） | N/A |

履歴・データ公開の安全性判断を伴うため、親がレビューと受け入れを担当する。実効effort値はホストから取得できないため継承値以上の断定をしない。context-aware-packはSwift非対応で、文書・Gitオブジェクト・バイナリ中心のため不使用。新規依存・CI変更なし。

## 検査と公開手順

実manifestにはウィンドウ名、時刻等、`events.json`にはタイトル・会議URLが含まれ得る。音声、画像、rawデータ、`analyze_session_audio.sh`の生出力はIssue・PR・Releaseへ貼らない。絶対パス、セッション識別子、会議URL、ウィンドウ名を除去した必要最小限の説明と、合成fixtureを利用する。自動録画manifestのwindow titleが空でも、収録内容自体は機密データである。

元リポジトリには個人情報のある旧履歴が残る。送信先を確認するまでpushしない。`git push --all`、`--mirror`、旧タグ送信、`.git`丸ごとの配布は禁止。既存remoteの履歴と共通祖先がない可能性があるのでforce pushで解決しない。

追加コミットも匿名identityを使う。グローバル設定を変更せず、公開用リポジトリのlocal設定か、次の指定でコミットする。

```bash
git -c user.name='EventRecorder contributors' \
    -c user.email='contributors@eventrecorder.invalid' \
    -c commit.gpgsign=false commit
```

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

Context Compression: T1完了。元履歴は保持。T2/T3と最終検査が残る。push・既存アプリ・TCCは対象外。
