from enum import Enum
import pigpio
from dataclasses import dataclass
from .wavegen import WaveGen


class ScriptStatus(Enum):
    INITING = 0
    HALTED = 1
    RUNNING = 2
    WAITING = 3
    FAILED = 4

# Sequential field color timing
# Field order: B 2742µs G 2777µs R 2749µs B 2742µs G 2777µs R 2883µs B ...
# BLU low to GRN low = 2742 us
# GRN low to RED low = 2777 us
# RED low to BLU low = 2749, 2883 us (alternating)
# BLU low to BLU low = 8264, 8403 us (sum is 16667 us)

@dataclass(frozen=False)
class TriggerConfig:
    RED_IN: int = 22
    GRN_IN: int = 24
    BLU_IN: int = 25

    RED_OUT: int = 17
    GRN_OUT: int = 27
    BLU_OUT: int = 23
    
    RED_FACTOR: float = 1
    GRN_FACTOR: float = 3
    BLU_FACTOR: float = 1
    
    TRIG_IN: int = BLU_IN
    BLU_START: int = 0
    GRN_START: int = 2742
    RED_START: int = 2742 + 2777

    TRIG_OUT: int = 5
    STROBE_IN: int = 6

    LED_IN: int = TRIG_IN
    LED_OUT: int = RED_OUT
    TRIG_OUT: int = TRIG_OUT
    
    TRIG_TIME: int = 0
    TRIG_WIDTH: int = 10
    LED_TIME: int = 400
    LED_WIDTH: int = 4
    WAVE_DURATION: int = 8000

class PiGPIOScript:
    def __init__(self, pig, text=None, id=None):
        if text is not None:
            self.pptext = self.preprocess_script(text)
            self.id = pig.store_script(self.pptext)
        elif id is not None:
            self.id = id
            self.pptext = ''
            self.text = ''
        self.pig = pig
        self.text = text if text else ''
        self.waves = []
        # print(f"{self} created")

    def preprocess_script(self, text):
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

from .wavegen import WaveGen

class PiGPIOWave:
    def __init__(self, pig, config):
        self.pig = pig
        self.config = config
        # self.kwargs = config.__dict__
        self.wavegen = WaveGen()
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
        
        RED_WIDTH = cf.RED_FACTOR * cf.LED_WIDTH
        GRN_WIDTH = cf.GRN_FACTOR * cf.LED_WIDTH
        BLU_WIDTH = cf.BLU_FACTOR * cf.LED_WIDTH
        
        RED_TIME = cf.LED_TIME + cf.RED_START
        GRN_TIME = cf.LED_TIME + cf.GRN_START
        BLU_TIME = cf.LED_TIME + cf.BLU_START

        # Define the initial state of the pins
        # self.wavegen.change_bit(cf.TRIG_OUT, 0, 0)
        # self.wavegen.change_bit(cf.RED_OUT, 0, 0)
        # self.wavegen.change_bit(cf.GRN_OUT, 0, 0)
        # self.wavegen.change_bit(cf.BLU_OUT, 0, 0)
        # self.wavegen.change_bit(cf.LED_OUT, 0, 0)

        # Camera trigger puls
        self.wavegen.change_bit(cf.TRIG_OUT, 1, cf.TRIG_TIME)
        self.wavegen.change_bit(cf.TRIG_OUT, 0, cf.TRIG_TIME + cf.TRIG_WIDTH)

        # RED LED pulse
        self.wavegen.change_bit(cf.RED_OUT, 1, RED_TIME)
        self.wavegen.change_bit(cf.RED_OUT, 0, RED_TIME + RED_WIDTH)

        # GRN LED pulse
        self.wavegen.change_bit(cf.GRN_OUT, 1, GRN_TIME)
        self.wavegen.change_bit(cf.GRN_OUT, 0, GRN_TIME + GRN_WIDTH)

        # BLU LED pulse
        self.wavegen.change_bit(cf.BLU_OUT, 1, BLU_TIME)
        self.wavegen.change_bit(cf.BLU_OUT, 0, BLU_TIME + BLU_WIDTH)

        # Add a final event to pad to desired duration
        self.wavegen.change_bit(cf.TRIG_OUT, 0, cf.WAVE_DURATION)
        
        # Convert the wavegen changes to pigpio wave format
        wave = [
            pigpio.pulse(set_mask, clr_mask, delay)
            for set_mask, clr_mask, delay in self.wavegen.wave_vector
        ]

        self.pig.wave_add_generic(wave)
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
    # ld p3 0				# status: sequencing paused
    # mics 100      		# otherwise delay for a bit
    jmp 100       		# and try again

# 	ld p3 2 			# status: waiting for p2 low
# tag 110
# 	r p2 jnz 110		# wait if p2 is high
# 	ld p3 3				# status: waiting for p2 high
# tag 111
# 	r p2 jz 111			# wait for rising edge of p2

    # ld p3 4				# status: sequencing started
    # br1 sta v4			# capture starting GPIO in p4
    # tick sta v5			# capture the start time in p5

tag 101
    r p1 jz 101			# wait for p1 to go high
    # tick sta v6			# capture trigger high time in p6

    # ld p3 5
tag 102
    r p1 jnz 102		# wait for falling edge on p1
    # br1 sta v7			# capture GPIO at trigger low in p7
    # tick sta v8			# capture trigger low time in p8
    # ld p3 6				# status: wave tx started
    wvtx p0				# trigger the wave

tag 103
    wvbsy
    jnz 103 			# wait for wave to finish
    # tick sta v9			# capture wave finish time in p9
    # ld p3 7				# status: wave tx complete
    # ld p4 v4 ld p5 v5 ld p6 v6 ld p7 v7 ld p8 v8 ld p9 v9
    # ld p3 8				# status: return params updated 

    jmp 100				# do it again
    ret
    """

    return PiGPIOScript(pig, script)
