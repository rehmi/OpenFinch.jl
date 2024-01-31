
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

from .OV2311 import OV2311Defaults

class V4L2CapturedImage:
	def __init__(self, frame, metadata={}):
		self.frame = frame
		self.metadata = metadata
		self.format = frame.pixel_format.name

	def to_grayscale(self):
		if self.format == 'YUYV':
			# Convert YUYV raw data to grayscale
			return cv2.cvtColor(np.frombuffer(self.frame.data, dtype=np.uint8).reshape((1200,1600,2)), cv2.COLOR_YUV2GRAY_YUYV)
		elif self.format == 'MJPEG':
			# Decode MJPG data to grayscale
			img = np.frombuffer(self.frame.data, dtype=np.uint8)
			return cv2.imdecode(img, cv2.IMREAD_GRAYSCALE)
		else:
			raise Exception(f"CapturedImage: unknown image format {self.format}")

	def to_rgb(self):
		if self.format == 'YUYV':
			# Convert YUYV raw data to RGB
			return cv2.cvtColor(np.frombuffer(self.frame.data, dtype=np.uint8).reshape((1200,1600,2)), cv2.COLOR_YUV2RGB_YUYV)

		elif self.format == 'MJPEG':
			# Decode MJPG data to RGB
			img = np.frombuffer(self.frame.data, dtype=np.uint8)
			return cv2.imdecode(img, cv2.IMREAD_COLOR)
		else:
			raise Exception(f"CapturedImage: unknown image format {self.format}")

	def to_bytes(self):
		return self.frame.data

import v4l2py

class V4L2CameraController:
	def __init__(self, device_id='/dev/video0', controls=OV2311Defaults):
		if type(device_id) == int:
			self.device_path = f"/dev/video{device_id}"
		else:
			self.device_path = device_id
		self.device = v4l2py.Device(self.device_path)
		self.video = v4l2py.VideoCapture(self.device)
		self.iter_video = iter(self.video)
		self.control_values = controls

		self.device.open()

		for control_name, value in self.control_values.items():
			self.set_control(control_name, value)

		self.frame_queue = queue.Queue(maxsize=1)
		self.running = False
		self.reader_fps = FrameRateMonitor("V4L2CameraController:reader", 1)

	def _start_reader(self):
		self.running = True
		self.thread = threading.Thread(target=self._read_frames)
		self.thread.start()

	def _read_frames(self):
		while self.running:
			frame = next(self.iter_video)
			self.reader_fps.update()
			if not self.frame_queue.full():
				self.frame_queue.put(frame)

	def _time_video_iter(self, N=100):
		tic = time.time()
		for _ in range(N):
			next(self.iter_video)
		toc = time.time()
		fps = N/(toc-tic)
		logging.info(f"video capture rate measured to be {fps:.2f} fps")

	def _stop_reader(self):
		self.running = False
		self.thread.join()


	def capture_frame(self, blocking=True):
		if not blocking and self.frame_queue.empty():
			return None
		else:
			frame = self.frame_queue.get()
			cap = V4L2CapturedImage(frame)
			return cap


	def set_format(self, width, height, pixel_format):
		subprocess.call([
			'v4l2-ctl',
			'--set-fmt-video=width={width},height={height},pixelformat={pixel_format}'.format(
				width=width, height=height, pixel_format=pixel_format)
		])

	def open(self):
		self.video.open()
		self._start_reader()

	def close(self):
		self._stop_reader()
		self.video.close()

	def read_frame(self):
		return next(iter(self.video))

	def get_control(self, control_name):
		try:
			return self.device.controls[control_name]
		except KeyError:
			raise AttributeError(f"Control '{control_name}' does not exist.")

	def set_control(self, control_name, value):
		try:
			control = self.device.controls[control_name]
			# You may need to check the control type and range before setting it
			control.value = value
		except KeyError:
			raise AttributeError(f"Control '{control_name}' does not exist.")
