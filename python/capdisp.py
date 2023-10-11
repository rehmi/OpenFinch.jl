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

class Display:
    def __init__(self, window_name='image'):
        if 'DISPLAY' not in os.environ:
            os.environ['DISPLAY'] = ':0'

        self.monitor = get_monitors()[0]
        self.window_name = window_name
        cv2.namedWindow(self.window_name, cv2.WND_PROP_FULLSCREEN)
        cv2.moveWindow(self.window_name, self.monitor.x, self.monitor.y)
        cv2.setWindowProperty(self.window_name, cv2.WND_PROP_FULLSCREEN, cv2.WINDOW_FULLSCREEN)

    def show_frame(self, img):
        img = cv2.resize(img, (self.monitor.width, self.monitor.height))
        cv2.imshow(self.window_name, img)

    def close(self):
        cv2.destroyAllWindows()

if __name__ == "__main__":
    vidcap = ImageCapture(capture_raw=False)
    vidcap.open()
    display = Display()

    frame_count = 0
    start_time = time.time()

    while True:
        try:
            img = vidcap.capture_frame()
            frame_count += 1

            display.show_frame(img)

            if time.time() - start_time >= 5:
                fps = frame_count / (time.time() - start_time)
                print(f"Average FPS: {fps:.2f}")
                frame_count = 0
                start_time = time.time()

            if cv2.waitKey(1) & 0xFF == ord('q'):
                break
        except AttributeError:
            continue

    display.close()
    vidcap.close()