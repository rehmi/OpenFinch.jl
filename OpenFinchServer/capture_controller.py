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
from .abstract_camera import AbstractCameraController
from .abstract_camera import AbstractCameraController

class CaptureController:
    # def __init__(self, device_id=0, capture_raw=False, controls={}):
    def __init__(self, camera_controller: AbstractCameraController):
        self.camera_controller = camera_controller
        self.capture_fps = FrameRateMonitor("CaptureController:capture", 1)

        # if False:
        #     self.camera_controller = V4L2CameraController(device_id, controls)
        #     self.reader_fps = self.camera_controller.reader_fps

        #     pixel_format = 'YUYV' if capture_raw else 'MJPG'
        #     self.camera_controller.set_format(width=1600, height=1200, pixel_format=pixel_format)

        #     for control_name, value in controls.items():
        #         self.set_control(control_name, value)

        # else:
        #     self.camera_controller = Picamera2Controller(device_id, controls)

    def get_capture_fps(self):
        return self.capture_fps.get_fps()

    def get_reader_fps(self):
        return self.camera_controller.reader_fps.get_fps()

    def capture_frame(self, blocking=True):
        frame = self.camera_controller.capture_frame(blocking=blocking)
        if frame is not None:
            self.capture_fps.update()
        return frame

    def capture_raw(self, blocking=True):
        frame = self.capture_frame(blocking=blocking)
        return frame.to_bytes()

    def capture_rgb(self, blocking=True):
        frame = self.capture_frame(blocking=blocking)
        return frame.to_rgb()

    def capture_grayscale(self, blocking=True):
        frame = self.capture_frame(blocking=blocking)
        return frame.to_grayscale()

    def open(self):
        self.camera_controller.open()

    def close(self):
        self.camera_controller.close()

    def get_controls(self):
        return self.camera_controller.get_controls

    def set_control(self, control_name, value):
        return self.camera_controller.set_control(control_name, value)

    def get_control(self, control_name):
        return self.camera_controller.get_control(control_name)
    