import time
import threading
import logging
import os
import pigpio

from .ImageCapture import ImageCapture
from .CameraControl import start_pig, trigger_wave_script, TriggerConfig
from .CameraControl import PiGPIOScript, PiGPIOWave, CameraControlDefaults
from .frame_rate_monitor import FrameRateMonitor

class SystemController:
	def __init__(self):
		# Initialize the configuration first
		self.config = TriggerConfig()
		self.config.TRIG_WIDTH = 10
		self.config.LED_WIDTH = 20
		self.config.WAVE_DURATION = 33400
		self.config.LED_TIME = 1000
		self.config.LED_MASK = 1 << self.config.RED_OUT  # | 1<<GRN_OUT | 1<<BLU_OUT

		self.dt = 8333 // 333
		self.t_min = 1000
		self.t_max = 8333 + self.t_min
		self.fps_logger = FrameRateMonitor("SystemController", 5)

		# Now initialize the rest of the components that depend on the config
		self.pig = start_pig()
		control_defaults = CameraControlDefaults()
		self.vidcap = ImageCapture(capture_raw=False, controls=control_defaults)
		self.vidcap.open()
		self.initialize_trigger()

	def initialize_trigger(self):
		self.script = trigger_wave_script(self.pig, self.config)
		self.wave = PiGPIOWave(self.pig, self.config)

		# Wait for the script to finish initializing before starting it
		while self.script.initing():
			pass
		self.script.start(self.wave.id)

	def __del__(self):
		self.shutdown()

	def shutdown(self):
		try:
			self.display.close()
		except Exception as e:
			# logging.info(f"CameraController shutting down display: {e}")
			pass
		try:
			self.vidcap.close()
		except Exception as e:
			# logging.info(f"CameraController shutting down vidcap: {e}")
			pass
		try:
			self.script.stop()
			self.script.delete()
		except Exception as e:
			# logging.info(f"CameraController shutting down script: {e}")
			pass
		try:
			self.wave.delete()
		except Exception as e:
			# logging.info(f"CameraController shutting down wave: {e}")
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
		self.vidcap.control_set("exposure_auto_priority", 1)

	def set_cam_freerunning(self):
		self.vidcap.control_set("exposure_auto_priority", 0)

	def update_t_cur(self):
		self.config.LED_TIME += self.dt
		if self.config.LED_TIME > self.t_max:
			self.config.LED_TIME = self.t_min

	def main(self):
		self.set_cam_triggered()
		self.fps_logger.reset()
		while True:
			self.process_frame()
			self.update_t_cur()
			self.fps_logger.update()   
