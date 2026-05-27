FROM debian:trixie AS build

ARG RELEASE_TAG
ARG CUDA_APT_REPO=https://developer.download.nvidia.com/compute/cuda/repos/debian13/sbsa
ARG CUDA_SERIES=13-3
ARG CUDA_DOT=13.3

ENV DEBIAN_FRONTEND=noninteractive
ENV CC=gcc
ENV CXX=g++
ENV CUDAHOSTCXX=g++
ENV CUDA_HOME=/usr/local/cuda-${CUDA_DOT}
ENV CUDAToolkit_ROOT=/usr/local/cuda-${CUDA_DOT}
ENV PATH=/usr/local/cuda-${CUDA_DOT}/bin:${PATH}

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
    curl -fsSL "${CUDA_APT_REPO}/8793F200.pub" | gpg --dearmor -o /usr/share/keyrings/nvidia-cuda-archive-keyring.gpg && \
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
    pkg="/out/llama-${RELEASE_TAG}" && \
    mkdir -p "${pkg}" "${pkg}/licenses/nvidia/debian-package-copyrights" "${pkg}/licenses/upstream" && \
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
    tmp_deps="$(mktemp)" && \
    for binary in "${pkg}"/libggml-cuda.so* "${pkg}"/llama-* "${pkg}"/rpc-server; do \
      if [ -e "${binary}" ]; then \
        ldd "${binary}" 2>/dev/null | awk '/=> \// { print $3 } /^\/.*\/lib/ { print $1 }' >> "${tmp_deps}"; \
      fi; \
    done && \
    sort -u "${tmp_deps}" | while read -r lib; do \
      [ -n "${lib}" ] || continue; \
      name="$(basename "${lib}")"; \
      case "${name}" in \
        libcuda.so|libcuda.so.*|libnvidia-*.so|libnvidia-*.so.*) \
          ;; \
        libcudart.so|libcudart.so.*|libcublas.so|libcublas.so.*|libcublasLt.so|libcublasLt.so.*|\
        libnvJitLink.so|libnvJitLink.so.*|libnvrtc.so|libnvrtc.so.*|libnvrtc-builtins.so|libnvrtc-builtins.so.*|\
        libnvvm.so|libnvvm.so.*|libnvToolsExt.so|libnvToolsExt.so.*|libnvblas.so|libnvblas.so.*|\
        libcufft.so|libcufft.so.*|libcufftw.so|libcufftw.so.*|libcurand.so|libcurand.so.*|\
        libcusolver.so|libcusolver.so.*|libcusolverMg.so|libcusolverMg.so.*|libcusparse.so|libcusparse.so.*|\
        libnpp*.so|libnpp*.so.*|libnvfatbin.so|libnvfatbin.so.*|libnvjpeg.so|libnvjpeg.so.*|\
        libcupti.so|libcupti.so.*|libcufile.so|libcufile.so.*|libcufile_rdma.so|libcufile_rdma.so.*) \
          cp -a "${lib}" "${pkg}/" || true; \
          ;; \
        *cuda*|*cublas*|*cupti*|*cufft*|*curand*|*cusolver*|*cusparse*|*npp*|*nvJitLink*|*nvrtc*|*nvvm*|*nvToolsExt*|*nvblas*|*nvfatbin*|*nvjpeg*|*cufile*) \
          echo "Refusing to bundle CUDA/NVIDIA library that is not in the redistributable allowlist: ${lib}"; \
          exit 1; \
          ;; \
      esac; \
    done && \
    find /usr/local/cuda* -maxdepth 3 -type f \( \
        -iname '*EULA*' -o \
        -iname '*LICENSE*' -o \
        -iname '*COPYRIGHT*' -o \
        -iname 'redistrib*.json' \
      \) -exec sh -c 'for file do cp "$file" "$0/$(basename "$file")"; done' "${pkg}/licenses/nvidia" {} + 2>/dev/null || true && \
    find /usr/share/doc -maxdepth 2 -type f -name copyright | while read -r file; do \
      package="$(basename "$(dirname "${file}")")"; \
      case "${package}" in \
        cuda-*|libcu*|libnv*) cp "${file}" "${pkg}/licenses/nvidia/debian-package-copyrights/${package}.copyright" ;; \
      esac; \
    done && \
    dpkg-query -W 'cuda-*' 'libcu*' 'libnv*' > "${pkg}/licenses/nvidia/cuda-package-versions.txt" 2>/dev/null || true && \
    printf '%s\n' \
      'This package bundles NVIDIA CUDA runtime components from NVIDIA CUDA Toolkit 13 Debian packages.' \
      'NVIDIA CUDA license terms apply to NVIDIA components.' \
      'See CUDA-EULA.txt when present, the Debian package copyright files in this directory, and:' \
      'https://docs.nvidia.com/cuda/eula/' \
      > "${pkg}/licenses/nvidia/README.txt" && \
    curl -fsSL https://docs.nvidia.com/cuda/eula/index.html -o "${pkg}/licenses/nvidia/CUDA-EULA.html" || true && \
    LD_LIBRARY_PATH="${pkg}:${LD_LIBRARY_PATH:-}" sh -c '\
      set -eu; \
      missing="$(mktemp)"; \
      external="$(mktemp)"; \
      find "$1" -maxdepth 1 -type f \( -perm -0100 -o -name "*.so*" \) -print | while read -r binary; do \
        ldd "${binary}" 2>/dev/null || true; \
      done | awk "/not found/ { print \\$1 }" | sort -u > "${missing}"; \
      if grep -vE "^libcuda\\.so(\\..*)?$" "${missing}" > "${missing}.unexpected"; then \
        echo "Unexpected unresolved shared libraries:"; \
        cat "${missing}.unexpected"; \
        exit 1; \
      fi; \
      find "$1" -maxdepth 1 -type f \( -perm -0100 -o -name "*.so*" \) -print | while read -r binary; do \
        ldd "${binary}" 2>/dev/null || true; \
      done | awk "/=> \\// { print \\$1 \" \" \\$3 } /^\\/.*\\/lib/ { print \\$1 \" \" \\$1 }" | \
        grep -E " (/.*/)?lib(cuda|cublas|cupti|cufft|curand|cusolver|cusparse|npp|nvJitLink|nvrtc|nvvm|nvToolsExt|nvblas|nvfatbin|nvjpeg|cufile).*\\.so" | \
        grep -vE "(^|[ /])lib(cuda|nvidia-[^ ]*)\\.so(\\.| |$)" | \
        awk -v pkg="$1/" "\\$2 !~ \"^\" pkg { print }" | sort -u > "${external}"; \
      if [ -s "${external}" ]; then \
        echo "CUDA/NVIDIA runtime libraries resolved outside the package:"; \
        cat "${external}"; \
        exit 1; \
      fi; \
    ' sh "${pkg}" && \
    tar -czf "/out/llama-${RELEASE_TAG}-bin-debian-trixie-cuda13-arm64.tar.gz" -C /out "llama-${RELEASE_TAG}"

