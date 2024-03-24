import cv2
import numpy as np
from screeninfo import get_monitors
import os
import logging
import requests
import time
import mmap
from PIL import Image

# Common interface for display operations
class DisplayBackend:
    def display_image(self, img):
        raise NotImplementedError

# Frontend API
class Display:
    def __init__(self, window_name='SLM image', monitor_index=0):
        self.backend = self._select_backend(window_name)

    def _select_backend(self, window_name):
        if 'DISPLAY' in os.environ:
            return WindowSystemDisplay(window_name)
        elif os.path.exists("/dev/fb0"):
            return FramebufferDisplay()
        else:
            logging.error("No suitable display backend found.")
            return None

    def display_image(self, img):
        if self.backend:
            self.backend.display_image(img)
        else:
            logging.error("No backend available for displaying images.")

class FramebufferDisplay(DisplayBackend):
    def get_framebuffer_dimensions(self):
        """
        Retrieves the dimensions of the framebuffer.

        Returns:
        - tuple: The width and height of the framebuffer.
        """
        # This command should return the dimensions in a format like "800x600"
        # Adjust the command as necessary for your specific environment
        output = os.popen('fbset -s | grep geometry').read()
        dimensions = output.split()
        width = int(dimensions[1])
        height = int(dimensions[2])
        return width, height

    def display_image_on_framebuffer(self, image_path):
        """
        Displays an image directly on the framebuffer using a memory-mapped file.

        Parameters:
        - image_path (str): The path to the image file.
        """
        # Load the image
        img = Image.open(image_path)

        # Get the framebuffer dimensions
        width, height = self.get_framebuffer_dimensions()

        # Resize the image to fit the framebuffer dimensions
        img = img.resize((width, height))

        # Convert the image to the framebuffer format (e.g., RGB565)
        img_data = self.convert_image_to_framebuffer_format(img)

        # Write the image data to the framebuffer
        self.write_to_framebuffer(img_data, width, height)

    def convert_image_to_framebuffer_format(self, img):
        """
        Converts a PIL Image to the format required by the framebuffer (e.g., RGB565).

        Parameters:
        - img (PIL.Image): The image to convert.

        Returns:
        - numpy.ndarray: The image data in framebuffer format.
        """
        img = img.convert('RGB')
        img_data = np.array(img, dtype=np.uint8)
        r = (img_data[:,:,0] >> 3) & 0x1F
        g = (img_data[:,:,1] >> 2) & 0x3F
        b = (img_data[:,:,2] >> 3) & 0x1F
        rgb565 = (r << 11) | (g << 5) | b
        return rgb565.astype(np.uint16)

    def write_to_framebuffer(self, img_data, width, height):
        """
        Writes image data directly to the framebuffer device using memory mapping.

        Parameters:
        - img_data (numpy.ndarray): The image data in the correct format for the framebuffer.
        - width (int): The width of the framebuffer.
        - height (int): The height of the framebuffer.
        """
        framebuffer_device = "/dev/fb0"  # Path to the framebuffer device

        # Calculate the size of the framebuffer in bytes
        fb_size = width * height * 2  # 2 bytes per pixel for RGB565

        with open(framebuffer_device, "r+b") as fb:
            mm = mmap.mmap(fb.fileno(), fb_size)
            mm.write(img_data.tobytes())
            mm.close()


class WindowSystemDisplay(DisplayBackend):
    def __init__(self, window_name='SLM image', monitor_index=0):
        self.monitor_index = monitor_index
        self.window_mode = "normal"
        self.window_name = window_name
        self.window_created = False
        self.use_framebuffer = False

        # XXX begin hack to ensure the display appears on monitor[0]
        self.create_window()
        self.move_to_monitor(0)
        self.update()
        self.move_to_monitor(0)
        self.update()
        # self.hide_window()
        self.update()
        # XXX end hack


    def display_image(self, img):
        self.image = img
        cv2.imshow(self.window_name, self.image)
        self.update()
    
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
        logging.debug(f"moving window to ({x}, {y}) + ({dx}, {dy}) = ({x+dx}, {y+dy})")
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
