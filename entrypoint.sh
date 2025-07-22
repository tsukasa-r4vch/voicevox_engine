#!/bin/bash
set -eux

cat /opt/voicevox_engine/README.md > /dev/stderr &

"$@" --port "${PORT:-5000}" &
ENGINE_PID=$!

# 起動確認待ち
for i in {1..20}; do
  sleep 1
  if curl -sf "http://localhost:${PORT:-5000}/version" >/dev/null; then
    echo "VOICEVOX Engine is up"
    break
  fi
done

# プリウォーム（キャッシュ生成を強化）
echo "Warming up..."
TEXT="これはテストです"
curl -sf -X POST "http://localhost:${PORT:-5000}/audio_query?speaker=14&text=${TEXT}" \
  -H "Content-Type: application/json" > /tmp/query.json || true

curl -sf -X POST "http://localhost:${PORT:-5000}/accent_phrases?speaker=14" \
  -H "Content-Type: application/json" -d @/tmp/query.json > /dev/null || true

curl -sf -X POST "http://localhost:${PORT:-5000}/mora_length?speaker=14" \
  -H "Content-Type: application/json" -d @/tmp/query.json > /dev/null || true

curl -sf -X POST "http://localhost:${PORT:-5000}/mora_pitch?speaker=14" \
  -H "Content-Type: application/json" -d @/tmp/query.json > /dev/null || true

curl -sf -X POST "http://localhost:${PORT:-5000}/synthesis?speaker=14" \
  -H "Content-Type: application/json" -d @/tmp/query.json --output /dev/null || true

# エンジンがバックグラウンド起動中 → 前面に戻す
wait "$ENGINE_PID"
