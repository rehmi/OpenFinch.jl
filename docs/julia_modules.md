# OpenFinch.jl Julia Modules

This document provides a detailed overview of the core Julia modules in the `OpenFinch.jl` application.

## `src/OpenFinch.jl`

This is the main module of the application. It serves as the entry point and is responsible for loading and re-exporting the other core modules.

## `src/Dashboard.jl`

The `Dashboard.jl` module provides a web-based user interface for controlling the OpenFinch hardware and viewing real-time data.

-   **Core Technology**: It is built using `JSServe.jl`, a library for creating interactive web UIs in pure Julia.
-   **Functionality**:
    -   **Live Camera Feed**: Displays a live video stream from the camera.
    -   **Hardware Control**: Provides interactive widgets (sliders, buttons, checkboxes) to control camera settings (e.g., exposure, gain), trigger lasers, and manage other hardware components.
    -   **Real-time Updates**: Uses WebSockets to maintain a persistent connection with the client, allowing for real-time updates of the UI and hardware status.
-   **Key Functions**:
    -   `display_dashboard()`: Launches the web-based dashboard.
    -   `start_connection()`: Establishes a connection to the remote Python server.
    -   `stop_connection()`: Closes the connection to the server.

## `src/RPYC.jl`

This module implements the client-side logic for Remote Python Call (RPyC), enabling seamless interoperability between Julia and Python.

-   **Core Technology**: It uses `PythonCall.jl` to wrap the Python `rpyc` library.
-   **Functionality**:
    -   **Remote Connection**: Establishes an SSH connection to a remote machine and starts an RPyC server.
    -   **Proxy Objects**: Allows Julia to interact with Python objects on the remote server as if they were local Julia objects.
    -   **Remote Execution**: Enables the execution of Python code on the remote server from within the Julia environment.
-   **Key Structs**:
    -   `RemotePython`: An abstract type for remote Python connections.
    -   `RPYCClassic`: A concrete implementation of `RemotePython` that uses `plumbum` and `zerodeploy` for robust SSH-based connections.

## `src/SLM.jl`

The `SLM.jl` module is responsible for controlling the Spatial Light Modulator (SLM).

-   **Functionality**:
    -   **Image Display**: Sends images to the SLM to be displayed. This is used to project patterns for holographic reconstruction or other optical experiments.
    -   **Remote Control**: It uses the `RPYC.jl` module to communicate with the Python server, which in turn controls the SLM display using libraries like `pygame` or `OpenCV`.
-   **Key Structs**:
    -   `SLMDisplay`: Represents a connection to a remote SLM display.

## `src/CameraControl.jl`

This module provides low-level control over the camera and other hardware components, with a focus on precise timing and synchronization.

-   **Core Technology**: It uses `PythonCall.jl` to interface with the `pigpio` Python library, which provides high-performance GPIO control on the Raspberry Pi.
-   **Functionality**:
    -   **GPIO Scripting**: Defines a `PiGPIOScript` struct to create, manage, and run `pigpio` scripts. This allows for complex sequences of GPIO operations with microsecond-level timing.
    -   **Waveform Generation**: Includes functions like `trigger_wave_script` to generate and transmit waveforms for triggering the camera and LEDs in a synchronized manner.
    -   **Hardware Synchronization**: Enables the precise coordination of the camera, SLM, and illumination sources, which is critical for many computational imaging techniques.
