from enum import Enum
# import v4l2py
import pigpio

# from PIL import Image, ImageShow, ImageColor

class ScriptStatus(Enum):
	INITING = 0
	HALTED = 1
	RUNNING = 2
	WAITING = 3
	FAILED = 4

def preprocess_script(text):
	# Split the script into lines
	lines = text.split('\n')
	# Split each line at the first comment character, keeping the leading text
	uncommented = [line.split('#')[0] for line in lines]
	# Strip leading and trailing whitespace from each line
	stripped = [line.strip() for line in uncommented]
	# Keep only nonempty lines
	nonempty = [line for line in stripped if line]
	# Rejoin the nonempty lines into a single string
	return '\n'.join(nonempty)

class PiGPIOScript:
	def __init__(self, pig, text=None, id=None):
		if text is not None:
			self.pptext = preprocess_script(text)
			self.id = pig.store_script(self.pptext)
		elif id is not None:
			self.id = id
			self.pptext = ''
			self.text = ''
		self.pig = pig
		self.text = text if text else ''
		self.waves = []
		# print(f"{self} created")

	def __del__(self):
		# print(f"{self} finalizing")
		self.stop()
		self.delete()

	def __str__(self):
		return f"PiGPIOScript({self.pig}, id={self.id})"
	
	def __repr__(self):
		return self.__str__()

	def delete(self):
		if self.id >= 0:
			self.pig.delete_script(self.id)
			self.id = -1
	
	def start(self, *args):
		if self.id >= 0:
			self.pig.run_script(self.id, list(args))
	
	def run(self, *args):
		if self.id >= 0:
			self.pig.run_script(self.id, list(args))
	
	def stop(self):
		if self.id >= 0:
			self.pig.stop_script(self.id)

	def status(self):
		e, _ = self.pig.script_status(self.id)
		return ScriptStatus(e)

	def params(self):
		_, p = self.pig.script_status(self.id)
		return p

	def set_params(self, *args):
		if self.id >= 0:
			self.pig.update_script(self.id, list(args))

	def params_valid(self):
		params = self.params()
		hi_to_lo = params[8] - params[6]
		return (0 < hi_to_lo < 8340)

	def param_summary(self):
		params = self.params()
		start_gpio = f"{params[4]:08x}"
		start_to_hi = params[6] - params[5]
		triglo_gpio = f"{params[7]:08x}"
		hi_to_lo = params[8] - params[6]
		lo_to_finish = params[9] - params[8]
		
		summary = f"{start_gpio} {start_to_hi:5d} TrigHI {hi_to_lo:5d} {triglo_gpio} {lo_to_finish:5d} Finish"
		return summary

	def halted(self):
		return self.status() == ScriptStatus.HALTED

	def initing(self):
		return self.status() == ScriptStatus.INITING

	def running(self):
		return self.status() == ScriptStatus.RUNNING


def start_pig(host="localhost", port=8888):
	pig = pigpio.pi(host, port)
	if not pig.connected:
		raise ValueError("Couldn't open connection to pigpiod")
		# raise Exception('Could not connect to pigpio')
	return pig

class PiGPIOWave:
	def __init__(self, pig, config):
		self.pig = pig
		self.config = config
		self.kwargs = config.__dict__
		self.wave = []
		self.id = self.generate_wave()

	def __str__(self):
		return f"PiGPIOWave{self.pig}, id={self.id})"
	
	def __repr__(self):
		return self.__str__()

	def __del__(self):
		self.delete()

	def delete(self):
		if self.id >= 0:
			self.pig.wave_delete(self.id)
			self.id = -1

	def generate_wave(self):
		cf = self.config

		for pin in [cf.TRIG_OUT, cf.RED_OUT, cf.GRN_OUT, cf.BLU_OUT, cf.LED_OUT]:
			self.pig.set_mode(pin, pigpio.OUTPUT)

		for pin in [cf.TRIG_IN, cf.LED_IN, cf.STROBE_IN]:
			self.pig.set_mode(pin, pigpio.INPUT)

		dtled = max(0, cf.LED_TIME - cf.TRIG_WIDTH - cf.TRIG_TIME)
		dtif = max(0, cf.WAVE_DURATION - cf.LED_TIME - cf.LED_WIDTH - cf.TRIG_TIME - cf.TRIG_WIDTH)

		LED_ON_HIGH = cf.LED_MASK
		LED_ON_LOW = 0
		LED_OFF_HIGH = 0
		LED_OFF_LOW = cf.LED_MASK

		self.wave.append(pigpio.pulse(0, 0, cf.TRIG_TIME))
		self.wave.append(pigpio.pulse(0, 1<<cf.TRIG_OUT, cf.TRIG_WIDTH))
		self.wave.append(pigpio.pulse(1<<cf.TRIG_OUT, 0, dtled))
		self.wave.append(pigpio.pulse(LED_ON_HIGH, LED_ON_LOW, cf.LED_WIDTH))
		self.wave.append(pigpio.pulse(LED_OFF_HIGH, LED_OFF_LOW, dtif))
		self.pig.wave_add_generic(self.wave)
		return self.pig.wave_create()


def trigger_wave_script(pig, config):
	script = f"""
	pads 0 16								# set pad drivers to 16 mA

	# we expect wave id in p0
	lda {config.TRIG_IN} sta p1
	lda {config.STROBE_IN} sta p2

	ld p3 1				# status: starting

tag 100
	lda p0         		# load the current value of p0
	or 0 jp 101    		# if p0 is valid (>=0), proceed
	ld p3 0				# status: sequencing paused
	mils 1      		# otherwise delay for a bit
	jmp 100       		# and try again

# 	ld p3 2 			# status: waiting for p2 low
# tag 110
# 	r p2 jnz 110		# wait if p2 is high
# 	ld p3 3				# status: waiting for p2 high
# tag 111
# 	r p2 jz 111			# wait for rising edge of p2

	ld p3 4				# status: sequencing started
	br1 sta v4			# capture starting GPIO in p4
	tick sta v5			# capture the start time in p5

tag 101
	r p1 jz 101			# wait for p1 to go high
	tick sta v6			# capture trigger high time in p6

	ld p3 5
tag 102
	r p1 jnz 102		# wait for falling edge on p1
	br1 sta v7			# capture GPIO at trigger low in p7
	tick sta v8			# capture trigger low time in p8
	ld p3 6				# status: wave tx started
	wvtx p0				# trigger the wave

tag 103
	wvbsy
	jnz 103 			# wait for wave to finish
	tick sta v9			# capture wave finish time in p9
	ld p3 7				# status: wave tx complete
	ld p4 v4 ld p5 v5 ld p6 v6 ld p7 v7 ld p8 v8 ld p9 v9
	ld p3 8				# status: return params updated 

	jmp 100				# do it again
	ret
	"""

	return PiGPIOScript(pig, script)

import time

def trigger_loop(pig, n=1000, t_min=2777, t_max=2778+8333, **kwargs):
	c = int((t_max - t_min) // n)

	start_time = time.time()

	for i in range(n + 1):
		s = trigger_wave_script(pig, LED_TIME=t_min + i * c, **kwargs)
		
		while s.initing():
			pass
		
		s.start()
		
		while s.running():
			pass
		
		p = s.params()
		print_summary(p)

		s.delete()
		pig.wave_clear()

	# capture the end time
	end_time = time.time()

	# Calculate the elapsed time
	elapsed_time = end_time - start_time
	
	print(f"{n/elapsed_time} fps")
	
	return fps



if __name__ == "__main__":
	pig = start_pig()
	trigger_loop(pig)

