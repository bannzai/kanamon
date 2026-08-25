# kanamon (カナモン)

ポケモンの名前でカタカナ・ひらがなの読みを練習する子ども向け iOS アプリ。TestFlight のみの個人利用で、App Store には公開しない (根拠: [ADR 0001](documents/adr/0001-pokemon-assets-testflight-personal-only.md))。

## 概要
@documents/PROJECT.md

## Xcode プロジェクト構成の変更

- `Kanamon.xcodeproj` をプロジェクト構成の唯一の正とする。XcodeGen と `project.yml` は使わず、`xcodegen generate` を実行しない
- ターゲット、ファイル、Build Settings、Build Phases、Scheme、Swift Package の変更は Xcode の GUI で行う。自動化が必要な場合は、プロジェクト構成を `Kanamon.xcodeproj/project.pbxproj`、Scheme を `Kanamon.xcodeproj/xcshareddata/xcschemes/*.xcscheme` で直接編集する
- 上記の機械検査は `~/.agents/skills/create-new-app/scripts/check-setup.sh` の `xcode-project-source` 項目で行える (project.yml が残っていると MISSING になる)
- 変更後は `git diff -- Kanamon.xcodeproj` で意図した差分だけであることを確認し、下記のビルドとテストを実行する

## 検証方法

- シミュレータビルド: `make build-ios` (ログは `./tmp/build.log` に保存し、全文を warning / error で検査する)
- ユニットテスト: `make test` (sim-boot で解決した simulator 上で実行する)
- 動作確認 (UI・挙動): sim-boot (`/sim-manager` skill) で起動した simulator へ `make ios` で install + launch する。UI 変更はスクリーンショットで描画を確認してから完了報告する
- ポケモンのデータは実行時に PokeAPI から取得する構成のため、初回の動作確認はネットワーク接続のある状態で行う。素材ファイルを検証用にリポジトリへ置かない (`.claude/rules/pokemon-assets-no-commit.md`)

<!-- ai-review-config begin -->
<!--
このブロックは自動生成です。直接編集せず、テンプレートを更新してから再生成してください。
内容は AI コードレビュー時の挙動指示であり、コードベース自体への規約ではありません。
-->

## レビュー時の応答スタイル

- 応答は日本語で行う

## レビュー範囲外

以下は自動レビューで指摘しない (別の検出経路があるため):

- コンパイルエラー・型エラー (ローカル/CI のビルドで検出される)
- Lint/フォーマット違反 (リンター・フォーマッターで検出される)
<!-- ai-review-config end -->
