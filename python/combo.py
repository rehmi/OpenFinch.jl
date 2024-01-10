import time
from ImageCapture import ImageCapture
from Display import Display
from CameraControl import start_pig, trigger_wave_script, print_summary, params_valid

if __name__ == "__main__":

	pig = start_pig()
	
	vidcap = ImageCapture(capture_raw=False)
	vidcap.open()
	time.sleep(1)

	vidcap.control_set("exposure_auto_priority", 0)

	vidcap.control_set("brightness"					,	32)
	vidcap.control_set("contrast"					,	32)
	vidcap.control_set("saturation"					,	64)
	vidcap.control_set("hue"						,	1)
	vidcap.control_set("gamma"						,	72)
	vidcap.control_set("gain"						,	54)
	vidcap.control_set("power_line_frequency"		,	2)
	vidcap.control_set("sharpness"					,	3)
	vidcap.control_set("backlight_compensation"		,	0)
	vidcap.control_set("exposure_auto"				,	1)
	vidcap.control_set("exposure_absolute"			,	8)
	vidcap.control_set("exposure_auto_priority"		,	0)
	vidcap.control_set("white_balance_temperature" 	,	4600)

	# time.sleep(2)
 
	display = Display()

	frame_count = 0
	start_time = time.time()

	# trigger_loop(pig)
 
	n=1000
	t_min=2777
	t_max=2778+8333
	c = int((t_max - t_min) // n)
 
	skip = 0
 
	vidcap.control_set("exposure_auto_priority", 1)

	while True:
		for i in range(n + 1):
			while True:
				LED_TIME = t_min + 800 # + c*i
				s = trigger_wave_script(pig, LED_TIME=LED_TIME, LED_WIDTH=100)
			
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
 