# Compose Pilot プロダクト概要・開発計画

## このドキュメントについて

このドキュメントは、Compose Pilotを継続的に開発するための判断基準を残すことを目的としています。

現在の機能だけでなく、プロダクトの目的、MVPに至るまでの経緯、技術選定、既知の課題、今後の開発計画をまとめます。仕様や優先順位が変わった場合は、実装と一緒にこのドキュメントも更新します。

## プロダクトの目的

Compose Pilotは、ローカル環境のDocker Composeプロジェクトを、ターミナルを開かずブラウザから操作するための軽量GUIです。

各ComposeプロジェクトのサービスとしてCompose Pilotを組み込み、1つのCompose Pilotが同居する1つのComposeプロジェクトだけを管理します。

Docker Desktopにはコンテナ管理機能がありますが、Compose Pilotでは日常的なアプリケーション開発に必要な操作へ焦点を絞ります。

- プロジェクト内のサービスを確認する
- プロジェクト全体、または選択したサービスをビルド・起動する
- サービスの状態とログを確認する
- 停止、再起動、削除を行う

目指すのは、Dockerそのものや複数プロジェクトを横断管理する汎用ツールではなく、個々のComposeプロジェクトに開発用の操作画面を追加するローカル開発ツールです。

## 想定利用者

- Docker Composeプロジェクトをローカルで開発している人
- `docker compose`の基本操作をGUIから行いたい人
- Docker DesktopよりComposeプロジェクト中心の画面を求めている人
- チーム内で共通の開発操作を分かりやすく提供したい人

## プロダクト原則

### ローカルファースト

Compose Pilotはローカル環境で動作し、外部サービスを必須としません。標準設定では`127.0.0.1`だけに公開します。

### 元のCompose設定を変更しない

ユーザーの`compose.yaml`や`docker-compose.yml`を直接編集しません。macOSホストとのパス差異は、一時的なoverrideファイルで吸収します。

### 実際のCompose CLIを利用する

Composeの挙動を独自に再実装せず、Docker公式の`docker compose`コマンドを利用します。環境変数展開、依存関係、build contextなどのCompose仕様は、可能な限りCompose CLIへ委ねます。

### 操作結果を隠さない

実行したコマンドと出力を画面に表示します。失敗時に、利用者がターミナルと同じ情報を確認できる状態を維持します。

### 安全側に倒す

同一プロジェクトへの操作は同時に1件だけ許可します。解決できないパスや未知のサービスを黙って実行せず、操作前にエラーとして扱います。

Compose Pilot自身は通常の操作対象から除外します。「すべてのサービス」を対象にする操作でもCompose Pilot自身を暗黙に含めません。自己停止を許可する場合は、起動時の明示的な設定と実行時の警告を必要とします。

## 単一プロジェクト構成の設計方針

### 1プロジェクトにつき1つのCompose Pilot

Compose Pilotを管理対象プロジェクトのCompose設定へサービスとして追加します。1つのCompose Pilotは、同じCompose設定に属する1プロジェクトだけを管理します。

```text
Composeプロジェクト
├── アプリケーションサービス
├── データベースなどの補助サービス
└── Compose Pilot
```

上位ディレクトリからComposeファイルを再帰探索する機能と、画面上のプロジェクト選択は廃止しました。管理対象は起動時に一意に決まり、別のComposeプロジェクトを誤って操作しません。

### Compose Pilot自身の識別

Docker Composeは、起動したコンテナへプロジェクト名とサービス名のラベルを自動付与します。Compose PilotはDocker APIを通じて自身のコンテナを調べ、次の標準ラベルから操作対象のプロジェクト名と自己サービス名を識別します。

```text
com.docker.compose.project
com.docker.compose.service
```

この情報を取得できない場合や、自己サービスがマウントされたCompose設定に存在しない場合は、Compose操作を開始しません。コンテナ外での開発時に限り、`COMPOSE_PROJECT_NAME`と`COMPOSE_PILOT_SERVICE`による明示指定も利用できます。

### 通常モードの操作規則

