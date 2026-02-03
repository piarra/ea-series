# Cloudflare Log Stream

小さなログ集約用の Cloudflare Workers。`POST /logs` で受け取ったメッセージを Durable Object 経由で WebSocket に配信し、同一 Worker が配信する簡易 Web UI で最大 1000 件まで表示します。Durable Object 内では SQLite ストレージに最新 1000 件まで永続化します。

## 必要環境
- Node.js 18+
- `npm install` で wrangler・型定義を取得
- Cloudflare アカウント（`wrangler login` 済み）

## ローカル開発
```bash
npm install
npm run dev
```
ブラウザで `http://localhost:8787/` を開きます。  
ログ送信例:
```bash
curl -X POST -H "Content-Type: application/json" \
  -d '{"message":"hello from curl","level":"info","source":"local"}' \
  http://localhost:8787/logs
```

## デプロイ
最初のデプロイ時のみ Durable Object を自動作成するため `--new-class` を付与します。
```bash
npm run deploy -- --new-class
```

## 設定
- `LOG_HISTORY_LIMIT`（デフォルト 1000）: Durable Object が保持する履歴件数。`wrangler.toml` の `vars` で変更できます。SQLite への保存件数も同じ値になります。

## エンドポイント
- `GET /` : Web UI（スマホ対応）
- `GET /ws` : WebSocket (クライアント用)
- `POST /logs` : ログ受付。JSON なら `{message, level?, context?, source?}`。プレーンテキストでも可。
- `GET /health` : ヘルスチェック

### 備考
- CORS は `POST /logs` に対して `*` で許可。
- Web UI もログ履歴を最大 1000 件まで保持し、古いものから捨てます。
