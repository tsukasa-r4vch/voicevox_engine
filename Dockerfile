# syntax=docker/dockerfile:1

ARG BASE_IMAGE=mirror.gcr.io/ubuntu:22.04

###########################
# === ビルドフェーズ === #
###########################
FROM ${BASE_IMAGE} AS build-core
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    git \
    cmake \
    clang \
    build-essential \
    libssl-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /work
RUN git clone --depth=1 https://github.com/VOICEVOX/voicevox_core.git
WORKDIR /work/voicevox_core

# CPU向け Release + AVX 最適化
RUN cmake -B build -DCMAKE_BUILD_TYPE=Release -DVOICEVOX_CORE_USE_CPU=ON -DCMAKE_CXX_FLAGS="-march=native"
RUN cmake --build build -j$(nproc)


###############################
# === エンジンDLフェーズ === #
###############################
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

RUN set -eux; \
    LIST_NAME=voicevox_engine-${VOICEVOX_ENGINE_TARGET}-${VOICEVOX_ENGINE_VERSION}.7z.txt; \
    curl -fLO --retry 3 --retry-delay 5 "https://github.com/${VOICEVOX_ENGINE_REPOSITORY}/releases/download/${VOICEVOX_ENGINE_VERSION}/${LIST_NAME}"; \
    awk -v "repo=${VOICEVOX_ENGINE_REPOSITORY}" -v "tag=${VOICEVOX_ENGINE_VERSION}" \
        '{ print "url = \"https://github.com/" repo "/releases/download/" tag "/" $0 "\"\noutput = \"" $0 "\"" }' \
        "${LIST_NAME}" > ./curl.txt; \
    curl -fL --retry 3 --retry-delay 5 --parallel --config ./curl.txt; \
    7zr x "$(head -1 "./${LIST_NAME}")"

RUN find ./linux-cpu/model/ -mindepth 1 -maxdepth 1 -type d ! -name "himari" -exec rm -rf {} +
COPY ./himari-only/metas.json ./linux-cpu/model/metas.json
COPY ./himari-only/speakers.json ./linux-cpu/model/speakers.json
RUN mv ./linux-cpu /opt/voicevox_engine && rm -rf ./*


###########################
# === ランタイムフェーズ === #
###########################
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

COPY --from=download-engine-env /opt/voicevox_engine /opt/voicevox_engine
COPY --from=build-core /work/voicevox_core/build/core/libcore.so /opt/voicevox_engine/core/libcore.so

COPY ./himari-only/metas.json /opt/voicevox_engine/model/metas.json
COPY ./himari-only/speakers.json /opt/voicevox_engine/model/speakers.json

ARG VOICEVOX_RESOURCE_VERSION=0.24.1
RUN curl -fLo "/opt/voicevox_engine/README.md" --retry 3 --retry-delay 5 \
    "https://raw.githubusercontent.com/VOICEVOX/voicevox_resource/${VOICEVOX_RESOURCE_VERSION}/engine/README.md"

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir git+https://github.com/r9y9/pyopenjtalk.git

COPY --chmod=775 <<EOF /entrypoint.sh
#!/bin/bash
set -eux
cat /opt/voicevox_engine/README.md > /dev/stderr &
"$@" --port "${PORT:-5000}" &
ENGINE_PID=$!

for i in {1..20}; do
  sleep 1
  if curl -sf "http://localhost:${PORT:-5000}/version" >/dev/null; then
    echo "VOICEVOX Engine is up"
    break
  fi
  echo "Waiting for engine..."
done

echo "Generating cache..."
curl -sf -X POST "http://localhost:${PORT:-5000}/audio_query?speaker=14&text=テスト" \
  -H "Content-Type: application/json" > /tmp/query.json || true

curl -sf -X POST "http://localhost:${PORT:-5000}/synthesis?speaker=14" \
  -H "Content-Type: application/json" \
  -d @/tmp/query.json --output /dev/null || true

wait "$ENGINE_PID"
EOF

ENTRYPOINT [ "/entrypoint.sh" ]
CMD [ "gosu", "user", "/opt/voicevox_engine/run", "--host", "0.0.0.0", "--cpu_num_threads=1" ]
