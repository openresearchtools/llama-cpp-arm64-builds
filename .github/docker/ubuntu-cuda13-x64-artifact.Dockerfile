FROM node:24-bookworm-slim AS node

FROM ubuntu:24.04 AS build

ARG RELEASE_TAG
ARG CUDA_APT_REPO=https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64
ARG CUDA_SERIES=13-2
ARG CUDA_DOT=13.2

ENV DEBIAN_FRONTEND=noninteractive
ENV CC=gcc
ENV CXX=g++
ENV CUDAHOSTCXX=g++
ENV CUDA_HOME=/usr/local/cuda-${CUDA_DOT}
ENV CUDAToolkit_ROOT=/usr/local/cuda-${CUDA_DOT}
ENV PATH=/usr/local/cuda-${CUDA_DOT}/bin:${PATH}

COPY --from=node /usr/local/ /usr/local/

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      gnupg \
      git \
      build-essential \
      cmake \
      ninja-build \
      pkg-config \
      python3 \
      python3-pip \
      libssl-dev \
      libgomp1 \
      xz-utils && \
    mkdir -p /usr/share/keyrings && \
    curl --retry 5 --connect-timeout 20 --max-time 120 -fsSL "${CUDA_APT_REPO}/3bf863cc.pub" | gpg --dearmor -o /usr/share/keyrings/nvidia-cuda-archive-keyring.gpg && \
    printf 'deb [signed-by=/usr/share/keyrings/nvidia-cuda-archive-keyring.gpg] %s /\n' "${CUDA_APT_REPO}" > /etc/apt/sources.list.d/nvidia-cuda.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      cuda-nvcc-${CUDA_SERIES} \
      cuda-cudart-dev-${CUDA_SERIES} \
      libcublas-dev-${CUDA_SERIES} && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . .

RUN cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_RPATH='$ORIGIN' \
      -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
      -DGGML_NATIVE=OFF \
      -DGGML_BACKEND_DL=ON \
      -DGGML_CPU_ALL_VARIANTS=ON \
      -DGGML_CUDA=ON \
      -DGGML_RPC=ON \
      -DCUDAToolkit_ROOT="${CUDAToolkit_ROOT}" \
      -DLLAMA_BUILD_EXAMPLES=OFF \
      -DLLAMA_BUILD_TESTS=OFF \
      -DLLAMA_BUILD_TOOLS=ON \
      -DLLAMA_BUILD_SERVER=ON \
      -DLLAMA_BUILD_BORINGSSL=ON && \
    cmake --build build --config Release -j"$(nproc)"

RUN test -n "${RELEASE_TAG}" && \
    mkdir -p /out && \
    cp LICENSE build/bin/LICENSE && \
    if [ ! -x build/bin/rpc-server ] && [ -x build/bin/ggml-rpc-server ]; then \
      cp build/bin/ggml-rpc-server build/bin/rpc-server; \
    fi && \
    test -x build/bin/rpc-server && \
    test -x build/bin/llama-server && \
    test -x build/bin/llama-cli && \
    test -e build/bin/libggml-cuda.so && \
    broken_symlinks="$(find build/bin -xtype l -print)" && \
    if [ -n "${broken_symlinks}" ]; then \
      printf '%s\n' 'Broken symlinks in build/bin:' "${broken_symlinks}"; \
      exit 1; \
    fi && \
    tar -czf "/out/llama-${RELEASE_TAG}-bin-ubuntu-cuda13-x64.tar.gz" \
      --transform "s,^\.,llama-${RELEASE_TAG}," -C build/bin .

FROM scratch AS artifact
COPY --from=build /out/ /
