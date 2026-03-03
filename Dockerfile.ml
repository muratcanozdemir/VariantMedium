ARG CUDA_VERSION=11.7.1

FROM nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu22.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3.11 \
        python3.11-dev \
        python3-pip \
        ca-certificates \
        # runtime libs for pysam's bundled htslib
        zlib1g \
        libbz2-1.0 \
        liblzma5 \
        libcurl4 \
    && rm -rf /var/lib/apt/lists/*

# make python3.11 the default python3
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
    && update-alternatives --install /usr/bin/python  python  /usr/bin/python3.11 1

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

WORKDIR /app
COPY pyproject.toml .
COPY bin/ bin/

# remove dead import
RUN sed -i '1{/^from pandas.core.window.ewm import \*/d}' bin/src/run.py

# install base + ml extras
RUN uv pip install --system --no-cache ".[ml]"

ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility

# CPU-only override at build time:
# docker build --build-arg CUDA_VERSION=cpu \
#   --build-arg CUDA_BASE=python:3.11-slim-bookworm \
#   -f Dockerfile.ml .