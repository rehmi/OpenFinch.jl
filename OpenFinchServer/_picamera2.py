import cv2
import numpy as np
from screeninfo import get_monitors
import v4l2py
import picamera2
from picamera2 import Picamera2, Preview, Metadata, libcamera
from libcamera import controls, ControlType
import time
import os
import io
import logging
import subprocess
import threading
import queue
from .frame_rate_monitor import FrameRateMonitor
from .abstract_camera import AbstractCameraController
from .controls import IntegerControl, BooleanControl, FloatControl, MenuControl

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

        self.common_to_imx296 = {
            'brightness': 'Brightness',
            'contrast': 'Contrast',
            'gamma': None,  # No corresponding control in Picamera2
            'gain': 'AnalogueGain',
            'power_line_frequency': None,  # No corresponding control in Picamera2
            'white_balance_temperature': None,  # No corresponding control in Picamera2
            'sharpness': 'Sharpness',
            'backlight_compensation': None,  # No corresponding control in Picamera2
            'exposure_time': 'ExposureTime',
            'exposure_auto': None,  # No corresponding control in Picamera2
            'exposure_absolute': None,  # No corresponding control in Picamera2
            'exposure_auto_priority': None,  # No corresponding control in Picamera2
            'analogue_gain': 'AnalogueGain',
            'colour_gains': 'ColourGains',
            'awb_enable': 'AwbEnable',
            'ae_enable': 'AeEnable',
            'ae_exposure_mode': 'AeExposureMode',
            'ae_constraint_mode': 'AeConstraintMode',
            'noise_reduction_mode': 'NoiseReductionMode',
            'scaler_crop': 'ScalerCrop',
        }

        # Define the mapping from backend-specific names to common control names.
        # This is basically the inverse of the mapping above.
        self.imx296_to_common = {v: k for k, v in self.common_to_imx296.items() if v is not None}

        # The functional translation layer is mapped by function name to their implementation
        self.common_control_translations = {
            'exposure_absolute': (self.get_exposure_absolute, self.set_exposure_absolute),
            # Other translations for different controls can be added here
        }


    # Let's define the functions to handle the mapping
    def common_to_backend(self, common_name):
        return self.common_to_imx296.get(common_name, None)

    def backend_to_common(self, backend_name):
        return self.imx296_to_common.get(backend_name, None)
    
    # Let's assume that the abstract 'exposure_absolute' units are in milliseconds,
    # but the backend 'ExposureTime' units are in microseconds.
    def set_exposure_absolute(self, abstract_value):
        # Convert from milliseconds to microseconds
        backend_value = abstract_value * 1
        self.picam2.set_controls({"ExposureTime": backend_value})

    def get_exposure_absolute(self):
        # Retrieve the exposure time from the backend (in microseconds)
        backend_value = self.picam2.get_control("ExposureTime")
        # Convert from microseconds to milliseconds
        return backend_value / 1

    def set_control(self, control_name, value):
        logging.info(f"Picamera2Controller.set_control({control_name}, {value})")
        try:
            backend_control_name = self.common_to_imx296.get(control_name, control_name)
            logging.info(f"set_control('{control_name}' -> '{backend_control_name}', {value})")
            self.picam2.set_controls({backend_control_name: value})
        except Exception as e:
            logging.exception(f"Control '{control_name}'")
        finally:
            return False

    def get_control(self, control_name):
        try:
            backend_control_name = self.common_to_imx296.get(control_name, control_name)
            logging.info(f"get_control('{control_name}' -> '{backend_control_name}')")
            return getattr(self.picam2.controls, backend_control_name)
        except Exception as e:
            logging.exception(f"Control '{control_name}'")
        finally:
            return False

    # # Modified control setter that uses translation functions where applicable
    # def set_control(self, control_name, value):
    #     if control_name in common_control_translations:
    #         # Call the translation function directly to set the value
    #         setter_function = common_control_translations.get(f'set_{control_name}')
    #         setter_function(self, value)
    #     else:
    #         # Translate abstract control name to backend and set the value directly
    #         backend_name = common_to_backend(control_name)
    #         if backend_name:
    #             self.picam2.set_controls({backend_name: value})
    #         else:
    #             raise ValueError(f"Control '{control_name}' is not supported by the backend.")

    # # Modified control getter that uses translation functions where applicable
    # def get_control(self, control_name):
    #     if control_name in common_control_translations:
    #         # Call the translation function directly to get the value
    #         getter_function = common_control_translations.get(f'get_{control_name}')
    #         return getter_function(self)
    #     else:
    #         # Translate abstract control name to backend and get the value directly
    #         backend_name = common_to_backend(control_name)
    #         if backend_name:
    #             return self.picam2.get_control(backend_name)
    #         else:
    #             raise ValueError(f"Control '{control_name}' is not supported by the backend.")


    def get_controls(self):
        return self.picam2.camera_ctrl_info

    def get_control_descriptors(self):
        # Convert the picamera2 controls to our common format
        return self.convert_picamera_controls(self.picam2.camera_ctrl_info)
    
    def convert_picamera_controls(self, camera_ctrl_info):
        controls = {}
        for control_name, control_info in camera_ctrl_info.items():
            control_id, control_range = control_info
            control_type = control_id.type.name
            if control_type == 'Integer32' or control_type == 'Integer64':
                controls[control_name] = IntegerControl(control_name, control_id.id, control_type, (control_range.min, control_range.max), None, None, None)
            elif control_type == 'Float':
                controls[control_name] = FloatControl(control_name, control_id.id, control_type, (control_range.min, control_range.max), None, None)
            elif control_type == 'Bool':
                controls[control_name] = BooleanControl(control_name, control_id.id, control_type, None, None)
        return controls

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

    def set_capture_mode(self, mode):
        if mode == 'still':
            self.picam2.switch_mode(self.still_config)
        elif mode == 'preview':
            self.picam2.switch_mode(self.preview_config)
        elif mode == 'video':
            self.picam2.switch_mode(self.video_config)

