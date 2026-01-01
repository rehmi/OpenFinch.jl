# OpenFinch Future Work and Improvement Proposals

This document outlines potential areas for future development, refactoring, and new features for the OpenFinch project.

## 1. Code Refactoring and Cleanup

While the project is highly functional, there are several areas where the code could be refactored to improve clarity, maintainability, and performance.

-   **Consolidate Optical Propagation Functions**: The optical propagation functions in `misc/optics.jl` are more advanced and feature-rich than those in the `notebooks`. These should be consolidated into a single, well-documented module within the main `src` directory.
-   **Standardize GPU Acceleration**: The project uses both `ArrayFire.jl` and `PyTorch` for GPU acceleration. A decision should be made to standardize on one of these backends to simplify the codebase and reduce dependencies. Given the project's use of PyTorch for other potential machine learning tasks, it might be the better long-term choice.
-   **Improve Configuration Management**: Many parameters, such as hardware settings and simulation parameters, are currently hard-coded in the scripts. A more robust configuration management system (e.g., using TOML or JSON files) would make the project more flexible and easier to use.
-   **Add Unit Tests**: The project currently lacks a comprehensive suite of unit tests. Adding tests for the core optical simulation functions and hardware control modules would improve the project's reliability and make it easier to maintain.

## 2. New Features and Capabilities

The current platform provides a strong foundation for adding new and exciting capabilities.

-   **Machine Learning-Based Hologram Generation**: The project's use of PyTorch opens up the possibility of using deep learning for hologram generation. This could lead to higher-quality holograms that are generated more quickly than with traditional algorithms like Gerchberg-Saxton.
-   **Closed-Loop Optimization**: The system could be extended to perform closed-loop optimization of the SLM patterns. This would involve capturing an image with the camera, comparing it to a target image, and then using an optimization algorithm to update the SLM pattern to minimize the difference.
-   **Advanced 3D Displays**: The platform could be used to develop more advanced 3D holographic displays, potentially using techniques like holographic stereograms or multi-plane holography.
-   **Integration with Other Scientific Libraries**: The project could be integrated with other scientific libraries in the Julia ecosystem, such as `DifferentialEquations.jl` for modeling more complex physical phenomena or `Makie.jl` for advanced 3D visualizations.

## 3. Documentation and Usability

-   **API Documentation**: The new documentation in the `docs` directory provides a good overview of the project, but more detailed API documentation for each function and module would be beneficial. This could be generated automatically from the code using a tool like `Documenter.jl`.
-   **Examples and Tutorials**: Creating a set of examples and tutorials would make it easier for new users to get started with the project. These could cover topics like setting up the hardware, running a basic simulation, and generating a hologram.
-   **Project Website**: A dedicated project website could be created to showcase the project's capabilities, provide documentation, and build a community around the project.
