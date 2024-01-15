import time
from ImageCapture import ImageCapture
from Display import Display
from CameraControl import start_pig, trigger_wave_script, TriggerConfig
from CameraControl import PiGPIOScript, PiGPIOWave, CameraControlDefaults

import threading
from queue import Queue

def initialize_config(config):
	config.TRIG_WIDTH = 10
	config.LED_WIDTH = 50
	config.WAVE_DURATION = 40000
	config.LED_TIME = 1000
	config.LED_MASK = 1<<config.RED_OUT # | 1<<GRN_OUT | 1<<BLU_OUT
	return config

global wave, script, display, vidcap, config, pig

def main():
	global wave, script, display, vidcap, config, pig
	config = TriggerConfig()
	initialize_config(config)
	pig = start_pig()
	control_defaults = CameraControlDefaults()
	vidcap = ImageCapture(capture_raw=False, controls=control_defaults)
	vidcap.open()

	display = Display()
	
	n=100
	t_min = 1000
	t_max = 8333 + t_min # + 2778
	config.LED_TIME = t_min
	c = int((t_max - t_min) // n)

	vidcap.control_set("exposure_auto_priority", 1)

	script = trigger_wave_script(pig, config)
	wave = PiGPIOWave(pig, config)
	while script.initing():
		pass;
	script.start(wave.id)

	frame_count = 0
	start_time = time.time()

	while True:
		for i in range(n + 1):
			try:
				# don't disable the wave until after a capture
				# logging.info(script.params())
				config.LED_TIME = t_min + c*i
				img = vidcap.capture_frame()
				script.set_params(0xffffffff) # deactivate the current wave
				frame_count += 1
				# while script.pig.wave_tx_busy():	# wait for sequencing_paused
				# 	# print(".", end="")
				# 	# print(s.status(), " ", s.params())
				# 	time.sleep(0.001)
				# 	pass
				# now safe to delete the wave
				wave.delete()
				wave = PiGPIOWave(pig, config)
				script.set_params(wave.id)

				display.show_frame(img)
				display.waitKey(1)

				if time.time() - start_time >= 3:
					fps = frame_count / (time.time() - start_time)
					logging.info(f"Average FPS: {fps:.2f}")
					frame_count = 0
					start_time = time.time()


			except Exception as e:
				logging.info(f"EXCEPTION: {e}")
				continue
	

import logging
if __name__ == "__main__":
	try:
		fmt = "%(threadName)-10s %(asctime)-15s %(levelname)-5s %(name)s: %(message)s"
		logging.basicConfig(level="INFO", format=fmt)
		main()
	except KeyboardInterrupt:
		logging.info("Ctrl-C pressed. Bailing out")
	finally:
		wave.delete()
		script.delete()
		display.close()
		vidcap.close()
