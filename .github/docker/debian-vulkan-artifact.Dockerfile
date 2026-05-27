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
    pkg="/out/llama-${RELEASE_TAG}" && \
    mkdir -p "${pkg}" "${pkg}/licenses/debian-package-copyrights" "${pkg}/licenses/upstream" && \
    find build -name "*.so*" -exec cp -P {} "${pkg}/" \; && \
    cp -a build/bin/. "${pkg}/" && \
    find . -maxdepth 1 -type f -name "*.py" -exec cp {} "${pkg}/" \; && \
    if [ -d gguf-py ]; then cp -a gguf-py "${pkg}/gguf-py"; fi && \
    if [ -d requirements ]; then cp -a requirements "${pkg}/requirements"; fi && \
    if [ -f requirements.txt ]; then cp requirements.txt "${pkg}/requirements.txt"; fi && \
    if [ -f .devops/tools.sh ]; then cp .devops/tools.sh "${pkg}/tools.sh"; fi && \
    test -x "${pkg}/rpc-server" && \
    test -x "${pkg}/llama-server" && \
    test -x "${pkg}/llama-cli" && \
    cp LICENSE "${pkg}/LICENSE" && \
    for file in AUTHORS NOTICE; do \
      if [ -f "${file}" ]; then cp "${file}" "${pkg}/licenses/upstream/${file}"; fi; \
    done && \
    if [ -d licenses ]; then cp -a licenses "${pkg}/licenses/upstream/licenses"; fi && \
    if [ -f vendor/cpp-httplib/LICENSE ]; then \
      mkdir -p "${pkg}/licenses/upstream/vendor/cpp-httplib"; \
      cp vendor/cpp-httplib/LICENSE "${pkg}/licenses/upstream/vendor/cpp-httplib/LICENSE"; \
    fi && \
    if [ -f gguf-py/LICENSE ]; then \
      mkdir -p "${pkg}/licenses/upstream/gguf-py"; \
      cp gguf-py/LICENSE "${pkg}/licenses/upstream/gguf-py/LICENSE"; \
    fi && \
    find /usr/share/doc -maxdepth 2 -type f -name copyright | while read -r file; do \
      package="$(basename "$(dirname "${file}")")"; \
      case "${package}" in \
        libvulkan*|vulkan*|spirv*|glslang*) cp "${file}" "${pkg}/licenses/debian-package-copyrights/${package}.copyright" ;; \
      esac; \
    done && \
    tar -czf "/out/llama-${RELEASE_TAG}-bin-debian-trixie-vulkan-arm64.tar.gz" -C /out "llama-${RELEASE_TAG}"

FROM scratch AS artifact
COPY --from=build /out/ /
