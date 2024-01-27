import cv2
import numpy as np
from screeninfo import get_monitors
import v4l2py
from picamera2 import Picamera2, Preview, Metadata
import libcamera
from libcamera import controls
import time
import os
import io
import logging
import subprocess
import threading
import queue
from .frame_rate_monitor import FrameRateMonitor

class Picamera2CapturedImage:
	def __init__(self, frame, metadata={}):
		self.frame = frame
		self.metadata = metadata
		self.format = "jpeg"

	def to_grayscale(self):
		if self.format == 'jpeg':
			img = np.frombuffer(self.frame.getbuffer(), dtype=np.uint8)
			return cv2.imdecode(img, cv2.IMREAD_GRAYSCALE)
		else:
			raise Exception(f"CapturedImage: unknown image format {self.format}")

	def to_rgb(self):
		if self.format == 'jpeg':
			img = np.frombuffer(self.frame.getbuffer(), dtype=np.uint8)
			return cv2.imdecode(img, cv2.IMREAD_COLOR)
		else:
			raise Exception(f"CapturedImage: unknown image format {self.format}")

	def to_bytes(self):
		return self.frame.getbuffer()

import v4l2py

class Picamera2Controller:
	def __init__(self, device_id=0, controls={}):
		self.device = Picamera2()
		self.device.configure("still")
		self.device.start()
		self.controls = controls
		self.reader_fps = FrameRateMonitor("Picamera2Controller:reader", 1)
		self.capture_config = self.device.create_still_configuration()
		self.preview_config = self.device.create_preview_configuration()
		self.set_capture_mode()
		# picamera2 likes to log a lot of things
		logger = logging.getLogger('picamera2.request')
		logger.setLevel(logging.WARNING)

	def capture_frame(self, blocking=True):
		data = io.BytesIO()
		self.device.capture_file(data, format='jpeg')
		self.reader_fps.update()
		return Picamera2CapturedImage(data)

	def set_control(self, control_name, value):
		try:
			self.device.set_controls({control_name: value})
		except KeyError:
			# raise AttributeError(f"Control '{control_name}' does not exist.")
			logging.exception(f"Control '{control_name}' does not exist.")
		finally:
			return False

	def get_control(self, control_name):
		try:
			return self.device.controls[control_name]
		except KeyError:
			# raise AttributeError(f"Control '{control_name}' does not exist.")
			logging.exception(f"Control '{control_name}' does not exist.")
		finally:
			return False

	def open(self):
		self.device.start()

	def close(self):
		self.device.stop()
		
	def set_capture_mode(self):
		self.device.switch_mode(self.capture_config)

	def set_preview_mode(self):
		self.device.switch_mode(self.preview_config)
