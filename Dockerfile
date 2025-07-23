# syntax=docker/dockerfile:1

FROM ubuntu:22.04 AS builder

WORKDIR /build
RUN apt-get update && apt-get install -y \
    git cmake build-essential wget curl p7zip-full python3-pip python3-dev gosu

# voicevox_core ビルド（最適化）
RUN git clone https://github.com/VOICEVOX/voicevox_core.git && \
    cd voicevox_core && \
    git submodule update --init --recursive && \
    cmake -B build -DCMAKE_BUILD_TYPE=Release -DVOICEVOX_CORE_USE_CPU=ON -DCMAKE_CXX_FLAGS="-march=native" && \
    cmake --build build -j$(nproc) && \
    cp build/core/libcore.so /build/libcore.so

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
RUN curl -LO https://github.com/${VOICEVOX_ENGINE_REPO}/releases/download/${VOICEVOX_ENGINE_TAG}/voicevox_engine-linux-cpu-${VOICEVOX_ENGINE_TAG}.7z && \
    7zr x voicevox_engine-linux-cpu-${VOICEVOX_ENGINE_TAG}.7z && \
    mv linux-cpu /opt/voicevox_engine && rm voicevox_engine*.7z

# libcore.so 差し替え
COPY --from=builder /build/libcore.so /opt/voicevox_engine/core/libcore.so

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
