import time
from ImageCapture import ImageCapture
from Display import Display
from CameraControl import start_pig, trigger_wave_script, TriggerConfig
from CameraControl import PiGPIOScript, PiGPIOWave, CameraControlDefaults
import threading
from queue import Queue
import logging

class MainClass:
	def __init__(self):
		self.wave = None
		self.script = None
		self.display = None
		self.vidcap = None
		self.config = None
		self.pig = None

	def initialize_config(self, config):
		config.TRIG_WIDTH = 10
		config.LED_WIDTH = 50
		config.WAVE_DURATION = 40000
		config.LED_TIME = 1000
		config.LED_MASK = 1<<config.RED_OUT # | 1<<GRN_OUT | 1<<BLU_OUT
		return config

	def initialize_camera(self):
		self.config = TriggerConfig()
		self.initialize_config(self.config)
		self.pig = start_pig()
		control_defaults = CameraControlDefaults()
		self.vidcap = ImageCapture(capture_raw=False, controls=control_defaults)
		self.vidcap.open()

	def initialize_display(self):
		self.display = Display()

	def initialize_script_and_wave(self):
		self.script = trigger_wave_script(self.pig, self.config)
		self.wave = PiGPIOWave(self.pig, self.config)
		while self.script.initing():
			pass
		self.script.start(self.wave.id)

	def calculate_led_time(self, i, n):
		c = int((self.t_max - self.t_min) // n)
		return self.t_min + c*i

	def capture_frame(self, i):
		self.config.LED_TIME = self.calculate_led_time(i, 100)
		img = self.vidcap.capture_frame()
		self.script.set_params(0xffffffff) # deactivate the current wave
		self.wave.delete()
		self.wave = PiGPIOWave(self.pig, self.config)
		self.script.set_params(self.wave.id)
		return img

	def update_display(self, img):
		self.display.set_image(img)
		self.display.display_image()
		self.display.update()

	def log_fps(self, frame_count, start_time):
		if time.time() - start_time >= 3:
			fps = frame_count / (time.time() - start_time)
			logging.info(f"Average FPS: {fps:.2f}")
			frame_count = 0
			start_time = time.time()
			return frame_count, start_time
		return frame_count, start_time

	def process_frames(self):
		n=100
		self.t_min = 1000
		self.t_max = 8333 + self.t_min
		self.vidcap.control_set("exposure_auto_priority", 1)

		frame_count = 0
		start_time = time.time()

		for i in range(n + 1):
			try:
				img = self.capture_frame(i)
				self.update_display(img)
				frame_count += 1
				frame_count, start_time = self.log_fps(frame_count, start_time)
			except Exception as e:
				logging.info(f"EXCEPTION: {e}")
				continue
				
	def main(self):
		self.initialize_camera()
		self.initialize_display()
		self.initialize_script_and_wave()
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
		main_obj.wave.delete()
		main_obj.script.delete()
		main_obj.display.close()
		main_obj.vidcap.close()