- Compose Pilot自身はサービス一覧へ管理サービスとして表示するが、選択不可とする
- サービス未選択時の操作対象は、Compose Pilot自身を除く全サービスとする
- `build`、`up`、`restart`、`stop`などは対象サービス名を明示して実行する
- Compose Pilot自身まで停止する`docker compose down`は通常モードでは実行しない
- 従来の「削除」は、対象サービスを限定できる`stop`と`rm`の組み合わせへの変更を検討する

### 自己操作を許可するオプション

自己操作は初期状態で無効にします。`ALLOW_SELF_OPERATION=true`を起動時に設定した場合だけ、Compose Pilot自身を操作対象として選択できるようにします。

自己停止や再作成ではHTTP接続が途中で切れ、GUIから復旧できない可能性があります。このため、自己操作を選択した実行には、結果を最後まで画面へ返せないことを明示した確認を必要とします。`down`を許可対象に含めるかは別途判断します。

### ホストパスの扱い

ホスト側パスの設定は`HOST_PROJECT_ROOT`とし、探索ルートではなく管理対象プロジェクトそのものの絶対パスを指定します。

コンテナ内では対象プロジェクトを`/workspace`へ読み取り専用でマウントし、bind mountのパス変換には従来どおりホスト側の絶対パスを利用します。

## 実装に至った経緯

### 1. デスクトップアプリではなくWebアプリを選択

当初はTauriなどを利用したデスクトップアプリも候補でした。しかし、macOSとWindowsの両方で利用しやすくし、アプリのインストールを不要にするため、ブラウザUIを採用しました。

Compose Pilot自身もDocker Composeで起動します。

```text
ブラウザ
  ↓ HTTP
Compose Pilotコンテナ
  ↓ Dockerソケット
Docker Desktop
```

### 2. 起動済みプロジェクトだけでなく、停止中のプロジェクトも操作対象にした

起動済みコンテナをDockerラベルから検出するだけでは、初回のビルドと起動をGUIから行えません。そのため、指定されたプロジェクトルート以下からComposeファイルを探索する方式を採用しました。

MVPでは次のファイル名を再帰的に検出します。

- `compose.yaml`
- `compose.yml`
- `docker-compose.yaml`
- `docker-compose.yml`

この探索方式は複数プロジェクトを横断管理する構成を前提としていました。現在は1プロジェクトにつき1つのCompose Pilotを配置し、再帰探索を行いません。

### 3. ホストと管理コンテナのパス差異をoverrideで解決

Compose Pilotコンテナから見えるパスは`/workspace`ですが、Docker Desktopがbind mountで必要とするのはmacOSホスト上のパスです。

```text
/workspace/sample
↓
/Users/example/projects/sample
```

Compose Pilotは`docker compose config --format json`で設定を正規化し、bind mountだけをホストパスへ変換した一時overrideファイルを生成します。

build context、Dockerfile、env file、configs、secrets、名前付きvolumeは変換しません。

### 4. Go版からRuby版へ移行

最初のMVPは、単一バイナリ化、並行処理、配布のしやすさを考慮してGoで実装しました。

その後、プロダクトを継続的に変更しやすくし、開発者自身が読み書きしやすい構成にするため、Rubyへ移行しました。現在のバックエンドはRuby 3.4、Sinatra、Pumaで構成しています。

Ruby版のMVPでは責務を次のように分離していました。単一プロジェクト化に伴い、探索責務は置き換えています。

| コンポーネント | 責務 |
| --- | --- |
| `ProjectRegistry` | Composeプロジェクトの探索と識別（単一プロジェクト化で廃止） |
| `ProjectLocator` | プロジェクト直下のComposeファイル解決 |
| `RuntimeIdentityResolver` | 実行中コンテナのプロジェクト名と自己サービス名の解決 |
| `ComposeRunner` | Compose設定の解析、パス変換、コマンド生成 |
| `CommandBody` | コマンドの一度だけの実行と出力配信 |
| `OperationRegistry` | プロジェクト単位の排他制御 |
| `App` | HTTP API、入力検証、レスポンス |

## 現在のアーキテクチャ

