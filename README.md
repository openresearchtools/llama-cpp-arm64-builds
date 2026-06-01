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
They follow the upstream llama.cpp Linux release shape: `build/bin` is archived
after adding the upstream `LICENSE`. The tarballs keep all built tools,
`rpc-server`, and CPU backend variants produced by the build.

The CUDA build uses NVIDIA's Debian 13 SBSA CUDA 13.2 packages at build time, but
does not bundle NVIDIA CUDA runtime libraries or driver libraries. CUDA runtime
libraries such as `libcudart`, `libcublas`, `libcublasLt`, and the NVIDIA driver
library `libcuda.so` must come from the target machine.

Release tarballs follow the upstream llama.cpp layout: a single
`llama-<tag>/` directory containing the built binaries and shared libraries,
including `rpc-server`.

## Workflows

- `Track llama.cpp releases`: runs monthly and builds the latest upstream
  `ggml-org/llama.cpp` release if this repository does not already have a
  release for that tag.
- `Track TurboQuant releases`: runs monthly and builds the latest
  `TheTom/llama-cpp-turboquant` release if this repository does not already
  have the corresponding `turbo-<tag>` release.
- `Build release artifacts`: reusable and manually runnable workflow for a
  specific source repository/ref/tag.

## Provenance

There are three separate layers here:

- `ggml-org/llama.cpp`: upstream source and upstream Linux release-package
  layout. This repo follows its tarball shape and release asset naming style.
- `TheTom/llama-cpp-turboquant`: TurboQuant source. TurboQuant builds check
  out Tom's repository directly; this repo does not vendor Tom's source.
- `openresearchtools/llama-cpp-turboquant`: OpenResearchTools build machinery
  layered on top of llama.cpp/Tom-style Dockerfiles, including ARM64 Docker
  release patterns, `GGML_RPC=ON`, and the RPC image target.

This repository is only the release automation layer for
`openresearchtools/llama-cpp-arm64-builds`.
