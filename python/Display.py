import cv2
import numpy as np
from screeninfo import get_monitors
import v4l2py
import time
import os
import subprocess

class Display:
	def __init__(self, window_name='image'):
		if 'DISPLAY' not in os.environ:
			os.environ['DISPLAY'] = ':0'
   
		mons = get_monitors()
		print(mons)
		self.monitor = mons[0]
		self.window_name = window_name
		cv2.namedWindow(self.window_name, cv2.WND_PROP_FULLSCREEN)
		cv2.waitKey(1)
		cv2.moveWindow(self.window_name, 0, 0)
		cv2.waitKey(1)
		cv2.moveWindow(self.window_name, self.monitor.x, self.monitor.y)
		cv2.waitKey(1)
		cv2.setWindowProperty(self.window_name, cv2.WND_PROP_FULLSCREEN, cv2.WINDOW_FULLSCREEN)
		cv2.waitKey(1)

	def show_frame(self, img):
		img = cv2.resize(img, (self.monitor.width, self.monitor.height))
		cv2.imshow(self.window_name, img)
  
	def waitKey(self, t):
		return cv2.waitKey(t)

	def close(self):
		cv2.destroyAllWindows()
