import time
from ImageCapture import ImageCapture
from Display import Display
from CameraControl import start_pig, trigger_wave_script, TriggerConfig
from CameraControl import PiGPIOScript, PiGPIOWave, CameraControlDefaults
import threading
from queue import Queue
import logging

class FPSLogger:
	def __init__(self):
		self.frame_count = 0
		self.start_time = time.time()

	def reset(self):
		self.frame_count = 0
		self.start_time = time.time()

	def increment(self):
		self.frame_count += 1

	def update(self):
		self.increment()
		if time.time() - self.start_time >= 3:
			fps = self.frame_count / (time.time() - self.start_time)
			logging.info(f"Average FPS: {fps:.2f}")
			self.reset()

class MainClass:
	def __init__(self):
		# Initialize the configuration first
		self.config = TriggerConfig()
		self.config.TRIG_WIDTH = 10
		self.config.LED_WIDTH = 20
		self.config.WAVE_DURATION = 40000
		self.config.LED_TIME = 1000
		self.config.LED_MASK = 1 << self.config.RED_OUT  # | 1<<GRN_OUT | 1<<BLU_OUT

		self.num_iterations = 100
		self.t_min = 1000
		self.t_max = 8333 + self.t_min
		self.fps_logger = FPSLogger()

		# Now initialize the rest of the components that depend on the config
		self.pig = start_pig()
		control_defaults = CameraControlDefaults()
		self.vidcap = ImageCapture(capture_raw=False, controls=control_defaults)
		self.vidcap.open()

		# Initialize display and script/wave-related components
		self.display = Display()
		self.script = trigger_wave_script(self.pig, self.config)
		self.wave = PiGPIOWave(self.pig, self.config)

		# Wait for the script to finish initializing before starting it
		while self.script.initing():
			pass
		self.script.start(self.wave.id)

	def shutdown(self):
		try:
			self.display.close()
			self.vidcap.close()
			self.script.stop()
			self.script.delete()
			self.wave.delete()
		except Exception as e:
			logging.info(f"While shutting down: {e}")

	def capture_frame(self):
		return self.vidcap.capture_frame()

	def capture_frame_with_timeout(self, timeout=0.25):
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
  
	def reset_wave(self, i):
		c = int((self.t_max - self.t_min) // self.num_iterations)
		self.config.LED_TIME = self.t_min + c*i
		self.script.set_params(0xffffffff) # deactivate the current wave
		self.wave.delete()
		self.wave = PiGPIOWave(self.pig, self.config)
		self.script.set_params(self.wave.id)

	def update_display(self, img):
		self.display.set_image(img)
		self.display.display_image()
		self.display.update()

	def process_frames(self):
		self.vidcap.control_set("exposure_auto_priority", 1)
		self.fps_logger.reset()
		for i in range(self.num_iterations + 1):
			try:
				img = self.capture_frame_with_timeout()
				if img is not None:
					self.fps_logger.update()
					self.reset_wave(i)
					self.update_display(img)
				else:
					logging.info("capture_frame timed out!")
			except Exception as e:
				logging.info(f"EXCEPTION: {e}")
				continue
				
	def main(self):
		while True:
			self.process_frames()

if __name__ == "__main__":
	try:
		fmt = "%(threadName)-10s %(asctime)-15s %(levelname)-5s %(name)s: %(message)s"
		logging.basicConfig(level="INFO", format=fmt)
		main_obj = MainClass()
		main_obj.main()
	except KeyboardInterrupt:
		logging.info("Ctrl-C pressed. Bailing out")
	finally:
		main_obj.shutdown()
