#!/bin/bash
set -eux

# 利用規約の表示（stderrに出す Render 用）
cat /opt/voicevox_engine/README.md > /dev/stderr &

# VOICEVOX エンジンをバックグラウンドで起動（ポート指定対応）
"$@" --port "${PORT:-5000}" &
ENGINE_PID=$!

# エンジンの起動を待機（最大20秒）
for i in {1..20}; do
  sleep 1
  if curl -sf "http://localhost:${PORT:-5000}/version" >/dev/null; then
    echo "VOICEVOX Engine is up"
    break
  fi
done

# キャッシュ生成（ダミーの合成リクエストを1回）
echo "Generating cache..."
curl -sf -X POST "http://localhost:${PORT:-5000}/audio_query?speaker=14&text=テスト" \
  -H "Content-Type: application/json" > /tmp/query.json || true

curl -sf -X POST "http://localhost:${PORT:-5000}/synthesis?speaker=14" \
  -H "Content-Type: application/json" \
  -d @/tmp/query.json --output /dev/null || true

# 前景に戻す
wait "$ENGINE_PID"
