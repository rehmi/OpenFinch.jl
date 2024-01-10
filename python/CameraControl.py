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
	def __init__(self, pig, text=None, index=None):
		if text is not None:
			self.pptext = preprocess_script(text)
			self.index = pig.store_script(self.pptext)
		elif index is not None:
			self.index = index
			self.pptext = ''
			self.text = ''
		self.pig = pig
		self.text = text if text else ''
		# print(f"{self} created")

	def __del__(self):
		# print(f"{self} finalizing")
		self.stop()
		self.delete()

	def __str__(self):
		return f"PiGPIOScript({self.pig}, index={self.index})"
	
	def __repr__(self):
		return self.__str__()

	def delete(self):
		if self.index >= 0:
			self.pig.delete_script(self.index)
			self.index = -1
	
	def start(self, *args):
		if self.index >= 0:
			self.pig.run_script(self.index, list(args))
	
	def run(self, *args):
		if self.index >= 0:
			self.pig.run_script(self.index, list(args))
	
	def stop(self):
		if self.index >= 0:
			self.pig.stop_script(self.index)

	def status(self):
		e, _ = self.pig.script_status(self.index)
		return ScriptStatus(e)

	def params(self):
		_, p = self.pig.script_status(self.index)
		return p

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
	def __init__(self, pig, **kwargs):
		self.pig = pig
		self.kwargs = kwargs
		self.wave = []
		self.id = self.generate_wave()

	def generate_wave(self):
		TRIG_IN = self.kwargs.get('TRIG_IN', 25)
		TRIG_TIME = self.kwargs.get('TRIG_TIME', 0)
		TRIG_OUT = self.kwargs.get('TRIG_OUT', 5)
		TRIG_WIDTH = self.kwargs.get('TRIG_WIDTH', 50)
		LED_IN = self.kwargs.get('LED_IN', 22)
		LED_TIME = self.kwargs.get('LED_TIME', 5555)
		LED_OUT = self.kwargs.get('LED_OUT', 17)
		RED_OUT = self.kwargs.get('RED_OUT', 17)
		GRN_OUT = self.kwargs.get('GRN_OUT', 27)
		BLU_OUT = self.kwargs.get('BLU_OUT', 23)
		LED_WIDTH = self.kwargs.get('LED_WIDTH', 500)
		STROBE_IN = self.kwargs.get('STROBE_IN', 6)
		WAVE_DURATION = self.kwargs.get('WAVE_DURATION', 16667)

		for pin in [TRIG_OUT, RED_OUT, GRN_OUT, BLU_OUT, LED_OUT]:
			self.pig.set_mode(pin, pigpio.OUTPUT)

		for pin in [TRIG_IN, LED_IN, STROBE_IN]:
			self.pig.set_mode(pin, pigpio.INPUT)

		dtled = max(0, LED_TIME - TRIG_WIDTH - TRIG_TIME)
		dtif = max(0, WAVE_DURATION - LED_TIME - LED_WIDTH - TRIG_TIME - TRIG_WIDTH)

		LED_ON_HIGH = self.kwargs.get('LED_MASK', 1<<LED_OUT)
		LED_ON_LOW = 0
		LED_OFF_HIGH = 0
		LED_OFF_LOW = self.kwargs.get('LED_MASK', 1<<LED_OUT)

		self.wave.append(pigpio.pulse(0, 0, TRIG_TIME))
		self.wave.append(pigpio.pulse(0, 1<<TRIG_OUT, TRIG_WIDTH))
		self.wave.append(pigpio.pulse(1<<TRIG_OUT, 0, dtled))
		self.wave.append(pigpio.pulse(LED_ON_HIGH, LED_ON_LOW, LED_WIDTH))
		self.wave.append(pigpio.pulse(LED_OFF_HIGH, LED_OFF_LOW, dtif))
		self.pig.wave_add_generic(self.wave)
		return self.pig.wave_create()

		def delete_wave(self):
			self.pig.wave_delete(self.id)


def trigger_wave_script(pig, **kwargs):
	# Default values for the parameters
	TRIG_IN = kwargs.get('TRIG_IN', 25)
	STROBE_IN = kwargs.get('STROBE_IN', 6)

	wave = PiGPIOWave(pig, **kwargs)
	
	script = f"""
	pads 0 16								# set pad drivers to 16 mA

	lda {wave.id} sta p0
	lda {TRIG_IN} sta p1
	lda {STROBE_IN} sta p2

tag 100
	br1 sta p4								# capture starting GPIO in p4
	tick sta p5								# capture the start time in p5

tag 101	mics 1	r p1		jz 101			# wait for p1 to go high

	tick sta p6								# capture trigger high time in p6

tag 102	mics 1 r p1			jnz 102			# wait for falling edge on p1

	br1 sta p7								# capture GPIO at trigger low in p7
	tick sta p8								# capture trigger low time in p8

	wvtx p0									# trigger the wave
tag 103	wvbsy	jnz 103 					# wait for wave to finish
	tick sta p9								# capture wave finish time in p9

	# wvdel p0		 						# release the wave resources
	# jmp 100
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

