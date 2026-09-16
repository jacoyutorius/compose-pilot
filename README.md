# Compose Pilot

Docker Composeプロジェクトへ組み込んで使う、ローカル開発向けの軽量GUIです。

1つのCompose Pilotが、同じCompose設定に属する1つのプロジェクトを管理します。ブラウザからサービスのビルド、起動、再起動、停止、削除、状態確認、ログ追跡を行えます。

このMVPはmacOSのDocker Desktopを対象としています。バックエンドはRuby 3.4、Sinatra、Puma、ブラウザ画面はHTML、CSS、JavaScriptで構成しています。

設計判断と今後の開発計画は[プロダクト概要・開発計画](docs/product-overview.md)を参照してください。

## 主な機能

- 同じComposeプロジェクトに属するサービスの一覧と状態を表示
- すべて、または選択したサービスのビルド・起動
- 再起動、停止、コンテナ削除
- コマンド出力とComposeログのリアルタイム表示
- Compose Pilot自身を通常操作から自動的に除外
- プロジェクト単位の排他制御による多重実行防止
- macOSホスト向けbind mountパス変換
- 元のComposeファイルを変更しない一時override生成

## 必要なもの

- macOS
- Docker Desktop
- `docker compose`が利用できること

Compose Pilot自身はコンテナ内で動くため、ホスト側へのRubyのインストールは不要です。

## 導入方法

最初にCompose Pilotのイメージをローカルでビルドします。

```bash
docker build -t compose-pilot:local /path/to/compose-pilot
```

管理対象プロジェクトの`compose.yaml`へ、次のサービスを追加します。

```yaml
services:
  compose-pilot:
    image: compose-pilot:local
    ports:
      - "127.0.0.1:8080:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - .:/workspace:ro
      - compose-pilot-data:/data
    environment:
      PROJECT_ROOT: /workspace
      HOST_PROJECT_ROOT: ${HOST_PROJECT_ROOT:?Set HOST_PROJECT_ROOT}
      ALLOW_SELF_OPERATION: ${ALLOW_SELF_OPERATION:-false}
    restart: unless-stopped

volumes:
  compose-pilot-data:
```

プロジェクトの`.env`に、`compose.yaml`があるディレクトリのmacOS上の絶対パスを設定します。

```dotenv
HOST_PROJECT_ROOT=/Users/your-name/projects/sample
ALLOW_SELF_OPERATION=false
```

Compose Pilotを起動します。

```bash
docker compose up -d compose-pilot
```

ブラウザで`http://localhost:8080`を開きます。

## 基本的な使い方

1. 操作対象を限定する場合は、サービスにチェックを入れます。
2. `ビルドして起動`などの操作ボタンを押します。
3. 画面下部の「実行結果」でコマンドの実行状況を確認します。

サービスを選択しなかった場合は、Compose Pilot自身を除く全サービスが対象になります。

「削除」はプロジェクト全体への`docker compose down`ではありません。対象サービスへ`docker compose rm --stop --force`を実行するため、Compose Pilotとプロジェクトのネットワーク・volumeは残ります。

## 自己操作の防止

Compose Pilotは、Docker Composeが実行中コンテナへ自動付与するラベルから、自身のプロジェクト名とサービス名を識別します。追加の識別ラベルやサービス名設定は不要です。

通常はCompose Pilot自身を選択できず、サービス未選択時の一括操作にも含まれません。

自己操作が必要な場合だけ、起動前に次の設定を有効にできます。

```dotenv
ALLOW_SELF_OPERATION=true
```

自己サービスを停止、再起動、再作成すると、ブラウザとの接続が途中で切れ、画面から復旧できなくなる場合があります。画面では実行前に確認を表示します。プロジェクト全体を停止する`down`は、この設定でも提供しません。

## パス変換の仕組み

プロジェクトディレクトリはCompose Pilotコンテナ内の`/workspace`へ読み取り専用でマウントされます。操作前に`docker compose config --format json`で設定を正規化し、`/workspace`以下を参照するbind mountだけをmacOSホスト上のパスへ変換します。

```text
/workspace/storage
↓
/Users/your-name/projects/sample/storage
```

変換結果は`/data/generated/project.paths.yaml`へ保存します。元のComposeファイルは変更しません。

build context、Dockerfile、env_file、configs、secrets、名前付きvolumeは変換対象外です。

## セキュリティ上の注意

Compose PilotはDockerソケットをマウントするため、ホスト上のDockerを操作できる強い権限を持ちます。

- ポートは`127.0.0.1`だけへ公開してください。
- インターネットやLANへ直接公開しないでください。
- 信頼できないComposeプロジェクトへ追加しないでください。
- `HOST_PROJECT_ROOT`には管理対象プロジェクト自身の絶対パスを指定してください。

## 現在の制限事項

- macOSホストのみを対象としています。
- 1つのCompose Pilotが管理できるプロジェクトは1つです。
- Composeファイルはプロジェクト直下の標準ファイル名1つだけに対応します。
  - `compose.yaml`
  - `compose.yml`
  - `docker-compose.yaml`
  - `docker-compose.yml`
- 標準ファイル名が複数存在する場合は、安全のため起動を拒否します。
- 認証機能はありません。
- プロジェクトルート外を参照するbind mountには対応していません。
- Windows・Linux向けのパス変換は未対応です。

## 開発とテスト

Ruby 3.4を利用できる場合は、次のコマンドで全テストを実行できます。

```bash
bundle install
bundle exec ruby -Itest -e 'Dir["test/*_test.rb"].sort.each { |f| require_relative f }'
```

Dockerイメージを作り直す場合は次を実行します。

```bash
docker compose build --no-cache
```
