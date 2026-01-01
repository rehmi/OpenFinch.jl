# OpenFinch Miscellaneous Code Summary

This document summarizes the key findings from the scripts and notebooks in the `misc` directory. This directory serves as a repository for experimental code, utilities, and alternative implementations.

## Overview

The `misc` directory contains a diverse collection of files that provide deeper insights into the project's development process and its underlying technologies. The code here is more experimental than in the main `src` directory, but it reveals the breadth of the project's capabilities and the different approaches that have been explored.

## Key Topics and Scripts

### Advanced Optical Propagation

-   **`optics.jl`**: This is a significant file that contains a rich library of functions for optical simulation.
    -   **Multiple Propagation Methods**: It implements several different algorithms for simulating wave propagation, including:
        -   `propIR`: Impulse Response method.
        -   `propTF`: Transfer Function method.
        -   `propFF`: Fraunhofer Far-Field approximation.
        -   `prop2step`: A two-step Fresnel propagation method.
    -   **GPU Acceleration**: The script makes extensive use of `ArrayFire.jl` for GPU acceleration, indicating a strong focus on high-performance computing.
    -   **Data Structures**: It defines `LightField` and `PhasorField` data structures for representing and manipulating optical fields, suggesting a sophisticated and well-structured approach to simulation.
-   **`waveopt_pluto.jl`**: This Pluto notebook likely provides an interactive environment for experimenting with the wave optics functions defined in `optics.jl`.

### Experimental and Alternative Implementations

-   The presence of numerous files with names like `waveopt backup 1.jl`, `prop_obsolete.jl`, and `proptest_borked.jl` indicates that the `misc` directory is a place where different ideas are tried out and iterated upon. This is a normal and healthy part of the research and development process.

### Utility Scripts

-   **`sendimage.jl`**: This script likely contains code for sending images to the SLM or another display, providing a utility for testing the display functionality.
-   **`test_VideoIO.jl`**: This script suggests that the `VideoIO.jl` library has been used or tested, possibly for reading and writing video files or for camera interfacing.

## Summary of Findings

The code in the `misc` directory reinforces the conclusions drawn from the `notebooks` directory and provides additional details:

-   **Deep Expertise in Optics**: The variety and sophistication of the optical propagation algorithms demonstrate a deep understanding of computational optics.
-   **Commitment to High Performance**: The consistent use of GPU acceleration with both `ArrayFire.jl` and `PyTorch` shows that performance is a key consideration in the project.
-   **Iterative Development Process**: The presence of backup files, obsolete code, and experimental scripts provides a realistic view of the project's development history and the iterative process of building a complex scientific computing application.
-   **Broad Toolset**: The developers are comfortable using a wide range of tools and libraries, including `Pluto.jl` for interactive computing, `ArrayFire.jl` for GPU acceleration, and various Julia packages for image and video processing.

## Code Repetition and Consolidation Opportunities

The `misc` directory contains the source of truth for many functions duplicated in the notebooks.

### Core Optical Functions
-   **`optics.jl`**: Defines the core `PhasorField` and `LightField` types, along with the `propagate` dispatch mechanism and specific implementations (`propFresnel`, `propTF`, `propIR`, `prop2step`).
-   **`voelz.jl`**: Contains the CPU-based implementations of optical primitives (`circ`, `rect`, etc.) and propagators, derived from Voelz's MATLAB tutorial.

### GPU Acceleration
-   **`af_conv.jl`**: Contains the custom `af_conv` function for ArrayFire convolution, which handles padding and expansion logic.
-   **`af_pad.jl`**: Implements `af_pad` for padding ArrayFire arrays, a dependency for `af_conv`.

These files should serve as the basis for the proposed `WaveOptics` module. Consolidating them will eliminate the need for copy-pasting code into notebooks and ensure a single source of truth for these critical algorithms.
