import cv2
import numpy as np
from screeninfo import get_monitors
import os
import logging
import requests

class Display:
	def __init__(self, window_name='image', monitor_index=0):
		if 'DISPLAY' not in os.environ:
			os.environ['DISPLAY'] = ':0'

		self.monitor_index = monitor_index
		self.window_name = window_name
		cv2.namedWindow(self.window_name, cv2.WND_PROP_FULLSCREEN)
		self.move_to_monitor(self.monitor_index)
  
	def move_to_monitor(self, idx=None):
		if idx != None:
			self.monitor_index = idx
		monitors = get_monitors()
		if len(monitors) > self.monitor_index:
			monitor = monitors[self.monitor_index]
			cv2.moveWindow(self.window_name, monitor.x, monitor.y)
			cv2.setWindowProperty(self.window_name, cv2.WND_PROP_FULLSCREEN, cv2.WINDOW_FULLSCREEN)
		else:
			logging.info(f"Not enough monitors detected. Make sure you have at least {self.monitor_index + 1} monitors connected.")

	def set_image_url(self, url):
		response = requests.get(url)
		img_bytes = np.asarray(bytearray(response.content), dtype="uint8")
		self.image = cv2.imdecode(img_bytes, cv2.IMREAD_COLOR)
		return self.image

	def set_image(self, img):
		self.image = img

	def display_image(self):
		# self.move_to_monitor(self.monitor_index)
		cv2.imshow(self.window_name, self.image)
  
	def hide_window(self):
		cv2.moveWindow(self.window_name, -100, -100)

	def unhide_window(self):
		monitors = get_monitors()
		if len(monitors) > self.monitor_index:
			monitor = monitors[self.monitor_index]
			cv2.moveWindow(self.window_name, monitor.x, monitor.y)

	def resize(self, width, height):
		cv2.resizeWindow(self.window_name, width, height)

	def move(self, x, y):
		cv2.moveWindow(self.window_name, x, y)

	def destroy_window(self):
		cv2.destroyWindow(self.window_name)

	def update(self):
		cv2.waitKey(1)

	def show_frame(self, img):
		self.set_image(img)
		self.display_image()
		self.update()

	def waitKey(self, t=1):
		return cv2.waitKey(t)

	def close(self):
		cv2.destroyAllWindows()
