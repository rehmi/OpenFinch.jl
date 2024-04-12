import picamera2
from picamera2 import Picamera2, libcamera

p = Picamera2()

p.start()

p.controls
p.camera_ctrl_info
p.camera_controls
p.camera_properties
p.camera_config
p.capture_metadata()

p.set_controls({'ColourGains': (0.1, 1)})
