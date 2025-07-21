#!/bin/bash
set -eux

# 利用規約表示（stderrにRender用）
cat /opt/voicevox_engine/README.md > /dev/stderr &

# エンジン起動（バックグラウンド）
"$@" --port "${PORT:-5000}" &
ENGINE_PID=$!

# 起動待機
for i in {1..20}; do
  sleep 1
  if curl -sf "http://localhost:${PORT:-5000}/version" >/dev/null; then
    echo "VOICEVOX Engine is up"
    break
  fi
done

# キャッシュ生成：音声合成を事前実行（speaker=14: 冥鳴ひまり）
echo "Generating cache..."
curl -sf -X POST "http://localhost:${PORT:-5000}/audio_query?speaker=14&text=テスト" \
  -H "Content-Type: application/json" > /tmp/query.json || true

curl -sf -X POST "http://localhost:${PORT:-5000}/synthesis?speaker=14" \
  -H "Content-Type: application/json" \
  -d @/tmp/query.json --output /dev/null || true

# 前景プロセスへ戻す
wait "$ENGINE_PID"
