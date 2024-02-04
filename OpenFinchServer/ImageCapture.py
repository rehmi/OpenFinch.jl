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
from .camera_control_interface import CameraControllerInterface

class ImageCapture:
    # def __init__(self, device_id=0, capture_raw=False, controls={}):
    def __init__(self, camera_controller: CameraControllerInterface):
        self.camera_controller = camera_controller
        self.capture_fps = FrameRateMonitor("ImageCapture:capture", 1)

        # if False:
        #     self.camera_controller = V4L2CameraController(device_id, controls)
        #     self.reader_fps = self.camera_controller.reader_fps

        #     pixel_format = 'YUYV' if capture_raw else 'MJPG'
        #     self.camera_controller.set_format(width=1600, height=1200, pixel_format=pixel_format)

        #     for control_name, value in controls.items():
        #         self.control_set(control_name, value)

        # else:
        #     self.camera_controller = Picamera2Controller(device_id, controls)

    def get_capture_fps(self):
        return self.capture_fps.get_fps()

    def get_reader_fps(self):
        return self.camera_controller.reader_fps.get_fps()

    def capture_frame(self, blocking=True):
        cap = self.camera_controller.capture_frame(blocking=blocking)
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
        self.camera_controller.open()
        # self.video.open()
        # self._start_reader()

    def close(self):
        # self._stop_reader()
        # self.video.close()
        self.camera_controller.close()

    # def __del__(self):
        # self.camera_controller.close()
    
    def controls(self):
        return self.camera_controller.controls

    def control(self, control_name):
        return self.camera_controller.controls[control_name]

    def control_set(self, control_name, value):
        return self.camera_controller.set_control(control_name, value)

    def control_get(self, control_name):
        return self.camera_controller.get_control(control_name)
