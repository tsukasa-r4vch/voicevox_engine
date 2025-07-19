# Python 3.11 をベースにする（Self型を使うため）
FROM python:3.11-slim

# 作業ディレクトリを指定
WORKDIR /opt/voicevox_engine

# 必要なライブラリをインストール
RUN apt-get update && apt-get install -y \
    git gcc cmake build-essential libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

# numpyを先にインストール（必要に応じてバージョン固定）
RUN pip install numpy==2.2.4

# requirements.txt をコピーして依存パッケージをインストール
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# run.py をコピー（mainスクリプト）
COPY run.py ./run.py

# voicevox_engine ディレクトリの中身をコピー
COPY ./voicevox_engine ./voicevox_engine

# 冥鳴ひまりモデルを core/model 以下にコピー
COPY ./voicevox_engine/core/model/冥鳴ひまり_8eaad775-3119-417e-8cf4-2a10bfd592c8 ./core/model/冥鳴ひまり_8eaad775-3119-417e-8cf4-2a10bfd592c8

# 起動コマンド
CMD ["python", "run.py"]
