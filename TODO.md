# Project Exploration and Documentation Plan

This document outlines the plan for exploring and documenting the OpenFinch repository.

## Phase 1: Code Exploration (Done)

- [x] Systematically go through the `notebooks` and `misc` directories to understand the experiments and research that have been done.
- [x] Summarize the findings from the notebooks in `docs/notebook_summary.md`.
- [x] Summarize the findings from the misc code in `docs/misc_summary.md`.

## Phase 2: Initial Exploration (Done)

- [x] Review top-level `README.md` to understand project purpose.
- [x] Examine `Project.toml` to identify dependencies and project structure.
- [x] Analyze `src/OpenFinch.jl` to understand the main application entry point.
- [x] Investigate `src/CameraControl.jl` to understand hardware interaction.
- [x] Study `src/SLM.jl` to understand Spatial Light Modulator control.
- [x] Review `src/RPYC.jl` to understand the remote procedure call mechanism.
- [x] Analyze `src/Dashboard.jl` to understand the user interface.
- [x] List contents of `OpenFinchServer` to get an overview of the Python server.
- [x] Examine `OpenFinchServer/web/server.py` to understand the server implementation.

## Phase 3: Documentation (Done)

- [x] Create a `docs` directory for project documentation.
- [x] Create `docs/architecture.md` to document the overall project architecture, including a diagram showing the relationship between the Julia application and the Python server.
- [x] Create `docs/julia_modules.md` to detail the purpose and functionality of each Julia module (`CameraControl`, `SLM`, `RPYC`, `Dashboard`).
- [x] Create `docs/python_server.md` to document the Python server's API, WebSocket message format, and control logic.
- [x] Create `docs/hardware.md` to document the hardware setup, including the camera, SLM, and any custom electronics.

## Phase 4: Future Work (Done)

- [x] Propose a plan for future development and improvements based on the exploration.
- [x] Identify areas for refactoring and code cleanup.
- [x] Suggest potential new features or capabilities.
