# syntax=docker/dockerfile:1

ARG BASE_IMAGE=mirror.gcr.io/ubuntu:22.04

# === libcore.so ビルドフェーズ ===
FROM ${BASE_IMAGE} AS build-core
WORKDIR /work
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    git \
    curl \
    cmake \
    clang \
    build-essential \
    libsndfile1-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/VOICEVOX/voicevox_core.git && \
    cd voicevox_core && \
    git submodule update --init --recursive && \
    cd core && \
    cmake -B build -DCMAKE_BUILD_TYPE=Release -DVOICEVOX_CORE_USE_CPU=ON -DCMAKE_CXX_FLAGS="-march=native" && \
    cmake --build build -j$(nproc) && \
    cp build/libcore.so /opt/libcore.so

# === エンジンダウンロードフェーズ ===
FROM ${BASE_IMAGE} AS download-engine-env
WORKDIR /work
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y curl p7zip-full \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

ARG VOICEVOX_ENGINE_REPOSITORY
ARG VOICEVOX_ENGINE_VERSION
ARG VOICEVOX_ENGINE_TARGET

RUN set -eux; \
    LIST_NAME=voicevox_engine-${VOICEVOX_ENGINE_TARGET}-${VOICEVOX_ENGINE_VERSION}.7z.txt; \
    curl -fLO --retry 3 --retry-delay 5 "https://github.com/${VOICEVOX_ENGINE_REPOSITORY}/releases/download/${VOICEVOX_ENGINE_VERSION}/${LIST_NAME}"; \
    awk -v "repo=${VOICEVOX_ENGINE_REPOSITORY}" -v "tag=${VOICEVOX_ENGINE_VERSION}" \
        '{ print "url = \"https://github.com/" repo "/releases/download/" tag "/" $0 "\"\noutput = \"" $0 "\"" }' \
        "${LIST_NAME}" > ./curl.txt; \
    curl -fL --retry 3 --retry-delay 5 --parallel --config ./curl.txt; \
    7zr x "$(head -1 "./${LIST_NAME}")"

# himari以外削除
RUN find ./linux-cpu/model/ -mindepth 1 -maxdepth 1 -type d ! -name "himari" -exec rm -rf {} +

# himari専用メタ情報のコピー
COPY ./himari-only/metas.json ./linux-cpu/model/metas.json
COPY ./himari-only/speakers.json ./linux-cpu/model/speakers.json

# 配置とクリーンアップ
RUN mv ./linux-cpu /opt/voicevox_engine && rm -rf ./*

# === ランタイムフェーズ ===
FROM ${BASE_IMAGE} AS runtime-env
WORKDIR /opt/voicevox_engine
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl \
    gosu \
    git \
    cmake \
    build-essential \
    python3-dev \
    python3-pip \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home user

# エンジンコピー
COPY --from=download-engine-env /opt/voicevox_engine /opt/voicevox_engine

# 最適化 libcore.so の差し替え
COPY --from=build-core /opt/libcore.so /opt/voicevox_engine/core/libcore.so

# 再度メタ情報を上書き（必要であれば）
COPY ./himari-only/metas.json /opt/voicevox_engine/model/metas.json
COPY ./himari-only/speakers.json /opt/voicevox_engine/model/speakers.json

# READMEを取得（Render 要件）
ARG VOICEVOX_RESOURCE_VERSION=0.24.1
RUN curl -fLo "/opt/voicevox_engine/README.md" --retry 3 --retry-delay 5 \
    "https://raw.githubusercontent.com/VOICEVOX/voicevox_resource/${VOICEVOX_RESOURCE_VERSION}/engine/README.md"

# Python依存
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir git+https://github.com/r9y9/pyopenjtalk.git

# 起動スクリプト（cache生成含む）
COPY --chmod=775 <<EOF /entrypoint.sh
#!/bin/bash
set -eux

# 利用規約の表示
cat /opt/voicevox_engine/README.md > /dev/stderr &

# エンジン起動（ポートはPORT envで指定可能、デフォルト:5000）
"\$@" --port "\${PORT:-5000}" &
ENGINE_PID=\$!

# エンジン起動を待機（最大20秒）
for i in {1..20}; do
  sleep 1
  if curl -sf "http://localhost:\${PORT:-5000}/version" >/dev/null; then
    echo "VOICEVOX Engine is up"
    break
  fi
done

# キャッシュ生成（himari）
echo "Generating cache..."
curl -sf -X POST "http://localhost:\${PORT:-5000}/audio_query?speaker=14&text=テスト" \
  -H "Content-Type: application/json" > /tmp/query.json || true

curl -sf -X POST "http://localhost:\${PORT:-5000}/synthesis?speaker=14" \
  -H "Content-Type: application/json" \
  -d @/tmp/query.json --output /dev/null || true

# 前景へ
wait "\$ENGINE_PID"
EOF

ENTRYPOINT [ "/entrypoint.sh" ]
CMD [ "gosu", "user", "/opt/voicevox_engine/run", "--host", "0.0.0.0", "--cpu_num_threads=1" ]
