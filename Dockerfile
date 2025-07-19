FROM python:3.11-slim

WORKDIR /opt/voicevox_engine

# 必要パッケージインストール
RUN apt-get update && apt-get install -y \
    libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

# requirements.txtをコピーしてインストール
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# VoiceVox Engine本体コードをコピー
COPY ./voicevox_engine ./voicevox_engine

# 冥鳴ひまりモデルのみコピー
COPY ./voicevox_engine/core/model/冥鳴ひまり_8eaad775-3119-417e-8cf4-2a10bfd592c8 ./voicevox_engine/core/model/冥鳴ひまり_8eaad775-3119-417e-8cf4-2a10bfd592c8

# coreライブラリコピー（例: libcore_cpu_x64.so）
COPY ./voicevox_engine/core/libcore.so ./voicevox_engine/core/libcore.so

# 起動スクリプトをコピー
COPY run.py .

CMD ["python", "run.py"]
