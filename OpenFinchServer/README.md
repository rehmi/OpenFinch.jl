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
### Modify `udev` rules to allow changing IMX296 trigger mode

### Modifying Sysfs File Permissions for the IMX296 Module

By following these instructions, you can modify the `trigger_mode` file permissions of the IMX296 module, allowing user programs to write values to it without needing root access. This concise guide will walk you through setting up a `udev` rule to allow non-root users to write to the `trigger_mode` parameter of the IMX296 module.

1. **Identify the Target File:**
   - The file in question is located at `/sys/module/imx296/parameters/trigger_mode`.

2. **Create a Udev Rule File:**
   - Open your terminal.
   - Navigate to `/etc/udev/rules.d/`.
   - Use a text editor (e.g., `nano` or `vim`) to create a new file named `99-imx296-permissions.rules`.

     ```
     sudo nano /etc/udev/rules.d/99-imx296-permissions.rules
     ```

3. **Write the Rule:**
   - In the newly created file, input the following udev rule:

     ```
     ACTION=="add", SUBSYSTEM=="module", KERNEL=="imx296", RUN+="/bin/chmod 0666 /sys/module/imx296/parameters/trigger_mode"
     ```

   - This rule changes the permissions of `trigger_mode` to `0666` (read and write for everyone) when the IMX296 module is loaded.

4. **Reload Udev Rules:**
   - To apply your new rule, reload the udev rules with the following commands:

     ```
     sudo udevadm control --reload-rules
     sudo udevadm trigger
     ```

5. **Verify:**
   - Ensure the rule works by checking the permissions of the `trigger_mode` file:

     ```
     ls -l /sys/module/imx296/parameters/trigger_mode
     ```

   - If done correctly, the permissions should reflect the changes made by your udev rule.

## Usage

Navigate to `http://localhost:8000` to access the web interface for camera configuration and image viewing.

For API details and WebSocket communication, see the `web/server.py` file.

## Contributing

Contributions are welcome. Please submit changes via GitHub pull requests.

## License

Licensed under the MIT License. See the LICENSE file for details.
