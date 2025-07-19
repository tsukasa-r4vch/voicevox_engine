# Python 3.10ベースの軽量イメージ
FROM python:3.10-slim

# 作業ディレクトリを設定
WORKDIR /opt/voicevox_engine

# 必要なシステム依存パッケージのインストール
RUN apt-get update && apt-get install -y \
    git gcc cmake build-essential libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

# numpyを先にインストール（pyworld依存回避）
RUN pip install numpy==2.2.4

# requirements.txt をコピーしてインストール
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# 実行スクリプト
COPY run.py ./run.py

# voicevox_engine のソースコードをコピー
COPY ./voicevox_engine ./voicevox_engine

# 冥鳴ひまり専用モデルだけをコピー
COPY ./voicevox_engine/core/model/冥鳴ひまり_8eaad775-3119-417e-8cf4-2a10bfd592c8 \
     ./core/model/冥鳴ひまり_8eaad775-3119-417e-8cf4-2a10bfd592c8

# コンテナ起動時のコマンド
CMD ["python", "run.py"]
