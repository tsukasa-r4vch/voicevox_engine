# syntax=docker/dockerfile:1

ARG BASE_IMAGE=mirror.gcr.io/ubuntu:22.04

# === ダウンロードフェーズ ===
FROM ${BASE_IMAGE} AS download-engine-env
ARG DEBIAN_FRONTEND=noninteractive
WORKDIR /work

RUN apt-get update && apt-get install -y \
    curl \
    p7zip-full \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

ARG VOICEVOX_ENGINE_REPOSITORY
ARG VOICEVOX_ENGINE_VERSION
ARG VOICEVOX_ENGINE_TARGET

# --- エンジン本体ダウンロードと展開 ---
RUN set -eux; \
    LIST_NAME=voicevox_engine-${VOICEVOX_ENGINE_TARGET}-${VOICEVOX_ENGINE_VERSION}.7z.txt; \
    curl -fLO --retry 3 --retry-delay 5 "https://github.com/${VOICEVOX_ENGINE_REPOSITORY}/releases/download/${VOICEVOX_ENGINE_VERSION}/${LIST_NAME}"; \
    awk -v "repo=${VOICEVOX_ENGINE_REPOSITORY}" -v "tag=${VOICEVOX_ENGINE_VERSION}" \
        '{ print "url = \"https://github.com/" repo "/releases/download/" tag "/" $0 "\"\noutput = \"" $0 "\"" }' \
        "${LIST_NAME}" > ./curl.txt; \
    curl -fL --retry 3 --retry-delay 5 --parallel --config ./curl.txt; \
    7zr x "$(head -1 "./${LIST_NAME}")"

# --- himari以外のモデル削除 ---
RUN find ./linux-cpu/model/ -mindepth 1 -maxdepth 1 -type d ! -name "himari" -exec rm -rf {} +

# --- himari専用メタファイルの差し替え ---
COPY ./himari-only/metas.json ./linux-cpu/model/metas.json
COPY ./himari-only/speakers.json ./linux-cpu/model/speakers.json

# --- エンジン配置とクリーンアップ ---
RUN mv ./linux-cpu /opt/voicevox_engine && rm -rf ./*

# === ランタイムフェーズ ===
FROM ${BASE_IMAGE} AS runtime-env
ARG DEBIAN_FRONTEND=noninteractive
WORKDIR /opt/voicevox_engine

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

# エンジン本体のコピー
COPY --from=download-engine-env /opt/voicevox_engine /opt/voicevox_engine

# GPU非対応にするため、libcore.so を差し替える（必要な場合）
COPY ./voicevox_engine/core/bin/linux/libcore.so ./voicevox_engine/core/libcore.so

# himari専用メタファイルを反映
COPY ./himari-only/metas.json /opt/voicevox_engine/model/metas.json
COPY ./himari-only/speakers.json /opt/voicevox_engine/model/speakers.json

# README取得（Render対策）
ARG VOICEVOX_RESOURCE_VERSION=0.24.1
RUN curl -fLo "/opt/voicevox_engine/README.md" --retry 3 --retry-delay 5 \
    "https://raw.githubusercontent.com/VOICEVOX/voicevox_resource/${VOICEVOX_RESOURCE_VERSION}/engine/README.md"

# Python依存関係
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir git+https://github.com/r9y9/pyopenjtalk.git

# Entrypoint スクリプト
COPY --chmod=775 <<EOF /entrypoint.sh
#!/bin/bash
set -eux
cat /opt/voicevox_engine/README.md > /dev/stderr
exec "\$@" --port "\${PORT:-5000}"
EOF

ENTRYPOINT [ "/entrypoint.sh" ]
CMD [ "gosu", "user", "/opt/voicevox_engine/run", "--host", "0.0.0.0" ]
