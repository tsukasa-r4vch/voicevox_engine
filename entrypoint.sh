#!/bin/bash
set -eux
cat /opt/voicevox_engine/README.md > /dev/stderr &

"$@" --port "${PORT:-5000}" &
ENGINE_PID=$!

# エンジンの起動待ち
for i in {1..20}; do
  sleep 1
  if curl -sf "http://localhost:${PORT:-5000}/version" >/dev/null; then
    break
  fi
done

# キャッシュ生成（冥鳴ひまり）
curl -sf -X POST "http://localhost:${PORT:-5000}/audio_query?speaker=14&text=テスト" \
  -H "Content-Type: application/json" > /tmp/query.json || true

curl -sf -X POST "http://localhost:${PORT:-5000}/synthesis?speaker=14" \
  -H "Content-Type: application/json" -d @/tmp/query.json --output /dev/null || true

wait "$ENGINE_PID"
