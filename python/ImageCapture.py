import cv2
import numpy as np
from screeninfo import get_monitors
import v4l2py
import time
import os
import subprocess

class ImageCapture:
	def __init__(self, device_path='/dev/video0', capture_raw=False):
		self.device_path = device_path
		self.capture_raw = capture_raw
		self.device = v4l2py.Device(self.device_path)
		self.video = v4l2py.VideoCapture(self.device)
		self.iter_video = iter(self.video)

		if capture_raw:
			subprocess.call(['v4l2-ctl', '--set-fmt-video=width=1600,height=1200,pixelformat=YUYV'])
		else:
			subprocess.call(['v4l2-ctl', '--set-fmt-video=width=1600,height=1200,pixelformat=MJPG'])

	def open(self):
		self.device.open()
		self.video.open()

	def close(self):
		self.video.close()
		self.device.close()

	def capture_frame(self):
		frame = next(self.iter_video)
		if self.capture_raw:
			pass  
		else:
			img = np.frombuffer(frame.data, dtype=np.uint8)
			img = cv2.imdecode(img, cv2.IMREAD_COLOR)
		return img
	
	def controls(self):
		return self.device.controls

	def control(self, control_name):
		return self.device.controls[control_name]

	def control_set(self, control_name, value):
		self.device.controls[control_name].value = value
  
	def control_get(self, control_name):
		return self.device.controls[control_name]
