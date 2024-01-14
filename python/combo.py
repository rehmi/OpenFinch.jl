import time
from ImageCapture import ImageCapture
from Display import Display
from CameraControl import start_pig, trigger_wave_script
from CameraControl import PiGPIOScript, PiGPIOWave

from dataclasses import dataclass

import threading
from queue import Queue

@dataclass(frozen=False)
class Config:
	RED_IN: int = 25
	GRN_IN: int = 24
	BLU_IN: int = 22

	RED_OUT: int = 17
	GRN_OUT: int = 27
	BLU_OUT: int = 23

	TRIG_OUT: int = 5
	STROBE_IN: int = 6

	TRIG_IN: int = RED_IN
	LED_IN: int = BLU_IN
	LED_OUT: int = RED_OUT
	TRIG_OUT: int = TRIG_OUT
	
	TRIG_TIME: int = 0
	TRIG_WIDTH: int = 50
	LED_TIME: int = 5555
	LED_WIDTH: int = 20
	WAVE_DURATION: int = 8333
	
def main():
	config = Config()

	pig = start_pig()

	vidcap = ImageCapture(capture_raw=False)
	vidcap.open()
	# time.sleep(1)

	vidcap.control_set("exposure_auto_priority", 0)

	# {
	# <Control brightness type=integer min=-64 max=64 step=1 default=0 value=32>, 
	# <Control contrast type=integer min=0 max=64 step=1 default=32 value=32>, 
	# <Control saturation type=integer min=0 max=128 step=1 default=64 value=64>, 
	# <Control hue type=integer min=-40 max=40 step=1 default=0 value=1>, 
	# <Control white_balance_temperature_auto type=boolean default=1 value=1>, 
	# <Control gamma type=integer min=72 max=500 step=1 default=100 value=72>, 
	# <Control gain type=integer min=0 max=100 step=1 default=0 value=0>, 
	# <Control power_line_frequency type=menu min=0 max=2 step=1 default=2 value=2>, 
	# <Control white_balance_temperature type=integer min=2800 max=6500 step=1 default=4600 value=4600 flags=inactive>, 
	# <Control sharpness type=integer min=0 max=6 step=1 default=3 value=3>, 
	# <Control backlight_compensation type=integer min=0 max=2 step=1 default=1 value=0>, 
	# <Control exposure_auto type=menu min=0 max=3 step=1 default=3 value=1>, 
	# <Control exposure_absolute type=integer min=1 max=5000 step=1 default=157 value=8>, 
	# <Control exposure_auto_priority type=boolean default=0 value=0>
	# }

	time.sleep(1)
	
	vidcap.control_set("brightness"					,	0)
	vidcap.control_set("contrast"					,	32)
	vidcap.control_set("saturation"					,	0)
	vidcap.control_set("hue"						,	1)
	vidcap.control_set("gamma"						,	100)
	vidcap.control_set("gain"						,	0)
	vidcap.control_set("power_line_frequency"		,	0)
	vidcap.control_set("sharpness"					,	6)
	vidcap.control_set("backlight_compensation"		,	0)
	vidcap.control_set("exposure_auto"				,	1)
	vidcap.control_set("exposure_absolute"			,   66)
	vidcap.control_set("exposure_auto_priority"		,	0)
	vidcap.control_set("white_balance_temperature" 	,	4600)

	# time.sleep(2)

	display = Display()
	
	n=100
	t_min = 1000
	t_max = 8333 + t_min # + 2778
	
	config.TRIG_WIDTH = 10
	config.LED_WIDTH = 50
	config.WAVE_DURATION = 40000
	config.LED_TIME = t_min

	c = int((t_max - t_min) // n)

	skip = 0

	vidcap.control_set("exposure_auto_priority", 1)

	config.LED_MASK = 1<<config.RED_OUT # | 1<<GRN_OUT | 1<<BLU_OUT

	s = trigger_wave_script(pig, config)
	wave = PiGPIOWave(pig, config)
	s.start(wave.id)

	frame_count = 0
	start_time = time.time()

	while True:
		for i in range(n + 1):
			s.set_params(0xffffffff)			# deactivate the current wave
			display.waitKey(1)
			# while s.params()[3] != 0:	# wait for sequencing_paused
				# print(s.status(), " ", s.params())
				# time.sleep(0.010)
				# pass
			# now safe to delete the wave
			wave.delete()
			config.LED_TIME = t_min + c*i
			wave = PiGPIOWave(pig, config)
			s.set_params(wave.id)

			# logging.info(s.params())
			try:
				img = vidcap.capture_frame()
				frame_count += 1

				display.show_frame(img)

				if time.time() - start_time >= 3:
					fps = frame_count / (time.time() - start_time)
					logging.info(f"Average FPS: {fps:.2f}")
					frame_count = 0
					start_time = time.time()

			except Exception as e:
				logging.info(f"EXCEPTION: {e}")
				continue
	
	wave.delete()
	s.delete()
	display.close()
	vidcap.close()


import logging
if __name__ == "__main__":
	try:
		fmt = "%(threadName)-10s %(asctime)-15s %(levelname)-5s %(name)s: %(message)s"
		logging.basicConfig(level="INFO", format=fmt)
		main()
	except KeyboardInterrupt:
		logging.info("Ctrl-C pressed. Bailing out")
