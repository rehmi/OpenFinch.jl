# OpenFinchServer

OpenFinchServer is a server application designed for camera control and image processing. It supports various camera models, including IMX296 and OV2311, and integrates functionalities for real-time image capture, processing, and GPIO interactions. The server is built with Python and offers a web interface for remote operations.

## Features

- **Camera Control**: Customizable settings for exposure, gain, and other parameters for supported camera models.
- **GPIO Integration**: Interfaces for controlling GPIO pins for synchronized operations with external hardware.
- **Real-time Image Processing**: On-the-fly image adjustments and processing capabilities.
- **Web Interface**: A web server for remote camera control and configuration, including real-time data streaming.
- **Waveform Generation**: Utilities for generating waveforms for timing control.
- **Modular Design**: Easy integration of new camera models and hardware interfaces.

## Installation

### Prerequisites

- Python 3.6 or higher
- Required libraries: pigpio, OpenCV-Python, aiohttp, numpy, pillow, screeninfo, v4l2py, picamera2

### Setup

1. **Clone the Repository**

```bash
git clone https://github.com/your-repository/OpenFinchServer.git
cd OpenFinchServer
```

2. **Install Dependencies**

For a standard installation:

```bash
pip install .
```

For a development (editable) installation:

```bash
pip install -e .
```

3. **Configure pigpio**

Start the pigpio daemon for GPIO control:

```bash
sudo pigpiod
```

4. **Camera Configuration**

Modify settings in `camera/models/IMX296.py` and `camera/models/OV2311.py` as needed.

5. **Start the Server**

```bash
python web/main.py
```

## Usage

Navigate to `http://localhost:8000` to access the web interface for camera configuration and image viewing.

For API details and WebSocket communication, see the `web/server.py` file.

## Contributing

Contributions are welcome. Please submit changes via GitHub pull requests.

## License

Licensed under the MIT License. See the LICENSE file for details.
