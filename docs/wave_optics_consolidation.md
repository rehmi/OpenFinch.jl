# Wave Optics Consolidation Plan

This document outlines the strategy for consolidating the scattered wave optics code in `notebooks/` and `misc/` into a unified, reusable package structure within `src/`.

## Current State Analysis

The codebase currently contains multiple implementations of core optical propagation algorithms and data structures, primarily derived from Voelz's "Computational Fourier Optics" and custom ArrayFire-accelerated implementations.

### Key Findings

1.  **Duplication**:
    *   **Propagators**: `propTF`, `propIR`, `propFF`, `prop2step` appear in `misc/optics.jl`, `misc/voelz.jl`, and `notebooks/waveopt.pluto.jl`.
    *   **Primitives**: `circ`, `rect`, `jinc`, `seidel_5` are duplicated in `misc/voelz.jl` and `notebooks/waveopt.pluto.jl`.
    *   **Data Structures**: `PhasorField` and `LightField` are defined in `misc/optics.jl` and `notebooks/waveopt.pluto.jl`.
    *   **GPU Utils**: `af_conv` and `af_pad` are in `misc/` and re-implemented/pasted in notebooks.

2.  **Implementations**:
    *   **CPU**: Standard FFTW-based implementations following Voelz.
    *   **GPU**: ArrayFire-based implementations (`acc_*` functions, `af_conv`) for high-performance propagation.

3.  **Abstractions**:
    *   There is an emerging abstraction using `Propagator` types (`PropFresnel`, `PropTF`, etc.) to dispatch `propagate()` calls, which is a good pattern to preserve and formalize.

## Proposed Architecture

We will consolidate these into a new module structure under `src/WaveOptics/` (or integrated into `src/OpenFinch.jl` if preferred, but a submodule is cleaner).

### 1. Types (`src/WaveOptics/Types.jl`)
*   `PhasorField`: Complex amplitude field.
*   `LightField`: Multi-wavelength complex field.
*   `Grid` / `Plane`: Geometry definitions (from `waveopt.pluto.jl`).

### 2. Primitives (`src/WaveOptics/Primitives.jl`)
*   **Shapes**: `circ`, `rect`, `jinc`, `tri`.
*   **Optical Elements**: `thin_lens`, `spherical_wavefront`, `tilt`, `focus`.
*   **Aberrations**: `seidel_5`.

### 3. Propagation (`src/WaveOptics/Propagation.jl`)
*   **Interface**: `propagate(field, dist, ...; method=PropFresnel())`.
*   **Methods**:
    *   `PropTF` (Transfer Function)
    *   `PropIR` (Impulse Response)
    *   `PropFF` (Fraunhofer)
    *   `Prop2Step` (Two-step Fresnel)
    *   `PropFresnel` (Adaptive/Default)

### 4. Backend / Acceleration (`src/WaveOptics/Backend.jl`)
*   **Goal**: Deprecate `ArrayFire.jl` in favor of `KernelAbstractions.jl` to support a wider range of hardware (CUDA, AMD, Metal, CPU).
*   **Abstraction Layer**:
    *   Implement kernels using `@kernel` macro from `KernelAbstractions`.
    *   Use `AbstractFFTs.jl` interface to dispatch to appropriate FFT implementations (`CUDA.CUFFT`, `AMDGPU.rocFFT`, `Metal.MPS`, `FFTW`).
    *   We may need to implement a lightweight wrapper or trait-based system to handle backend-specific FFT plan creation and execution, as `KernelAbstractions` does not provide FFTs out of the box.
*   **Migration**:
    *   Rewrite `af_conv` and `af_pad` using generic array operations or custom kernels.
    *   Port `acc_*` primitive generators to `KernelAbstractions` kernels.

### 5. FFT Strategy for KernelAbstractions

Since `KernelAbstractions.jl` does not provide FFT functionality, we must rely on the ecosystem's `AbstractFFTs.jl` interface and backend-specific implementations.

*   **Interface**: Code should be written against `AbstractFFTs.fft` and `AbstractFFTs.ifft`.
*   **Backends**:
    *   **CUDA**: `CUDA.jl` provides `CUFFT` which implements the `AbstractFFTs` interface for `CuArray`.
    *   **AMDGPU**: `AMDGPU.jl` provides `rocFFT` for `ROCArray`.
    *   **Metal**: `Metal.jl` has FFT support via Metal Performance Shaders, but verification of `AbstractFFTs` compliance is needed.
    *   **CPU**: `FFTW.jl` is the standard for `Array`.
*   **Package Extensions**: Use Julia's package extensions (Julia 1.9+) to load backend-specific optimizations or plan caching mechanisms only when the corresponding backend package (e.g., `CUDA`, `Metal`) is loaded by the user.

### 6. Algorithms (`src/WaveOptics/Algorithms.jl`)
*   `gerchberg_saxton`
*   `binary_gerchberg_saxton`
*   Any other high-level iterative algorithms.

## Action Plan

1.  **Create Directory Structure**: Set up `src/WaveOptics/`.
2.  **Migrate Types**: Extract `PhasorField` and `LightField` definitions.
3.  **Migrate Primitives**: Consolidate Voelz implementations.
4.  **Refactor Propagation**:
    *   Define the `Propagator` abstract type hierarchy.
    *   Implement the CPU versions first.
    *   Port the ArrayFire versions, ensuring they hook into the same high-level API (dispatching on `AFArray` inputs).
5.  **Clean Up**:
    *   Update `misc/optics.jl` to use the new package structure (or deprecate it).
    *   Update notebooks to import from the new module instead of defining functions inline.

## Open Questions

*   **Dependency Management**: Should `ArrayFire` be a hard dependency or an extension? Given the project seems heavily reliant on it for performance, a hard dependency might be acceptable for `OpenFinch`.
*   **Naming**: Should this be a standalone package `WaveOptics.jl` inside the repo, or just a module `OpenFinch.WaveOptics`?

## Performance Benchmarks

To validate the feasibility of using `KernelAbstractions.jl` with `Metal.jl` on Apple Silicon, a series of benchmarks were performed. The goal was to compare the performance of a custom `KernelAbstractions.jl` kernel against a CPU-based implementation for a simple pointwise multiplication task.

### Key Findings

*   **Small Arrays (256x256)**: The CPU is significantly faster due to the overhead of launching a GPU kernel.
*   **Medium Arrays (1024x1024)**: The GPU begins to show a performance advantage.
*   **Large Arrays (3840x3840)**: The GPU is significantly faster, demonstrating the benefits of parallelization for large datasets.

### Conclusion

The `KernelAbstractions.jl` toolchain is working correctly on the Metal backend and scales well for large arrays. This gives us confidence that we can proceed with implementing the wave optics package using `KernelAbstractions.jl` and `Metal.jl`. However, the lack of a direct FFT implementation in `Metal.jl` remains a challenge that will need to be addressed.

