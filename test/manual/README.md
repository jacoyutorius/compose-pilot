# 手動動作確認

既存のComposeプロジェクトと分離し、`demo-web`と`demo-worker`をCompose Pilotから操作するための構成です。GUIは`http://localhost:18080`、デモWebサービスは`http://localhost:18081`で開きます。

## 起動

リポジトリルートでCompose Pilotのイメージをビルドします。

```bash
docker build -t compose-pilot:local .
```

テスト用の環境変数ファイルを作り、`HOST_PROJECT_ROOT`をこの`test/manual`ディレクトリの絶対パスへ書き換えます。

```bash
cp test/manual/.env.example test/manual/.env
```

テスト用プロジェクトを起動します。

```bash
docker compose --env-file test/manual/.env -f test/manual/compose.yaml up -d
```

## 確認項目

- プロジェクト選択用のサイドメニューが表示されない
- `demo-web`、`demo-worker`、`compose-pilot`の3サービスが表示される
- 通常設定では`compose-pilot`を選択できない
- サービス未選択の停止・再起動・削除でもCompose Pilotが動作し続ける
- `demo-web`だけを選択し、停止・再起動・削除を個別に実行できる
- 各サービスカードのボタンから、そのサービスだけを起動・停止・再起動できる
- 各サービスカードのログアイコンから、そのサービスだけのログを追跡できる
- ログ追跡中に停止アイコンで通常の操作状態へ戻れる
- サービスごとのビルド設定が、それぞれのビルドコマンドへ反映される
- 「ビルドして起動」でbuild成功後にupが実行される
- `demo-web`の「ブラウザで開く」からデモページを別タブで開ける
- `demo-web`の停止中は「ブラウザで開く」が表示されない
- 削除後も画面へアクセスでき、Composeネットワークとvolumeが残る
- ログ追跡にCompose Pilot自身のログが混ざらない

自己操作を確認する場合は、`.env`の`ALLOW_SELF_OPERATION`を`true`へ変更してCompose Pilotを再作成します。接続が切れる可能性があるため、最後に確認してください。

```bash
docker compose --env-file test/manual/.env -f test/manual/compose.yaml up -d --force-recreate compose-pilot
```

## 終了

GUIからの削除はプロジェクト全体を停止しないため、検証後はターミナルから終了します。

```bash
docker compose --env-file test/manual/.env -f test/manual/compose.yaml down --volumes
```
