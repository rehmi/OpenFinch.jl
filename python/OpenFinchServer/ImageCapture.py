import cv2
import numpy as np
from screeninfo import get_monitors
import v4l2py
import time
import os
import logging
import subprocess
import threading
import queue
from .frame_rate_monitor import FrameRateMonitor

class ImageCapture:
	def __init__(self, device_path='/dev/video0', capture_raw=False, controls={}):
		self.device_path = device_path
		self.capture_raw = capture_raw
		self.device = v4l2py.Device(self.device_path)
		self.video = v4l2py.VideoCapture(self.device)
		self.iter_video = iter(self.video)

		if capture_raw:
			subprocess.call(['v4l2-ctl', '--set-fmt-video=width=1600,height=1200,pixelformat=YUYV'])
		else:
			subprocess.call(['v4l2-ctl', '--set-fmt-video=width=1600,height=1200,pixelformat=MJPG'])
		
		self.device.open()
  
		for control_name, value in controls.items():
			self.control_set(control_name, value)
   
		self.frame_queue = queue.Queue(maxsize=3)
		self.running = False
		self.reader_fps = FrameRateMonitor("ImageCapture reader", 5)
		self.capture_fps = FrameRateMonitor("ImageCapture capture", 5)
  
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

	def capture_frame(self, blocking=True):
		if not blocking and self.frame_queue.empty():
			return None
		else:
			self.capture_fps.update()
			frame = self.frame_queue.get()
			if self.capture_raw:
				img = cv2.cvtColor(np.frombuffer(frame.data, dtype=np.uint8).reshape((1200,1600,2)), cv2.COLOR_YUV2GRAY_YUYV)
			else:
				img = np.frombuffer(frame.data, dtype=np.uint8)
				img = cv2.imdecode(img, cv2.IMREAD_GRAYSCALE)
			return img

		# return self._next_frame()
		# return self.last_frame

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

	def open(self):
		# self.device.open()
		self.video.open()
		self._start_reader()

	def close(self):
		self._stop_reader()
		self.video.close()
		# self.device.close()
  
	def __del__(self):
		self.device.close()
	
	def controls(self):
		return self.device.controls

	def control(self, control_name):
		return self.device.controls[control_name]

	def control_set(self, control_name, value):
		try:
			control = self.device.controls[control_name]
			if isinstance(control, v4l2py.device.IntegerControl):
				if not control.minimum <= value <= control.maximum:
					raise ValueError(f"Value '{value}' is outside the allowable range for control '{control_name}'.")
			elif isinstance(control, v4l2py.device.BooleanControl):
				if value not in [True, False]:
					raise ValueError(f"Value '{value}' is not a valid boolean value.")
			# Add checks for other control types as needed
			control.value = value
		except KeyError:
			raise AttributeError(f"Control '{control_name}' does not exist.")

	def control_get(self, control_name):
		try:
			return self.device.controls[control_name]
		except KeyError:
			raise AttributeError(f"Control '{control_name}' does not exist.")
