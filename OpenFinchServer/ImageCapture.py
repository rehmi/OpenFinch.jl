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
from ._v4l2 import V4L2CapturedImage, V4L2CameraController
from ._picamera2 import Picamera2CapturedImage, Picamera2Controller

class ImageCapture:
	def __init__(self, device_id=0, capture_raw=False, controls={}):
		self.capture_raw = capture_raw
		self.capture_fps = FrameRateMonitor("ImageCapture:capture", 1)
  
		if False:
			self.device = V4L2CameraController(device_id, controls)
			self.reader_fps = self.device.reader_fps

			pixel_format = 'YUYV' if capture_raw else 'MJPG'
			self.device.set_format(width=1600, height=1200, pixel_format=pixel_format)

			for control_name, value in controls.items():
				self.control_set(control_name, value)

		else:
			self.device = Picamera2Controller(device_id, controls)
   
	def get_capture_fps(self):
		return self.capture_fps.get_fps()
  
	def get_reader_fps(self):
		return self.device.reader_fps.get_fps()

	def capture_frame(self, blocking=True):
		cap = self.device.capture_frame(blocking=blocking)
		if cap is not None:
			self.capture_fps.update()
		return cap

	def capture_raw(self, blocking=True):
		cap = self.capture_frame(blocking=blocking)
		return cap.to_bytes()

	def capture_rgb(self, blocking=True):
		cap = self.capture_frame(blocking=blocking)
		return cap.to_rgb()

	def capture_grayscale(self, blocking=True):
		cap = self.capture_frame(blocking=blocking)
		return cap.to_grayscale()

	def open(self):
		self.device.open()
		# self.video.open()
		# self._start_reader()

	def close(self):
		# self._stop_reader()
		# self.video.close()
		self.device.close()

	# def __del__(self):
		# self.device.close()
	
	def controls(self):
		return self.device.controls

	def control(self, control_name):
		return self.device.controls[control_name]

	def control_set(self, control_name, value):
		return self.device.set_control(control_name, value)

	def control_get(self, control_name):
		return self.device.get_control(control_name)
