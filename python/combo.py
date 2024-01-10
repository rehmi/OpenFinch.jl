import time
from ImageCapture import ImageCapture
from Display import Display
from CameraControl import start_pig, trigger_wave_script, print_summary, params_valid

if __name__ == "__main__":

	pig = start_pig()
	
	vidcap = ImageCapture(capture_raw=False)
	vidcap.open()
	# time.sleep(1)

	vidcap.control_set("exposure_auto_priority", 0)

	# {
	# 9963776: <Control brightness type=integer min=-64 max=64 step=1 default=0 value=32>, 
	# 9963777: <Control contrast type=integer min=0 max=64 step=1 default=32 value=32>, 
	# 9963778: <Control saturation type=integer min=0 max=128 step=1 default=64 value=64>, 
	# 9963779: <Control hue type=integer min=-40 max=40 step=1 default=0 value=1>, 
	# 9963788: <Control white_balance_temperature_auto type=boolean default=1 value=1>, 
	# 9963792: <Control gamma type=integer min=72 max=500 step=1 default=100 value=72>, 
	# 9963795: <Control gain type=integer min=0 max=100 step=1 default=0 value=0>, 
	# 9963800: <Control power_line_frequency type=menu min=0 max=2 step=1 default=2 value=2>, 
	# 9963802: <Control white_balance_temperature type=integer min=2800 max=6500 step=1 default=4600 value=4600 flags=inactive>, 
	# 9963803: <Control sharpness type=integer min=0 max=6 step=1 default=3 value=3>, 
	# 9963804: <Control backlight_compensation type=integer min=0 max=2 step=1 default=1 value=0>, 
	# 10094849: <Control exposure_auto type=menu min=0 max=3 step=1 default=3 value=1>, 
	# 10094850: <Control exposure_absolute type=integer min=1 max=5000 step=1 default=157 value=8>, 
	# 10094851: <Control exposure_auto_priority type=boolean default=0 value=0>
	# }

	time.sleep(1)
	
	vidcap.control_set("brightness"					,	0)
	vidcap.control_set("contrast"					,	32)
	vidcap.control_set("saturation"					,	0)
	vidcap.control_set("hue"						,	1)
	vidcap.control_set("gamma"						,	100)
	vidcap.control_set("gain"						,	0)
	vidcap.control_set("power_line_frequency"		,	2)
	vidcap.control_set("sharpness"					,	3)
	vidcap.control_set("backlight_compensation"		,	0)
	vidcap.control_set("exposure_auto"				,	1)
	vidcap.control_set("exposure_absolute"			,	1)
	vidcap.control_set("exposure_auto_priority"		,	0)
	vidcap.control_set("white_balance_temperature" 	,	4600)

	# time.sleep(2)
 
	display = Display()

	frame_count = 0
	start_time = time.time()

	# trigger_loop(pig)
 
	n=100
	t_min = 0 # 2777
	t_max = 8333 # + 2778
	
	LED_WIDTH = 200

	c = int((t_max - t_min) // n)

	RED_OUT = 17
	GRN_OUT = 27
	BLU_OUT = 23
 
	skip = 0
 
	vidcap.control_set("exposure_auto_priority", 1)

	while True:
		for i in range(n + 1):
			while True:
				LED_TIME = t_min + c*i
				LED_MASK = 1<<RED_OUT # | 1<<GRN_OUT | 1<<BLU_OUT
				s = trigger_wave_script(pig, LED_TIME=LED_TIME, LED_WIDTH=LED_WIDTH, LED_MASK=LED_MASK, WAVE_DURATION=0)
			
				while s.initing():
					pass
				
				s.start()
			
				while s.running():
					pass
			
				p = s.params()
				print_summary(p)

				s.delete()
				pig.wave_clear()
	
				if params_valid(p):
					break
				
				# skip |= 4

			try:
				img = vidcap.capture_frame()
				frame_count += 1

				# if not (skip & 1):
				display.show_frame(img)

				# skip >>= 1

				if time.time() - start_time >= 5:
					fps = frame_count / (time.time() - start_time)
					print(f"Average FPS: {fps:.2f}")
					frame_count = 0
					start_time = time.time()

				if display.waitKey(1) & 0xFF == ord('q'):
					break
			except AttributeError:
				continue

	display.close()
	vidcap.close()
 