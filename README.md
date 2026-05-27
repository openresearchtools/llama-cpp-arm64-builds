# llama-cpp-arm64-builds

Release automation for ARM64 llama.cpp builds.

This repository does not vendor llama.cpp or TurboQuant source. Its GitHub
Actions workflows check out source from:

- `ggml-org/llama.cpp`
- `TheTom/llama-cpp-turboquant`

It then builds release tarballs for:

- macOS ARM64 Metal
- Debian Trixie ARM64 Vulkan
- Debian Trixie ARM64 CUDA 13

The Debian artifacts are built inside throwaway Debian Trixie ARM64 containers.
They are normal full release packages: all built tools, `rpc-server`, and CPU
backend variants are kept in the CUDA and Vulkan tarballs.
The CUDA build uses NVIDIA's Debian 13 SBSA CUDA 13 packages and bundles CUDA
runtime libraries such as `libcudart`, `libcublas`, and `libcublasLt` together
with NVIDIA EULA and package copyright notices.
It does not bundle the NVIDIA kernel/user driver. `libcuda.so` must come from
the target machine's installed NVIDIA driver.

Release tarballs follow the upstream llama.cpp layout: a single
`llama-<tag>/` directory containing the built binaries and shared libraries,
including `rpc-server`.

## Workflows

- `Track llama.cpp releases`: runs daily and builds the latest upstream
  `ggml-org/llama.cpp` release if this repository does not already have a
  release for that tag.
- `Track TurboQuant releases`: runs daily and builds the latest
  `TheTom/llama-cpp-turboquant` release if this repository does not already
  have the corresponding `turbo-<tag>` release.
- `Build release artifacts`: reusable and manually runnable workflow for a
  specific source repository/ref/tag.

## Provenance

There are three separate layers here:

- `ggml-org/llama.cpp`: upstream source and upstream release-package layout.
  This repo follows its tarball shape and release asset naming style.
- `TheTom/llama-cpp-turboquant`: TurboQuant source. TurboQuant builds check
  out Tom's repository directly; this repo does not vendor Tom's source.
- `openresearchtools/llama-cpp-turboquant`: OpenResearchTools build machinery
  layered on top of llama.cpp/Tom-style Dockerfiles, including ARM64 Docker
  release patterns, `GGML_RPC=ON`, NVIDIA notice/license collection, and the
  RPC image target.

This repository is only the release automation layer for
`openresearchtools/llama-cpp-arm64-builds`.
