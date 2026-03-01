# ffmpeg-multistream-azure

Azure Container Instances (ACI) 上で ffmpeg を使い、1つの RTMP 入力を複数のプラットフォーム（YouTube / Facebook Live / X / LinkedIn）へ同時配信するシンプルなツール。

Restreamer と違い RTMP→HLS→RTMP の変換を経由しないため、音声品質の劣化が起きにくい。

## 特徴

- **直接 RTMP ファンアウト**: HLS を経由しない true passthrough
- **使わない時はゼロ円**: ACI は起動中のみ課金
- **自動停止タイマー**: `-t <分>` で指定時間後に自動削除
- **設定ファイルで管理**: ストリームキーは `config` に書くだけ

## 前提条件

- Azure CLI (`az`) インストール済み
- Docker インストール済み（初回イメージビルド時のみ）
- `openssl` インストール済み

## セットアップ

### 1. config ファイルを作成

```bash
cp config.example config
# config を編集して各プラットフォームのストリームキーを入力
```

### 2. Docker イメージをビルド & push（初回のみ）

```bash
docker build -t ebibibi/ffmpeg-multistream:latest .
docker push ebibibi/ffmpeg-multistream:latest
```

### 3. 起動

```bash
./multistream.sh -y start
# 17時に自動停止させる場合:
MINUTES=$(( (17*60) - (10#$(date +%H)*60 + 10#$(date +%M)) ))
./multistream.sh -y -t $MINUTES start
```

### 4. 停止

```bash
./multistream.sh stop
```

## 配信先の設定

`config` に各プラットフォームの情報を入力する。使わないものは空欄にしておけばスキップされる。

| プラットフォーム | 変数 |
|---|---|
| YouTube Live | `YOUTUBE_RTMP` (URL にキー含む) |
| Facebook Live | `FACEBOOK_RTMP` (URL にキー含む) |
| X (Twitter) | `X_RTMP` + `X_KEY` |
| LinkedIn Live | `LINKEDIN_RTMP` + `LINKEDIN_KEY` |

## 配信元アプリの設定

| 項目 | 値 |
|---|---|
| サーバー | `rtmp://<FQDN>:1935/live/` |
| ストリームキー | `config` の `STREAM_NAME`（デフォルト: `stream`） |

FQDN は `./multistream.sh status` で確認できる。
