import time
import threading
import logging
import os
import pigpio

from .capture_controller import CaptureController
from .sequencer import start_pig, trigger_wave_script, TriggerConfig
from .sequencer import PiGPIOScript, PiGPIOWave
from .frame_rate_monitor import FrameRateMonitor
from .abstract_camera import AbstractCameraController

class SystemController:
    def __init__(self, camera_controller: AbstractCameraController):
        self.camera_controller = camera_controller
        # Initialize the configuration first
        self.config = TriggerConfig()
        # self.config.TRIG_WIDTH = 10
        # self.config.LED_WIDTH = 4
        # self.config.WAVE_DURATION = 8000
        # self.config.LED_TIME = 400
        # self.config.LED_MASK = 1 << self.config.RED_OUT  # | 1<<GRN_OUT | 1<<BLU_OUT

        self.t_min = 0
        self.t_max = 2730
        self.dt = (self.t_max - self.t_min) // 256
        self.fps_logger = FrameRateMonitor("SystemController", 1)

        # Now initialize the rest of the components that depend on the config
        self.pig = start_pig()
        self.vidcap = CaptureController(camera_controller=self.camera_controller)
        self.vidcap.open()
        self.initialize_gpio()
        self.initialize_trigger()

    def set_capture_mode(self, mode):
        self.camera_controller.set_capture_mode(mode)

    def initialize_gpio(self):
        cf = self.config

        for pin in [cf.TRIG_OUT, cf.RED_OUT, cf.GRN_OUT, cf.BLU_OUT]:
            self.pig.set_mode(pin, pigpio.OUTPUT)

        for pin in [cf.TRIG_IN, cf.RED_IN, cf.GRN_IN, cf.BLU_IN, cf.STROBE_IN]:
            self.pig.set_mode(pin, pigpio.INPUT)

    def initialize_trigger(self):
        self.script = trigger_wave_script(self.pig, self.config)
        self.wave = PiGPIOWave(self.pig, self.config)

        # Wait for the script to finish initializing before starting it
        while self.script.initing():
            pass
        self.script.start(self.wave.id)

    def __del__(self):
        self.shutdown()

    def get_capture_fps(self):
        return self.vidcap.get_capture_fps()

    def get_controller_fps(self):
        return self.fps_logger.get_fps()
        
    def get_reader_fps(self):
        return self.vidcap.get_reader_fps()

    def shutdown(self):
        try:
            self.display.close()
        except Exception as e:
            # logging.debug(f"CameraController shutting down display: {e}")
            pass
        try:
            self.vidcap.close()
        except Exception as e:
            # logging.debug(f"CameraController shutting down vidcap: {e}")
            pass
        try:
            self.script.stop()
            self.script.delete()
        except Exception as e:
            # logging.debug(f"CameraController shutting down script: {e}")
            pass
        try:
            self.wave.delete()
        except Exception as e:
            # logging.debug(f"CameraController shutting down wave: {e}")
            pass

    def capture_frame(self, timeout=0):
        self.fps_logger.update()
        if timeout <= 0:
            return self.vidcap.capture_frame()
        else:
            result = [None]

            def target():
                result[0] = self.vidcap.capture_frame()

            thread = threading.Thread(target=target)
            thread.start()
            thread.join(timeout)
            if thread.is_alive():
                return None
            else:
                return result[0]

    def stop_wave(self):
        self.script.set_params(0xffffffff) # deactivate the current wave
        self.wave.delete()

    def set_delay(self, t_del):
        self.config.LED_TIME = t_del
        self.wave = PiGPIOWave(self.pig, self.config)
        self.script.set_params(self.wave.id)

    def update_wave(self):
        self.stop_wave()
        self.set_delay(self.config.LED_TIME)

    def set_cam_triggered(self):
        # XXX move this into the camera controller
        # self.vidcap.set_control("exposure_auto_priority", 1)
        pass

    def set_cam_freerunning(self):
        # XXX move this into the camera controller
        # self.vidcap.set_control("exposure_auto_priority", 0)
        pass

    def sweep(self):
        self.config.LED_TIME += self.dt
        if self.config.LED_TIME > self.t_max:
            self.config.LED_TIME = self.t_min
