# ffmpeg-multistream-azure

Azure Container Instances (ACI) 上で ffmpeg を使い、1つの RTMP 入力を YouTube / Facebook Live / X / LinkedIn へ同時配信するツール。

RTMP → HLS → RTMP のような中間変換をせず、**直接 RTMP ファンアウト**するため音声品質の劣化が起きにくい。

---

## 毎回の使い方

### 配信開始

```bash
cd ~/ffmpeg-multistream-azure

# 17:00 に自動停止させる場合（分数は都度計算）
MINUTES=$(( (17*60) - (10#$(date +%H)*60 + 10#$(date +%M)) ))
./multistream.sh -y -t $MINUTES start

# 手動停止前提で起動する場合
./multistream.sh -y start
```

起動完了後に **配信前チェックリスト** が自動表示される。
チェックリストに表示された「サーバー」と「ストリームキー」を配信元アプリに入力して配信開始。

### 配信元アプリへの入力値

| 項目 | 値 |
|------|-----|
| サーバー | `rtmp://<表示された FQDN>:1935/live/` |
| ストリームキー | `config` の `STREAM_NAME`（デフォルト: `stream`） |

### 配信停止

```bash
./multistream.sh stop
```

### その他のコマンド

```bash
./multistream.sh status     # FQDN・状態を確認
./multistream.sh checklist  # 配信前チェックリストを再表示
./multistream.sh logs       # ffmpeg のログをリアルタイム表示
```

---

## 配信先の設定（config ファイル）

`config` ファイルに各プラットフォームのストリームキーを書く。
**使わないプラットフォームは空欄のまま**にしておけば自動でスキップされる。

```bash
cp config.example config
vi config  # または好きなエディタで編集
```

### YouTube Live

**取得場所**: YouTube Studio → ライブ配信 → ストリームキー

```bash
# URL の末尾にキーを含む形式
YOUTUBE_RTMP=rtmps://a.rtmp.youtube.com/live2/xxxx-xxxx-xxxx-xxxx-xxxx
```

### Facebook Live

**取得場所**: Facebook → ライブ動画を作成 → 「ストリーミングソフトを使用」→ サーバー URL をコピー（キーが末尾に含まれている）

```bash
# URL の末尾にキーを含む形式
FACEBOOK_RTMP=rtmps://live-api-s.facebook.com:443/rtmp/FB-xxxxxxxxx-x-Abxxxxxxx
```

### X (Twitter)

**取得場所**: X → プロフィール → ライブ配信 → ストリームキー

```bash
# サーバーURLとキーを別々に指定
X_RTMP=rtmp://jp.pscp.tv:80/x
X_KEY=xxxxxxxxxxxx
```

### LinkedIn Live

**取得場所**: LinkedIn → 投稿 → ライブ動画 → 「ストリーミングソフトを使用」→ 配信サーバーとキーをコピー

```bash
# サーバーURLとキーを別々に指定（サーバーは毎回変わる場合あり）
LINKEDIN_RTMP=rtmps://ip-xxx-xxx-xxx-xxx.live-input-li.bitcod.in/live
LINKEDIN_KEY=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

> **注意**: LinkedIn のストリームキーとサーバーURLは配信枠を作るたびに変わる。配信前に必ず更新すること。

### 停止忘れ防止通知（任意）

Discord Webhook URL を設定すると、起動時に「課金中」通知が届く。

```bash
NOTIFY_DISCORD_URL=https://discord.com/api/webhooks/xxxxxx/xxxxxx
```

---

## 初回セットアップ

### 前提条件

- Azure CLI (`az`) インストール済み・ログイン済み
- Docker インストール済み
- `openssl` インストール済み

### 手順

**1. Docker イメージをビルドして Docker Hub へ push**

```bash
docker build -t ebibibi/ffmpeg-multistream:latest .
docker login
docker push ebibibi/ffmpeg-multistream:latest
```

**2. config ファイルを作成**

```bash
cp config.example config
# config を編集してストリームキーを入力（上記「配信先の設定」参照）
```

**3. Azure の準備**

```bash
az login
az account set --subscription "MVP_WebSites"  # 使用するサブスクリプションを選択

# Microsoft.ContainerInstance が未登録の場合（初回のみ）
az provider register --namespace Microsoft.ContainerInstance --wait
```

---

## 仕組み

```
配信元アプリ（Teams 等）
    │ RTMP
    ▼
ffmpeg on ACI（rtmp://FQDN:1935/live/stream で待ち受け）
    │ RTMP コピー（エンコードなし）
    ├──▶ YouTube Live
    ├──▶ Facebook Live
    ├──▶ X (Twitter)
    └──▶ LinkedIn Live
```

ffmpeg は `-c copy` モードで動作するためトランスコードは行わない。
ストリームが切断されると自動で再接続待機状態に戻る。

---

## 料金の目安

ACI は**起動中のみ**課金される（停止・削除すればゼロ）。

| スペック | 2 時間あたりの目安 |
|---|---|
| 4 vCPU / 4 GB | 約 ¥120 |

`-t <分>` オプションで自動停止タイマーをセットすることを強く推奨。
