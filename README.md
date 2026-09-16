# Compose Pilot

Docker Composeプロジェクトをブラウザから操作する、ローカル環境向けの軽量GUIです。

このMVPは、macOSのDocker Desktopでの利用を対象にしています。

バックエンドはRuby 3.4、Sinatra、Pumaで実装しています。ブラウザ画面は依存関係の少ないHTML、CSS、JavaScriptで構成しています。

## 主な機能

- 指定したディレクトリ以下からComposeプロジェクトを検索
- プロジェクト全体、または選択したサービスのビルド・起動
- ビルド／ビルドして起動／再起動／停止／削除の操作
- コンテナとサービスの状態表示
- コマンド出力とComposeログのリアルタイム表示
- プロジェクト単位の排他制御によるCompose操作の多重実行防止
- macOSホスト向けbind mountパス変換
- 元のComposeファイルを変更せず、一時overrideファイルを生成

## 必要なもの

- macOS
- Docker Desktop
- `docker compose`が利用できること

Compose Pilot自体はコンテナ内で動くため、ホスト側へのRubyのインストールは不要です。

## 起動方法

サンプルの環境変数ファイルをコピーします。

```bash
cp .env.example .env
```

`.env`を開き、Composeプロジェクトを保存しているディレクトリの絶対パスを設定します。

```dotenv
HOST_PROJECTS_ROOT=/Users/your-name/projects
```

Compose Pilotをビルドして起動します。

```bash
docker compose up --build -d
```

起動後、ブラウザで次のURLを開きます。

```bash
open http://localhost:8080
```

## 基本的な使い方

1. 左側の一覧からComposeプロジェクトを選択します。
2. 操作対象を限定する場合は、サービスにチェックを入れます。
3. `ビルドして起動`などの操作ボタンを押します。
4. 画面下部の「実行結果」欄でコマンドの実行状況を確認します。

サービスを何も選択しなかった場合は、Composeプロジェクト全体が操作対象になります。

## パス変換の仕組み

ホスト側のプロジェクトディレクトリは、Compose Pilotコンテナ内の`/workspace`へ読み取り専用でマウントされます。

操作を実行する前に、Compose Pilotは次のコマンドを使ってCompose設定を正規化します。

```bash
docker compose config --format json
```

正規化された設定から、`/workspace`以下を参照するbind mountを抽出し、macOSホスト上のパスへ変換します。

```text
/workspace/sample/storage
↓
/Users/your-name/projects/sample/storage
```

変換結果は`/data/generated`以下の一時overrideファイルに保存されます。元の`compose.yaml`や`docker-compose.yml`は変更しません。

次の設定はパス変換の対象外です。

- build context
- Dockerfile
- env_file
- configs
- secrets
- 名前付きvolume

## セキュリティ上の注意

Compose Pilotは、ホストのDockerソケットをコンテナへマウントします。そのため、Compose Pilotコンテナはホスト上のDockerを操作できる強い権限を持ちます。

ポートはlocalhostだけへ公開しています。インターネットやLANへ直接公開しないでください。

## 現在の制限事項

- macOSホストのみを対象としています。
- プロジェクトルートとして指定できるディレクトリは1つです。
- 検出対象は標準的なComposeファイル名のみです。
  - `compose.yaml`
  - `compose.yml`
  - `docker-compose.yaml`
  - `docker-compose.yml`
- 認証機能はありません。
- プロジェクトルート外を参照するbind mountには対応していません。
- 読み取り専用以外の詳細なbind mountオプションは、まだ保持されません。
- Windows・Linux向けのパス変換には、まだ対応していません。

## 停止方法

Compose Pilotのディレクトリで次を実行します。

```bash
docker compose down
```

これはCompose Pilot自体を停止する操作です。画面上から管理対象プロジェクトへ実行する「削除」操作とは別なので注意してください。

## 開発とテスト

Rubyをローカルへインストールしている場合は、次のコマンドでテストできます。

```bash
bundle install
bundle exec ruby -Itest test/project_registry_test.rb
bundle exec ruby -Itest test/compose_runner_test.rb
```

Dockerイメージを作り直す場合は次を実行します。

```bash
docker compose build --no-cache
```
