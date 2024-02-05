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
from .abstract_camera import AbstractCameraController

from .IMX296 import IMX296Defaults

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

class Picamera2Controller(AbstractCameraController):
    def __init__(self, device_id=0, controls={}):
        self.picam2 = Picamera2()
        self.controls = controls
        self.reader_fps = FrameRateMonitor("Picamera2Controller:reader", 1)
        self.still_config = self.picam2.create_still_configuration()
        self.preview_config = self.picam2.create_preview_configuration()
        self.video_config = self.picam2.create_video_configuration()
        self.picam2.start()
        self.set_capture_mode("preview")
        # picamera2 likes to log a lot of things
        logger = logging.getLogger('picamera2.request')
        logger.setLevel(logging.WARNING)

        self.frame_queue = queue.Queue(maxsize=1)
        self.running = False
        self.reader_fps = FrameRateMonitor("Picamera2Controller:reader", 1)

    def _start_reader(self):
        self.running = True
        self.thread = threading.Thread(target=self._read_frames)
        self.thread.start()

    def _read_frames(self):
        while self.running:
            try:
                data = io.BytesIO()
                self.picam2.capture_file(data, format='jpeg')
                self.reader_fps.update()
                if not self.frame_queue.full():
                    self.frame_queue.put(Picamera2CapturedImage(data))
            except Exception as e:
                logging.error(f"Error capturing frame: {e}")

    def _stop_reader(self):
        try:
            self.running = False
            self.thread.join()
        except Exception as e:
            logging.exception("Picamera2Controller._stop_reader()")

    def capture_frame(self, blocking=True):
        if not blocking and self.frame_queue.empty():
            return None
        else:
            frame = self.frame_queue.get()
            return frame

    def open(self):
        self.picam2.start()
        self._start_reader()

    def close(self):
        self._stop_reader()
        self.picam2.stop()

    # def capture_frame(self, blocking=True):
    #     data = io.BytesIO()
    #     self.picam2.capture_file(data, format='jpeg')
    #     self.reader_fps.update()
    #     return Picamera2CapturedImage(data)

    def set_control(self, control_name, value):
        try:
            self.picam2.set_controls({control_name: value})
        except Exception as e:
            # raise AttributeError(f"Control '{control_name}' does not exist.")
            logging.exception(f"Control '{control_name}'")
        finally:
            return False

    def get_control(self, control_name):
        try:
            return self.picam2.controls[control_name]
        except Exception as e:
            # raise AttributeError(f"Control '{control_name}' does not exist.")
            logging.exception(f"Control '{control_name}'")
        finally:
            return False

    def get_controls(self):
        return self.picam2.camera_ctrl_info

    def set_capture_mode(self, mode):
        if mode == 'still':
            self.picam2.switch_mode(self.still_config)
        elif mode == 'preview':
            self.picam2.switch_mode(self.preview_config)
        elif mode == 'video':
            self.picam2.switch_mode(self.video_config)

