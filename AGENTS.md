# Repository Guidelines

## プロジェクト構成

`app.rb` は Sinatra のルーティングと HTTP 応答を担当します。主要ロジックは `lib/` に置き、プロジェクト探索は `project_registry.rb`、Compose コマンド生成とパス変換は `compose_runner.rb`、出力配信は `command_body.rb`、排他制御は `operation_registry.rb` に分離します。ブラウザ側の HTML、CSS、JavaScript は `web/`、Minitest は `test/` に配置します。設計判断や優先順位を変更する場合は `docs/product-overview.md` も更新してください。

## ビルド・テスト・開発コマンド

- `cp .env.example .env`: ローカル設定を作成し、`HOST_PROJECTS_ROOT` に macOS 上の絶対パスを指定します。
- `docker compose up --build -d`: イメージをビルドし、`http://localhost:8080` で起動します。
- `docker compose logs -f compose-pilot`: 開発中のアプリケーションログを追跡します。
- `docker compose down`: Compose Pilot 自体を停止します。
- `bundle install`: ホスト上でのテストに必要な gem を導入します。
- `bundle exec ruby -Itest -e 'Dir["test/*_test.rb"].sort.each { |f| require_relative f }'`: 全テストを実行します。
- `bundle exec ruby -Itest test/compose_runner_test.rb`: 単一テストファイルを実行します。

## コーディング規約

Ruby 3.4 を前提に、2 スペースインデント、ダブルクォート、ファイル先頭の `# frozen_string_literal: true` を使用します。ファイル名とメソッド名は `snake_case`、クラスとモジュールは `CamelCase`、真偽値メソッドは `?` で終えてください。外部コマンドはシェル文字列ではなく引数配列で組み立てます。フォーマッターやリンターは未導入のため、周辺コードに合わせます。コードコメントとドキュメントは日本語で記述します。

## テスト方針

テストには Minitest を使用します。ファイルは `*_test.rb`、クラスは `SomethingTest`、メソッドは `test_descriptive_behavior` の形式にします。正常系に加え、パス逸脱、不正なサービス、多重実行など主要な異常系を検証してください。実プロジェクトや Docker デーモンを変更せず、一時ディレクトリやスタブを利用します。

## コミットとプルリクエスト

履歴は少なく、厳密なコミット規約はまだありません。1 コミットを1つの論理変更に絞り、`サービス別ログ表示を追加` のように短く具体的な件名を付けます。ブランチ名は `feature/service-logs` や `fix/invalid-project-root` を推奨します。PR には目的、利用者への影響、確認コマンド、関連 Issue を記載し、`web/` の変更にはスクリーンショットを添付してください。

## セキュリティと完了条件

`.env`、認証情報、生成された override ファイルはコミットしません。Docker ソケットをマウントするため、公開先は `127.0.0.1` に限定します。元の Compose ファイルを変更せず、`PROJECTS_ROOT` 外へのアクセスと危険な多重実行を防いでください。変更完了前にテストを実行し、必要に応じて README と設計文書を更新します。
