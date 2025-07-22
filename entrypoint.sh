#!/bin/bash
set -eux

# 利用規約の表示（Renderログ用）
cat /opt/voicevox_engine/README.md > /dev/stderr &

# VOICEVOX エンジン起動（ポート指定）
/opt/voicevox_engine/run --host 0.0.0.0 --port "${PORT:-5000}" --cpu_num_threads=2 &
ENGINE_PID=$!

# エンジンの起動を待機（最大20秒）
for i in {1..20}; do
  sleep 1
  if curl -sf "http://localhost:${PORT:-5000}/version" >/dev/null; then
    echo "VOICEVOX Engine is up"
    break
  fi
done

# キャッシュ生成（テスト合成）
echo "Generating cache..."
curl -sf -X POST "http://localhost:${PORT:-5000}/audio_query?speaker=14&text=テスト" \
  -H "Content-Type: application/json" > /tmp/query.json || true

curl -sf -X POST "http://localhost:${PORT:-5000}/synthesis?speaker=14" \
  -H "Content-Type: application/json" \
  -d @/tmp/query.json --output /dev/null || true

# VOICEVOX エンジンの前景復帰
wait "$ENGINE_PID"
