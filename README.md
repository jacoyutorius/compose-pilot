# Compose Pilot

Docker Composeプロジェクトへ組み込んで使う、ローカル開発向けの軽量GUIです。

1つのCompose Pilotが、同じCompose設定に属する1つのプロジェクトを管理します。ブラウザからサービスのビルド、起動、再起動、停止、削除、状態確認、ログ追跡を行えます。

このMVPはmacOSのDocker Desktopを対象としています。バックエンドはRuby 3.4、Sinatra、Puma、ブラウザ画面はビルド不要のVue 3、HTML、CSS、JavaScriptで構成しています。

設計判断と今後の開発計画は[プロダクト概要・開発計画](docs/product-overview.md)を参照してください。

## 主な機能

- 同じComposeプロジェクトに属するサービスの一覧と状態を表示
- すべて、または選択したサービスのビルド・起動
- 再起動、停止、コンテナ削除
- サービスカードからの個別の起動・停止・再起動
- コマンド出力とComposeログのリアルタイム表示
- ラベルで指定したWebサービスを公開ポートから別タブで開く
- Compose Pilot自身を通常操作から自動的に除外
- プロジェクト単位の排他制御による多重実行防止
- macOSホスト向けbind mountパス変換
- 元のComposeファイルを変更しない一時override生成

## 必要なもの

- macOS
- Docker Desktop
- `docker compose`が利用できること

Compose Pilot自身はコンテナ内で動くため、ホスト側へのRubyのインストールは不要です。

Vue 3の本番用ランタイムは`web/vendor/`へバージョン固定で配置しているため、画面表示時のCDNアクセスやNode.jsによるフロントエンドビルドも不要です。ライセンスは`web/vendor/VUE-LICENSE.txt`を参照してください。

## 導入方法

GitHub Releasesで公開されたイメージをGHCRから利用します。`VERSION`は利用するリリース番号へ置き換えてください。

```bash
docker pull ghcr.io/jacoyutorius/compose-pilot:VERSION
```

管理対象プロジェクトの`compose.yaml`へ、次のサービスを追加します。

```yaml
services:
  compose-pilot:
    image: ghcr.io/jacoyutorius/compose-pilot:VERSION
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

開発中のコードを試す場合は、Compose Pilotのリポジトリでローカルイメージをビルドし、`image`を`compose-pilot:local`へ変更します。

```bash
docker build -t compose-pilot:local .
```

### Webサービスをブラウザで開く

サービスの公開ポートをGUIから開く場合は、対象サービスへコンテナ側のポートをラベルで指定します。

```yaml
services:
  web:
    ports:
      - "3000:3000"
    labels:
      compose-pilot.open-port: "3000"
      compose-pilot.open-scheme: http
      compose-pilot.open-path: /
```

`compose-pilot.open-port`は必須です。`open-scheme`は`http`が初期値で`https`も指定でき、`open-path`の初期値は`/`です。サービスが起動中で、指定したコンテナポートにホスト側の公開ポートが割り当てられている場合だけ「ブラウザで開く」を表示します。

リンク先のホスト名にはCompose Pilotを表示しているURLのホスト名を使い、公開ポートはDockerの状態から取得します。固定のホスト側ポートをラベルへ重複して記載する必要はありません。

## 基本的な使い方

1. 操作対象を限定する場合は、サービスにチェックを入れます。
2. `ビルドして起動`などの操作ボタンを押します。
3. 画面下部の「実行結果」でコマンドの実行状況を確認します。

サービスを選択しなかった場合は、Compose Pilot自身を除く全サービスが対象になります。

各サービスカードの「起動」「停止」「再起動」から、そのサービスだけを直接操作することもできます。サービスの状態に応じて実行できないボタンは無効になります。

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
- bind mountは`source`、`target`、`read_only`だけを保持し、その他の詳細オプションには対応していません。
- Windows・Linux向けのパス変換は未対応です。

## 開発とテスト

Ruby 3.4を利用できる場合は、次のコマンドで全テストを実行できます。

```bash
bundle install
bundle exec ruby -Itest -e 'Dir["test/*_test.rb"].sort.each { |f| require_relative f }'
```

GUIを含む手動動作確認には、既存環境と競合しない18080番ポートの[テスト用Composeプロジェクト](test/manual/README.md)を利用できます。

Dockerイメージを作り直す場合は次を実行します。

```bash
docker build --no-cache -t compose-pilot:local .
```

## コンテナイメージの公開

GitHubで`v0.1.0`のようなセマンティックバージョンのタグを指定してReleaseを公開すると、GitHub ActionsがGHCRへマルチアーキテクチャイメージを公開します。GitHubのActions画面から`Publish container image`を選び、`Run workflow`で同形式のバージョンを入力して任意に実行することもできます。

例えば`v1.2.3`のReleaseでは、次のタグが生成されます。

- `ghcr.io/jacoyutorius/compose-pilot:1.2.3`
- `ghcr.io/jacoyutorius/compose-pilot:1.2`
- `ghcr.io/jacoyutorius/compose-pilot:1`
- `ghcr.io/jacoyutorius/compose-pilot:latest`

プレリリース版には`latest`を付与しません。公開対象プラットフォームは`linux/amd64`と`linux/arm64`です。

GHCRパッケージは初回公開時にprivateで作成されます。認証なしで利用できるようにするには、初回Releaseの公開後にGitHubのパッケージ設定でvisibilityをpublicへ変更してください。以降のバージョンは同じパッケージへ追加されます。
