FROM --platform=linux/arm64 python:3.11-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# 依存（xgboost / lightgbm / onnx などのビルド・実行で必要になることが多い）
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    ca-certificates \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Python deps
# ここは必要に応じて増減してください
RUN pip install --no-cache-dir \
    numpy \
    pandas \
    scikit-learn \
    xgboost \
    lightgbm \
    onnxmltools \
    onnx \
    jupyterlab

WORKDIR /work
