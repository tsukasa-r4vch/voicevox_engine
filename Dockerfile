FROM python:3.11-slim

WORKDIR /opt/voicevox_engine

# 必要なパッケージをインストール（gitを追加）
RUN apt-get update && apt-get install -y \
    git \
    libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY ./voicevox_engine ./voicevox_engine

# 冥鳴ひまりモデルのみコピー
COPY ./voicevox_engine/core/model/冥鳴ひまり_8eaad775-3119-417e-8cf4-2a10bfd592c8 ./voicevox_engine/core/model/冥鳴ひまり_8eaad775-3119-417e-8cf4-2a10bfd592c8

# coreライブラリコピー
COPY ./voicevox_engine/core/bin/linux/libcore.so ./voicevox_engine/core/libcore.so

COPY run.py .

CMD ["python", "run.py"]
