import cv2
import numpy as np
from screeninfo import get_monitors
import os
import logging
import requests
import time
import mmap
from PIL import Image
from io import BytesIO

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
    def test_display(self):
        self.backend.test_display()

class FramebufferDisplay(DisplayBackend):
    def __init__(self):
        self.width, self.height = self.get_framebuffer_dimensions()
        # this is the frambuffer for video output - note that this is a 16 bit RGB
        # other setups will likely have a different format and dimensions which you can check with
        # fbset -fb /dev/fb0 
        self.tty = "/dev/tty1"
        self.disable_cursor()
        self.fb = self.get_mapped_framebuffer()
        self.saved_fb = self.fb.copy()

    def __del__(self):
        self.fb[:] = self.saved_fb
        self.enable_cursor()
    
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

    def get_mapped_framebuffer(self):
        # this is the frambuffer for analog video output - note that this is a 16 bit RGB
        # other setups will likely have a different format and dimensions which you can check with
        # fbset -fb /dev/fb0 
        return np.memmap('/dev/fb0', dtype='uint16',mode='w+', shape=(self.height, self.width))

    # Function to convert PIL image to 5-6-5 RGB format using NumPy
    def convert_image_to_rgb565(self, image):
        # first check for 1-bit images
        if image.mode == '1':
            img_np = np.array(image)
            rgb565 = img_np.astype(np.uint16) * 0xffff
        else:
            # Convert the image to RGB if it's not already in RGB mode
            if image.mode != 'RGB':
                image = image.convert('RGB')

            # Convert the image to a NumPy array
            img_np = np.array(image)

            # Resize image to match your framebuffer's resolution, if necessary
            # img_np = cv2.resize(img_np, (framebuffer_width, framebuffer_height))

            # Convert pixels to 5-6-5 format
            r = (img_np[:,:,0] >> 3).astype(np.uint16)
            g = (img_np[:,:,1] >> 2).astype(np.uint16)
            b = (img_np[:,:,2] >> 3).astype(np.uint16)
            rgb565 = (r << 11) | (g << 5) | b

        # return the numpy uint16 array
        return rgb565

    def display_image(self, img):
        img_width, img_height = img.size
        # Determine whether to crop or pad
        if img_width > self.width or img_height > self.height:
            # Crop the image
            left = (img_width - self.width) // 2
            top = (img_height - self.height) // 2
            right = (img_width + self.width) // 2
            bottom = (img_height + self.height) // 2
            img_cropped = img.crop((left, top, right, bottom))
            img_final = img_cropped
        elif img_width < self.width or img_height < self.height:
            # Pad the image
            img_final = Image.new("RGB", (self.width, self.height), "black")
            left = (self.width - img_width) // 2
            top = (self.height - img_height) // 2
            img_final.paste(img, (left, top))
        else:
            img_final = img

        # Convert the final image to RGB565 format
        img_rgb565 = self.convert_image_to_rgb565(img_final)

        # Convert the byte array to a NumPy array of type uint16
        # img_rgb565_np = np.frombuffer(img_rgb565, dtype=np.uint16)
        # Reshape the array to match the framebuffer's dimensions
        # and assign the reshaped array to the framebuffer
        self.fb[:] =  img_rgb565.reshape(self.height, self.width)
        # response = requests.get(image_url)
        # response.raise_for_status()
        # image_bytes = response.content
        # img = Image.open(BytesIO(image_bytes))
        # self.display_image(img)

    def disable_cursor(self):
        # this turns off the cursor blink:
        #os.system (f"TERM=linux setterm -foreground black -clear all >{tty}")
        os.system (f"TERM=linux setterm -cursor off >{self.tty}")

    def enable_cursor(self):
        # turn on the cursor again:    
        #os.system(f"TERM=linux setterm -foreground white -clear all >{tty}")
        os.system (f"TERM=linux setterm -cursor on >{self.tty}")

    def display_image_url(self, image_url):
        try:
            # Fetch the image
            response = requests.get(image_url)
            img = Image.open(BytesIO(response.content))
            self.display_image(img)
        except requests.exceptions.HTTPError as err:
            logging.exception(f"Error retrieving image")

    def test_display(self):
        test_image_url = "https://www.belle-nuit.com/site/files/testchart720.tif"
        # self.display_image_url(test_image_url)

        # URL of the image
        test_image_url = "https://m.media-amazon.com/images/I/71D-PfmrvjL._AC_SL1200_.jpg"
        self.display_image_url(test_image_url)


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

import unittest

class TestDisplayMethods(unittest.TestCase):
    def setUp(self):
        self.display = Display('foo')
        print(f"self.display = {self.display}")

    def test_display(self):
        self.display.test_display()

if __name__ == '__main__':
    unittest.main()