```text
web/index.html・Vue app.js
        ↓ HTTP API
Sinatra App
        ├─ ProjectLocator
        ├─ RuntimeIdentityResolver
        ├─ ComposeRunner
        ├─ OperationRegistry
        └─ CommandBody
                ↓
        docker compose CLI
                ↓
        /var/run/docker.sock
                ↓
        Docker Desktop
```

`ProjectRegistry`による複数プロジェクトの探索は廃止し、`ProjectLocator`が起動時に管理対象のCompose設定を1つ解決します。APIも単一プロジェクト前提とし、URLやリクエストにプロジェクトIDを含めません。

### ディレクトリ構成

```text
compose-pilot/
├── app.rb
├── config.ru
├── Gemfile
├── Dockerfile
├── compose.yaml
├── lib/
│   ├── command_body.rb
│   ├── compose_runner.rb
│   ├── operation_registry.rb
│   ├── project_locator.rb
│   └── runtime_identity.rb
├── test/
├── web/
│   └── vendor/        # ローカル配置したVueランタイムとライセンス
└── docs/
```

ブラウザ画面はVue 3のグローバルランタイムをローカルから直接読み込みます。npmやViteなどのビルド工程を設けず、既存のContent Security Policyを緩めないため、ブラウザ内テンプレートコンパイラを含まないランタイム版と描画関数を利用します。

## MVPで実装済みの機能

- プロジェクト直下のComposeファイル解決
- Compose設定からのサービス一覧取得
- Compose Pilot自身を除く全サービス、または選択サービスのビルド
- Compose Pilot自身を除く全サービス、または選択サービスの起動
- ビルドと起動の連続実行
- 再起動、停止、対象コンテナの削除
- サービスカードからの個別の起動、停止、再起動
- サービス状態の表示
- Composeログの追跡
- ラベルで指定したWebサービスを公開ポートから別タブで開く
- コマンド出力のリアルタイム表示
- macOS向けbind mountパス変換
- プロジェクト単位の多重実行防止
- localhost限定のポート公開

## MVP開発中に判明したこと

### 存在しないホストパスが空ディレクトリとして作成される

`HOST_PROJECTS_ROOT`を誤って指定した場合、Dockerが空のディレクトリを作成し、Compose Pilot自体は正常に起動する場合があります。その結果、エラーではなく「プロジェクトが0件」と表示されます。

今後は、0件の場合に設定値と確認方法を画面へ表示する必要があります。

### ストリーミング処理には実行回数の保証が必要

初期のRuby版では、Sinatraのストリーミングレスポンス内から別スレッドを起動していました。この実装により、同じ`docker compose up --build`が大量に並行実行される問題が発生しました。

現在はRackレスポンスボディの`each`からコマンドを一度だけ実行し、`OperationRegistry`で同一プロジェクトへの多重操作を拒否しています。

### UIだけの多重送信防止では不十分

ボタンを無効化しても、複数タブ、ネットワーク再送、将来の別クライアントから重複リクエストが届く可能性があります。重要な制約はバックエンドでも必ず保証します。

## 配布方針

利用者がCompose Pilotのソースを取得してローカルビルドしなくても導入できるように、リリース用コンテナイメージをGHCRで配布します。

- GitHub Releaseの公開を通常のイメージ公開契機とし、GitHub Actions画面からの手動公開にも対応する
- セマンティックバージョンからバージョン別タグと安定版の`latest`を生成する
- Apple SiliconとIntel Macの両方に対応するため、`linux/arm64`と`linux/amd64`を公開する
- GitHub Actionsの`GITHUB_TOKEN`を利用し、長期間有効な独自トークンを保管しない
- ビルドしたイメージにartifact attestationを付与する
- 開発中の動作確認では、引き続き`compose-pilot:local`を利用できるようにする

## セキュリティ

Compose PilotはDockerソケットをマウントするため、ホスト上のDockerを全面的に操作できる権限を持ちます。Dockerソケットへのアクセスは、実質的にホスト上で強い権限を持つことと同等です。

現在の前提は次のとおりです。

