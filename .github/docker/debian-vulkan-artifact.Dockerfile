FROM debian:trixie AS build

ARG RELEASE_TAG

ENV DEBIAN_FRONTEND=noninteractive
ENV CC=gcc
ENV CXX=g++

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      build-essential \
      cmake \
      ninja-build \
      pkg-config \
      python3 \
      python3-pip \
      libssl-dev \
      libgomp1 \
      libvulkan-dev \
      glslc \
      spirv-headers \
      xz-utils && \
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
      -DGGML_VULKAN=ON \
      -DGGML_RPC=ON \
      -DLLAMA_BUILD_EXAMPLES=OFF \
      -DLLAMA_BUILD_TESTS=OFF \
      -DLLAMA_BUILD_TOOLS=ON \
      -DLLAMA_BUILD_SERVER=ON \
      -DLLAMA_BUILD_BORINGSSL=ON && \
    cmake --build build --config Release -j"$(nproc)"

RUN test -n "${RELEASE_TAG}" && \
    mkdir -p /out && \
    cp LICENSE build/bin/LICENSE && \
    test -x build/bin/rpc-server && \
    test -x build/bin/llama-server && \
    test -x build/bin/llama-cli && \
    test -e build/bin/libggml-vulkan.so && \
    broken_symlinks="$(find build/bin -xtype l -print)" && \
    if [ -n "${broken_symlinks}" ]; then \
      printf '%s\n' 'Broken symlinks in build/bin:' "${broken_symlinks}"; \
      exit 1; \
    fi && \
    tar -czf "/out/llama-${RELEASE_TAG}-bin-debian-trixie-vulkan-arm64.tar.gz" \
      --transform "s,^\.,llama-${RELEASE_TAG}," -C build/bin .

FROM scratch AS artifact
COPY --from=build /out/ /
