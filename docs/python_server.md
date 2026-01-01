# OpenFinchServer Python Server

This document provides a detailed overview of the Python server component of the OpenFinch project.

## `OpenFinchServer/web/server.py`

This is the core of the Python server. It is an `aiohttp`-based web server that provides real-time control over the hardware.

### Key Classes

-   **`CameraServer`**: The main class that manages the server's state and functionality.
    -   Initializes the camera and system controllers.
    -   Manages WebSocket connections.
    -   Handles HTTP requests for serving the web interface and control endpoints.
    -   Contains the main application logic for capturing images, processing data, and broadcasting updates.
-   **`MessageHandler`**: A dedicated class for parsing and handling incoming WebSocket messages.
    -   Maps message types to specific handler functions.
    -   Decouples the message parsing logic from the main `CameraServer` class, improving code organization.

### WebSocket API

The server uses a WebSocket-based API for real-time communication with the Julia client. Messages are sent in JSON format.

#### Client-to-Server Messages

-   **Control Commands**: The client can send messages to set various hardware parameters.
    -   `set_control`: A generic message to set a control value.
        -   Example: `{"set_control": {"brightness": 50}}`
    -   Specific control messages for camera settings (e.g., `exposure_absolute`, `contrast`), LED timing (`LED_TIME`, `LED_WIDTH`), and other parameters.
-   **Streaming Control**:
    -   `stream_frames`: Enable or disable video streaming.
        -   Example: `{"stream_frames": {"value": true}}`
    -   `send_fps_updates`: Request or cancel real-time FPS updates.
        -   Example: `{"send_fps_updates": {"value": true}}`
-   **SLM Control**:
    -   `slm_image_url`: Send a URL to an image to be displayed on the SLM.
    -   `slm_image`: Send a base64-encoded image to be displayed on the SLM.

#### Server-to-Client Messages

-   **Image Data**:
    -   `image_response`: A message containing a captured image. The image can be sent as a binary blob or as a base64-encoded string, depending on the client's preference.
-   **Metadata and Status**:
    -   `update_controls`: Provides the client with the current values of all available controls.
    -   `fps_update`: Sends real-time FPS data for different parts of the capture pipeline.
-   **Configuration Updates**:
    -   The server will broadcast updates to control values (e.g., `LED_TIME`) to all connected clients when they are changed.

### Hardware Control Packages

-   **`camera/`**: This package abstracts the details of camera control.
    -   **`captures/`**: Contains different camera backend implementations.
        -   `picamera2.py`: For Raspberry Pi cameras using the `picamera2` library.
        -   `v4l2.py`: For V4L2-compatible cameras.
    -   **`controllers/`**:
        -   `system.py`: The `SystemController` class orchestrates the camera, GPIO, and other hardware components to ensure synchronized operation.
-   **`gpio/`**: This package provides low-level control of GPIO pins.
    -   `sequencer.py` and `wavegen.py`: These modules are likely used for generating complex, timed sequences of GPIO events, which are essential for triggering the camera and LEDs with high precision.