- ローカル環境だけで利用する
- `127.0.0.1`だけにポートを公開する
- インターネットやLANへ直接公開しない
- `HOST_PROJECT_ROOT`外のパスを操作しない
- サービス名をCompose設定と照合してからコマンドへ渡す

認証機能を実装するまで、リモート利用は対象外とします。

## 対象外とするもの

少なくとも当面は、次の用途を対象外とします。

- 本番環境のコンテナ運用
- Kubernetes管理
- Docker Swarm管理
- Docker Desktopの完全な代替
- インターネット上に公開する管理画面
- 複数ホストのリモート管理

## 今後の開発計画

### 完了：単一プロジェクト構成への移行

- 再帰的なプロジェクト探索を廃止
- 管理対象のCompose設定を1つに限定
- サイドメニューのプロジェクト選択を廃止
- Compose Pilot自身の識別と通常操作からの除外
- `down`を使わず対象サービスだけを削除する操作へ変更
- `HOST_PROJECTS_ROOT`から`HOST_PROJECT_ROOT`への設定移行
- READMEと導入用Compose設定例の更新
- 既存ユーザー向けの設定移行方法を用意

### フェーズ1：MVPの安定化

単一プロジェクト構成への移行後に、MVPの安定性を高める段階です。

- Compose設定を解決できない場合の診断表示
- Docker接続状態の表示
- 実行中操作の種類と開始時刻を表示
- 実行中コマンドの中断
- 操作失敗時の表示改善
- サービスごとのログ表示
- ビルドキャッシュ無効化オプションのUI
- APIとパス変換のテスト拡充
- 自己操作を許可する危険操作モード

### フェーズ2：Compose機能の拡充

- profilesの表示と選択
- `pull`操作
- `build --pull`などのビルドオプション
- プロジェクト名の明示的な設定
- Compose設定と生成overrideの確認画面

### フェーズ3：開発ワークフロー支援

- `docker compose exec`によるコマンド実行
- プロジェクトごとの定型コマンド登録
- Rails console、テスト、マイグレーションなどのショートカット
- 最近実行した操作の履歴

### フェーズ4：対応環境の拡大

- Windows向けホストパス変換
- Linux環境での検証
- 複数のパスマッピング
- プロジェクトルート外の共有ディレクトリ対応

Windows対応では、ドライブレター、Docker Desktop内部パス、WSL 2のパスを個別に検証する必要があります。

## 直近の優先順位

次に着手する候補は、次の順序を基本とします。

1. サービスごとのログ表示
2. 実行中操作の表示と中断
3. Docker接続状態の表示
4. profiles対応
5. Windows向けパス変換

優先順位は、実際の利用で発生した問題をもとに変更します。新機能よりも、データや開発環境を壊す可能性がある問題を優先します。

## 開発時の完了条件

機能追加や修正は、原則として次を満たした時点で完了とします。

- 正常系と主要な異常系がテストされている
- 同じ操作を複数回送っても危険な多重実行にならない
- 元のComposeファイルを変更しない
- プロジェクトルート外へ意図せずアクセスしない
- 失敗理由を画面またはログで確認できる
- READMEまたはこのドキュメントが必要に応じて更新されている
- macOSのDocker Desktopで動作確認されている

## Git運用案

初期段階では、単純なGitHub Flowを想定します。

1. `main`を常に動作可能な状態に保つ
2. Issueまたは開発項目ごとにブランチを作る
3. テストと動作確認後に`main`へマージする
4. MVP以降はバージョンタグを付ける

ブランチ名の例：

```text
feature/service-logs
feature/compose-profiles
fix/duplicate-build
fix/invalid-project-root
```

コミットでは、機能追加と無関係な整形や大規模な書き換えを混在させないようにします。

## 将来の判断で残しておく問い

- Compose Pilotは「Compose操作ツール」の範囲をどこまで広げるか
- 任意コマンド実行を安全に提供できるか
- Windows対応をコンテナだけで完結できるか
- Docker Engine APIを直接利用すべき機能があるか
- 複数人利用やリモート利用を本当に対象とするか
- プロジェクト設定をファイルで管理するか、GUI内部だけに保存するか

これらは先に決め切らず、実際の利用と必要性を確認しながら判断します。