FROM debian:trixie AS verify

ARG RELEASE_TAG

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends libgomp1 && \
    rm -rf /var/lib/apt/lists/*

COPY --from=build /out/ /out/

RUN test -n "${RELEASE_TAG}" && \
    pkg="/out/llama-${RELEASE_TAG}" && \
    LD_LIBRARY_PATH="${pkg}" sh -c '\
      set -eu; \
      missing="$(mktemp)"; \
      external="$(mktemp)"; \
      find "$1" -maxdepth 1 -type f \( -perm -0100 -o -name "*.so*" \) -print | while read -r binary; do \
        ldd "${binary}" 2>/dev/null || true; \
      done | awk "/not found/ { print \\$1 }" | sort -u > "${missing}"; \
      if grep -vE "^libcuda\\.so(\\..*)?$" "${missing}" > "${missing}.unexpected"; then \
        echo "Unexpected unresolved shared libraries in clean Debian runtime stage:"; \
        cat "${missing}.unexpected"; \
        exit 1; \
      fi; \
      find "$1" -maxdepth 1 -type f \( -perm -0100 -o -name "*.so*" \) -print | while read -r binary; do \
        ldd "${binary}" 2>/dev/null || true; \
      done | awk "/=> \\// { print \\$1 \" \" \\$3 } /^\\/.*\\/lib/ { print \\$1 \" \" \\$1 }" | \
        grep -E " (/.*/)?lib(cuda|cublas|cupti|cufft|curand|cusolver|cusparse|npp|nvJitLink|nvrtc|nvvm|nvToolsExt|nvblas|nvfatbin|nvjpeg|cufile).*\\.so" | \
        grep -vE "(^|[ /])lib(cuda|nvidia-[^ ]*)\\.so(\\.| |$)" | \
        awk -v pkg="$1/" "\\$2 !~ \"^\" pkg { print }" | sort -u > "${external}"; \
      if [ -s "${external}" ]; then \
        echo "CUDA/NVIDIA runtime libraries resolved outside the package in clean Debian runtime stage:"; \
        cat "${external}"; \
        exit 1; \
      fi; \
    ' sh "${pkg}"

FROM scratch AS artifact
COPY --from=verify /out/ /
