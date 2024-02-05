import cv2
import numpy as np
from screeninfo import get_monitors
import os
import logging
import requests
import time

class Display:
    def __init__(self, window_name='image', monitor_index=0):
        # if 'DISPLAY' not in os.environ:
        # 	os.environ['DISPLAY'] = ':0'

        self.monitor_index = monitor_index
        self.window_mode = "normal"
        self.window_name = window_name
        self.window_created = False

        # self.create_window()

    def set_image_url(self, url):
        response = requests.get(url)
        img_bytes = np.asarray(bytearray(response.content), dtype="uint8")
        image = cv2.imdecode(img_bytes, cv2.IMREAD_COLOR)
        self.display_image(image)
        return image

    def display_image(self, img):
        self.image = img
        cv2.imshow(self.window_name, self.image)
        self.update()

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
        monitor = get_monitors()[self.monitor_index]
        dx,dy = monitor.x,monitor.y
        logging.info(f"moving window to ({x}, {y}) + ({dx}, {dy}) = ({x+dx}, {y+dy})")
        cv2.moveWindow(self.window_name, x+dx, y+dy)

    def update(self):
        cv2.pollKey()
        time.sleep(0.01)
        cv2.pollKey()

    def waitKey(self, t=0):
        return cv2.waitKey(t)

    def close(self):
        cv2.destroyAllWindows()

    def create_window(self):
        if not self.window_created:
            if 'DISPLAY' not in os.environ:
                logging.error("DISPLAY environment variable is not set. Cannot create a window.")
                return
            cv2.namedWindow(self.window_name, cv2.WINDOW_NORMAL)
            self.window_created = True

    def destroy_window(self):
        if self.window_created:
            cv2.destroyWindow(self.window_name)
        self.window_created = False

    def move_to_monitor(self, idx=0):
        monitors = get_monitors()
        if len(monitors) > idx:
            oldmon = monitors[self.monitor_index]
            monitor = monitors[idx]
            self.monitor_index = idx
            self.move(0, 0)
        else:
            logging.info(f"Not enough monitors detected. Make sure you have at least {self.monitor_index + 1} monitors connected.")

    def switch_mode(self, mode):
        if mode == 'fullscreen':
            self.switch_to_fullscreen()
        elif mode == 'normal':
            self.switch_to_normal()
        else:
            raise ValueError("Invalid mode. Choose either 'fullscreen' or 'normal'.")

    
    def switch_to_fullscreen(self):
        cv2.setWindowProperty(self.window_name, cv2.WND_PROP_FULLSCREEN, cv2.WINDOW_FULLSCREEN)
        self.update()

    def switch_to_normal(self):
        self.destroy_window()
        self.create_window()
        cv2.setWindowProperty(self.window_name, cv2.WND_PROP_FULLSCREEN, cv2.WINDOW_NORMAL)
        self.update()

import unittest

class TestDisplayMethods(unittest.TestCase):
    def setUp(self):
        self.display = Display('foo')

    def test_display(self):
        self.display.switch_mode("normal")
        self.display.move_to_monitor(0)
        self.display.resize(512, 512)
        image = np.zeros((512, 512, 3), dtype=np.uint8)
        cv2.putText(image, "512 x 512 window on monitor 0; press any key to continue.", (10, 500), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 2)
        self.display.display_image(image)
        self.display.update()

        time.sleep(1)
        
        # self.display.switch_mode("normal")
        self.display.move_to_monitor(1)
        image = np.zeros((512, 512, 3), dtype=np.uint8)
        cv2.putText(image, "512 x 512 window on monitor 1; press any key to continue.", (10, 500), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 2)
        self.display.display_image(image)
        self.display.update()

        time.sleep(1)

        self.display.switch_mode("fullscreen")
        self.display.move_to_monitor(1)
        self.display.update()
        image = np.zeros((720, 1280, 3), dtype=np.uint8)
        cv2.putText(image, "Fullscreen window on monitor 1; press any key to continue.", (10, 700), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 2)
        self.display.display_image(image)
        self.display.update()

        time.sleep(1)

if __name__ == '__main__':
    unittest.main()
