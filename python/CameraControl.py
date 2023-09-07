from enum import Enum
import v4l2py
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

def trigger_wave_script(pig, **kwargs):
	# Default values for the parameters
	TRIG_IN = kwargs.get('TRIG_IN', 25)
	TRIG_TIME = kwargs.get('TRIG_TIME', 0)
	TRIG_OUT = kwargs.get('TRIG_OUT', 5)
	TRIG_WIDTH = kwargs.get('TRIG_WIDTH', 50)
	LED_IN = kwargs.get('LED_IN', 22)
	LED_TIME = kwargs.get('LED_TIME', 5555)
	LED_OUT = kwargs.get('LED_OUT', 17)
	LED_WIDTH = kwargs.get('LED_WIDTH', 250)
	STROBE_IN = kwargs.get('STROBE_IN', 6)
	WAVE_DURATION = kwargs.get('WAVE_DURATION', 16667)
	G1 = kwargs.get('G1', 23)
	G2 = kwargs.get('G2', 27)

	for pin in [G1, G2, TRIG_OUT, LED_OUT]:
		pig.set_mode(pin, pigpio.OUTPUT)

	for pin in [TRIG_IN, LED_IN, STROBE_IN]:
		pig.set_mode(pin, pigpio.INPUT)

	dtled = max(0, LED_TIME - TRIG_WIDTH - TRIG_TIME)
	dtif = max(0, WAVE_DURATION - LED_TIME - LED_WIDTH - TRIG_TIME - TRIG_WIDTH)

	wave = []
	wave.append(pigpio.pulse(0, 0, TRIG_TIME))
	wave.append(pigpio.pulse(0, 1<<TRIG_OUT, TRIG_WIDTH))
	wave.append(pigpio.pulse(1<<TRIG_OUT, 0, dtled))
	wave.append(pigpio.pulse(0, 1<<LED_OUT, LED_WIDTH))
	wave.append(pigpio.pulse(1<<LED_OUT, 0, dtif))
	pig.wave_add_generic(wave)
	wave_id = pig.wave_create()
	
	script = f"""
	pads 0 16							# set pad drivers to 16 mA
	lda 0 sta p0

	lda {TRIG_IN} sta p1
	lda {TRIG_TIME} sta p2
	lda {LED_TIME} sta p3
	lda {LED_WIDTH} sta p4

tag 100
	tick sta p5
	w {G1} 1
tag 101	mics 1	r {TRIG_IN}	jz 101				# wait for TRIG_IN to go high
	tick sub p5 sta p6
tag 102	inr p0	mics 1 r {TRIG_IN}	jnz 102		# wait for falling edge on TRIG_IN
	tick sub p5 sta p7
	w {G1} 0

	wvtx {wave_id} 						# trigger the wave created above

	w {G2} 1
# tag 104	mics 1	r {STROBE_IN}	jz 104	# wait for STROBE_IN to go high
# tag 105	mics 1	r {STROBE_IN}	jnz 105	# wait for STROBE_IN to go low
# tag 106	mics 1	r {STROBE_IN}	jz 106	# wait for STROBE_IN to go high
# tag 107	mics 1	r {STROBE_IN}	jnz 107	# wait for STROBE_IN to go low
	tick sub p5 sta p8
tag 103	wvbsy	jnz 103 				# wait for wave to finish
	tick sub p5 sta p9
	# wvdel {wave_id} 					# release the wave resources
	w {G2} 0

	ret
	"""
	return PiGPIOScript(pig, script)

import time

def trigger_loop(pig, n=100, t_min=2777, t_max=2778+8333, **kwargs):
	c = int((t_max - t_min) // n)

	start_time = time.time()

	for i in range(n + 1):
		s = trigger_wave_script(pig, LED_TIME=t_min + i * c, **kwargs)
		
		while s.initing():
			pass
		
		s.start()
		
		while s.running():
			pass
		
		s.delete()
		pig.wave_clear()

	# capture the end time
	end_time = time.time()

	# Calculate the elapsed time
	elapsed_time = end_time - start_time
	
	return f"{n/elapsed_time} fps"
