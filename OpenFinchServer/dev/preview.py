from picamera2 import Picamera2, Preview, Metadata
import libcamera
from libcamera import controls
from pprint import *
import time
import os

os.environ["DISPLAY"] = ":0"

picam2 = Picamera2(0)

picam2.stop()
config = picam2.create_preview_configuration()
# config["size"] = (1600, 1200)
# config[]"format"] = "MJPEG"
config["transform"] = libcamera.Transform(hflip=1, vflip=1)
picam2.configure(config)

picam2.start_preview(Preview.QT)
picam2.start()

metadata = picam2.capture_metadata()
pprint(metadata)

# time.sleep(2)
picam2.set_controls({"ExposureTime": 40000, "AnalogueGain": 1.0})
picam2.set_controls({"ExposureTime": 10000, "AnalogueGain": 1.0})
picam2.set_controls({"ExposureTime": 1000, "AnalogueGain": 10.0})
picam2.set_controls({"ExposureTime": 100, "AnalogueGain": 100.0})
# picam2.configure(config)
# picam2.capture_file("test-picam2.jpg")

##

import numpy as np
overlay = np.zeros((300, 400, 4), dtype=np.uint8)
overlay[:150, 200:] = (255, 0, 0, 64) # reddish
overlay[150:, :200] = (0, 255, 0, 64) # greenish 
overlay[150:, 200:] = (0, 0, 255, 64) # blueish 
picam2.set_overlay(overlay)
