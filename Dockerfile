# syntax=docker/dockerfile:1

FROM ubuntu:22.04 as build-core

WORKDIR /work

RUN apt-get update && apt-get install -y \
    git \
    cmake \
    build-essential \
    libxxhash-dev \
    curl \
    wget \
    unzip \
    pkg-config \
    libssl-dev \
    clang \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ここを v0.14.4 → 0.14.4 に修正
RUN git clone https://github.com/VOICEVOX/voicevox_core.git && \
    cd voicevox_core && \
    git fetch --tags && \
    git checkout 0.14.5 && \
    git submodule update --init --recursive && \
    cmake -B build -S example/cpp/unix -DCMAKE_BUILD_TYPE=Release -DVOICEVOX_CORE_USE_CPU=ON -DCMAKE_CXX_FLAGS="-march=native" && \
    cmake --build build -j$(nproc) && \
    cp $(find build -name libcore.so) /build/libcore.so


# ============================
FROM ubuntu:22.04 AS runtime

WORKDIR /opt/voicevox_engine

RUN apt-get update && apt-get install -y \
    python3 python3-pip curl gosu p7zip-full && \
    useradd --create-home user && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# voicevox_engine 取得＆展開
ARG VOICEVOX_ENGINE_REPO=VOICEVOX/voicevox_engine
ARG VOICEVOX_ENGINE_TAG=0.14.5

RUN apt-get update && apt-get install -y p7zip-full curl && apt-get clean

RUN set -eux; \
    LIST_NAME=voicevox_engine-linux-cpu-${VOICEVOX_ENGINE_TAG}.7z.txt; \
    curl -fLO "https://github.com/${VOICEVOX_ENGINE_REPO}/releases/download/${VOICEVOX_ENGINE_TAG}/${LIST_NAME}"; \
    awk -v "repo=${VOICEVOX_ENGINE_REPO}" -v "tag=${VOICEVOX_ENGINE_TAG}" \
        '{ print "url = \"https://github.com/" repo "/releases/download/" tag "/" $0 "\"\noutput = \"" $0 "\"" }' \
        "${LIST_NAME}" > ./curl.txt; \
    mkdir tmp_linux_cpu; \
    cd tmp_linux_cpu; \
    curl -fL --parallel --config ../curl.txt; \
    7zr x "$(head -1 ../${LIST_NAME})"; \
    rm -rf /opt/voicevox_engine/linux-cpu; \
    mv linux-cpu /opt/voicevox_engine; \
    cd ..; \
    rm -rf tmp_linux_cpu; \
    rm -rf ./*


# libcore.so 差し替え
COPY --from=build-core /build/libcore.so /opt/voicevox_engine/core/libcore.so

# Himari専用モデルだけ残す
RUN find ./model/ -mindepth 1 -maxdepth 1 -type d ! -name "himari" -exec rm -rf {} +

COPY ./himari-only/metas.json ./model/metas.json
COPY ./himari-only/speakers.json ./model/speakers.json

# Python deps
COPY requirements.txt .
RUN pip install -r requirements.txt && pip install git+https://github.com/r9y9/pyopenjtalk.git

# Entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["gosu", "user", "/opt/voicevox_engine/run", "--host", "0.0.0.0", "--cpu_num_threads=1"]
