# OpenFinch Hardware

This document provides an overview of the hardware components and interfaces used in the OpenFinch project.

## Core Components

The OpenFinch system is designed around a core set of hardware components that enable advanced computational imaging experiments.

-   **Single-Board Computer (SBC)**: The hardware is controlled by a single-board computer, most likely a **Raspberry Pi**. This is indicated by the use of the `picamera2` and `pigpio` libraries, which are specific to the Raspberry Pi platform.
-   **Camera**: The system uses a camera for image acquisition. The `camera` package in the Python server supports multiple backends, suggesting that different types of cameras can be used.
    -   **Raspberry Pi Camera Module**: The `picamera2` backend indicates direct support for the official Raspberry Pi cameras.
    -   **V4L2-Compatible Cameras**: The `v4l2` backend allows for the use of any camera that is compatible with the Video4Linux2 driver, which includes a wide range of USB webcams and other cameras.
-   **Spatial Light Modulator (SLM)**: An SLM is used to modulate the phase or amplitude of a light field. This is a key component for applications like holography. The `SLM.jl` module and the SLM-related message handlers in the Python server indicate that the system is designed to control an SLM, likely by treating it as a secondary display.
-   **Illumination**: The system includes controllable illumination sources, likely LEDs. The `LED_TIME` and `LED_WIDTH` parameters in the Python server, as well as the GPIO control logic, suggest that the timing and duration of the illumination can be precisely controlled.

## Hardware Interfaces

The different hardware components are controlled through various interfaces.

-   **GPIO**: The General-Purpose Input/Output (GPIO) pins on the Raspberry Pi are used for low-level hardware control and synchronization.
    -   **`pigpio` Library**: The project uses the `pigpio` library, which provides high-speed, precise control over the GPIO pins. This is essential for tasks that require microsecond-level timing, such as triggering the camera and LEDs.
    -   **Synchronization**: The GPIO pins are used to send and receive trigger signals, ensuring that the camera, SLM, and illumination are all synchronized.
-   **Camera Serial Interface (CSI)**: The Raspberry Pi Camera Modules connect to the SBC via the CSI port, which is a high-speed interface designed for cameras.
-   **USB**: V4L2-compatible cameras are typically connected via USB.
-   **HDMI/DVI**: The SLM is likely connected to the SBC via an HDMI or DVI port and is treated as a standard display. The `screeninfo` library is used to identify and control the SLM display.

## System Operation

The hardware components are orchestrated by the Python server running on the Raspberry Pi.

1.  The Julia application sends a command to the Python server via RPyC or WebSocket.
2.  The Python server receives the command and translates it into the appropriate hardware control signals.
3.  For a typical capture sequence:
    -   The server might first send an image to be displayed on the SLM.
    -   Then, it would use the `pigpio` library to generate a precisely timed waveform on the GPIO pins.
    -   This waveform would trigger the illumination (e.g., turn on an LED) and the camera shutter simultaneously.
    -   The camera captures an image and sends it back to the server.
    -   The server then streams the image to the Julia application for display and analysis.
