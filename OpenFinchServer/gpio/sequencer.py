from enum import Enum
import pigpio
from dataclasses import dataclass
from gpio.wavegen import WaveGen
import logging

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
    GRN_OUT: int = 23
    BLU_OUT: int = 27
    
    TRIG_IN: int = BLU_IN
    BLU_START: int = 0
    GRN_START: int = 2742
    RED_START: int = 2742 + 2777

    TRIG_OUT: int = 5
    STROBE_IN: int = 6

    # LED_IN: int = TRIG_IN
    # LED_OUT: int = RED_OUT
    # TRIG_OUT: int = TRIG_OUT
    
    TRIG_TIME: int = 0
    TRIG_WIDTH: int = 8000
    LED_TIME: int = 400
    LED_WIDTH: int = 5
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
        # logging.debug(f"Entering PiGPIOScript.start({self.id}, args={args})")
        if self.id >= 0:
            self.pig.run_script(self.id, list(args))
    
    def run(self, *args):
        # logging.debug(f"Entering PiGPIOScript.run(id={self.id}, args={args})")
        if self.id >= 0:
            self.pig.run_script(self.id, list(args))
    
    def stop(self):
        # logging.debug(f"PiGPIOScript.stop(id={self.id})")
        if self.id >= 0:
            self.pig.stop_script(self.id)

    def set_params(self, *args):
        # logging.debug(f"Entering PiGPIOScript.set_params(id={self.id}, args={args})")
        if self.id >= 0:
            self.pig.update_script(self.id, list(args))

    def status(self):
        e, _ = self.pig.script_status(self.id)
        return ScriptStatus(e)

    def params(self):
        _, p = self.pig.script_status(self.id)
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
    def __init__(self, pig, config, trigger_camera=True):
        self.pig = pig
        self.config = config
        # self.kwargs = config.__dict__
        self.wavegen = WaveGen()
        self.trigger_camera = trigger_camera
        self.id = self.generate_wave(trigger_camera=trigger_camera)

    def __str__(self):
        return f"PiGPIOWave{self.pig}, id={self.id}, trigger_camera={self.trigger_camera}"
    
    def __repr__(self):
        return self.__str__()

    def __del__(self):
        self.delete()

    def delete(self):
        # logging.debug(f"Deleting wave {self}")
        if self.id >= 0:
            self.pig.wave_delete(self.id)
            self.id = -1

    def generate_wave(self, trigger_camera=True):
        cf = self.config
        
        RED_WIDTH = cf.LED_WIDTH
        GRN_WIDTH = cf.LED_WIDTH
        BLU_WIDTH = cf.LED_WIDTH
        
        RED_TIME = cf.LED_TIME + cf.RED_START
        GRN_TIME = cf.LED_TIME + cf.GRN_START
        BLU_TIME = cf.LED_TIME + cf.BLU_START

        # Define the initial state of the pins
        # self.wavegen.change_bit(cf.TRIG_OUT, 0, 0)
        # self.wavegen.change_bit(cf.RED_OUT, 0, 0)
        # self.wavegen.change_bit(cf.GRN_OUT, 0, 0)
        # self.wavegen.change_bit(cf.BLU_OUT, 0, 0)
        # self.wavegen.change_bit(cf.LED_OUT, 0, 0)

        # Camera trigger pulse
        if trigger_camera:
            self.wavegen.change_bit(cf.TRIG_OUT, 0, cf.TRIG_TIME)
            self.wavegen.change_bit(cf.TRIG_OUT, 1, cf.TRIG_TIME + cf.TRIG_WIDTH)

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
        self.wavegen.change_bit(cf.STROBE_IN, 1, cf.WAVE_DURATION)
        
        # Convert the wavegen changes to pigpio wave format
        wave = [
            pigpio.pulse(set_mask, clr_mask, delay)
            for set_mask, clr_mask, delay in self.wavegen.wave_vector
        ]
        self.pig.wave_add_new()
        self.pig.wave_add_generic(wave)
        id = self.pig.wave_create()
        # logging.debug(f"PiGPIOWave.generate_wave() => id={id}")
        return id

class Sequencer:
    def __init__(self, pig, config):
        self.pig = pig
        self.config = config
        self.initialize_gpio()
        self.initialize_trigger()
        self.setup_waves()

    def initialize_gpio(self):
        cf = self.config

        for pin in [cf.TRIG_OUT, cf.RED_OUT, cf.GRN_OUT, cf.BLU_OUT]:
            self.pig.set_mode(pin, pigpio.OUTPUT)

        for pin in [cf.TRIG_IN, cf.RED_IN, cf.GRN_IN, cf.BLU_IN, cf.STROBE_IN]:
            self.pig.set_mode(pin, pigpio.INPUT)

    def setup_waves(self):
        self.wave_RGB = PiGPIOWave(self.pig, self.config, trigger_camera=False)
        self.wave_RGB_trig = PiGPIOWave(self.pig, self.config, trigger_camera=True)

    def initialize_trigger(self):
        self.script = self.trigger_wave_script(self.pig, self.config)
        # self.wave = PiGPIOWave(self.pig, self.config)
        self.setup_waves()

        # Wait for the script to finish initializing before starting it
        while self.script.initing():
            pass
        self.script.start(self.wave_RGB.id, self.wave_RGB_trig.id)

    def update_wave(self):
        ### XXX N.B. this implicitly depends on self.config
        old_RGB = self.wave_RGB
        old_RGB_trig = self.wave_RGB_trig
        self.setup_waves()
        self.script.set_params(self.wave_RGB.id, self.wave_RGB_trig.id)
        # old_RGB.delete()
        # old_RGB_trig.delete()
        
    def trigger_wave_script(self, pig, config):
        script = f"""
        pads 0 16								# set pad drivers to 16 mA

        # we expect RGB wave id in p0, RGB+trig wave id in p1
        lda {config.TRIG_IN} sta p2
        # lda 3 sta p3        # set p3 (wave repeat counter)
        lda 0 sta v3

    tag 100
        lda p0         		# load the current value of p0
        or 0 jp 115    		# if p0 is valid (>=0), proceed
        mics 101      		# otherwise delay for a bit
        jmp 100       		# and try again
        
    tag 115
        lda v3 or 0 jz 116  # if the wave repeat counter is 0, jmp to 116
        ld v0 p0            # load the RGB wave id into v0
        dcr v3              # decrement the wave repeat counter
        jmp 120
        
    tag 116                 # wave repeat counter is zero
        ld v0 p1            # load the RGB+trig wave id into v0
        lda 3 sta v3        # load the RGB wave repeat counter into v3
        jmp 120

    tag 120
        r p2 jnz 121        # read the GPIO and jump out of loop if it's high
        mics 101           	# otherwise delay for a bit
        jmp 120            	# and continue polling
    tag 121

    tag 130
        r p2 jnz 130		# wait for falling edge on p2

        wvtx v0				# trigger the wave

    tag 140
        mics 101			# delay for a bit
        wvbsy
        jnz 140 			# wait for wave to finish

        jmp 100				# do it again
        ret
        """

        return PiGPIOScript(pig, script)
