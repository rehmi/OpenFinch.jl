module CameraControl

using Images, ImageShow, Colors

using PythonCall

const v4l2py = Ref{Py}()
const pigpio = Ref{Py}()
const pig = Ref{Py}()

function __init__()
	v4l2py[] = pyimport("v4l2py")
	pigpio[] = pyimport("pigpio")
end

function start_pigpio(host="localhost", port=8888)
	pig[] = pigpio[].pi(host, port)
	if ! pyconvert(Bool, pig[].connected)
		error("Couldn't open connection to pigpiod")
	end
end

function scriptHalted(s)
    e, p = pig[].script_status(s)
    return Bool(e == pigpio[].PI_SCRIPT_HALTED)
end

function scriptIniting(s)
    e, p = pig[].script_status(s)
    return Bool(e == pigpio[].PI_SCRIPT_INITING)
end

function scriptRunning(s)
    e, p = pig[].script_status(s)
    return Bool(e == pigpio[].PI_SCRIPT_RUNNING)
end

function preprocess_script(scr)
	# split the script into lines
	lines = split(scr, "\n")
	# split each line at the first comment character, keeping the leading text
	uncommented = (line->first(split(line, "#"))).(lines)
	# strip leading and trailing whitespace from each line
	stripped = strip.(uncommented)
	# keep only nonempty lines
	nonempty = filter(line->!isempty(line), stripped)
	# rejoin the nonempty lines into a single string
	return join(nonempty, "\n")
end

trigger_script = """
	# p0: N_EXPOSURES
	# p1: TRIG_IN
	# p2: TRIG_DELAY
	# p3: TRIG_OUT
	# p4: TRIG_WIDTH
	# p5: LED_IN
	# p6: LED_DELAY
	# p7: LED_OUT
	# p8: LED_WIDTH
	# p9: STROBE_IN
   	
	ld v0 p0				# load N_EXPOSURES into v0
	dcr v0					# predecrement v0 because JP considers 0 to be positive

tag 0	r p1	jz 0 		# loop until TRIG_IN is HIGH
tag 1	r p1	jnz 1 		# loop until TRIG_IN is LOW
							# just saw falling edge on TRIG_IN

	mics p2 				# wait TRIG_DELAY µs

	w p3 0	mics p4	w p3 1  # send negative pulse to TRIG_OUT for TRIG_WIDTH µs

tag 2	r p9	jz 2 		# loop until STROBE_IN goes HIGH
							# just saw rising edge on STROBE_IN

tag 3	r p5	jz 3 		# loop until LED_IN is HIGH
tag 4	r p5	jnz 4		# loop until LED_IN goes LOW
							# just saw rising edge on LED_IN
	
	mics p6					# wait LED_DELAY µs

	w p7 0	mics p8	w p7 1 	# pulse LED_OUT LOW for LED_WIDTH µs

	w 27 1

tag 5	r p9	jnz 5 		# loop until STROBE_IN is LOW
tag 6	r p9	jz 6		# loop until STROBE_IN goes HIGH
							# just saw rising edge on STROBE_IN
tag 7	r p9	jnz 7		# loop until STROBE_IN goes low
							# just saw falling edge on STROBE_IN

	w 27 0
	
	mils 125				# need this to wait for end of second strobe

	dcr v0
    jp 0
"""


function trigger(n = 1)
	
	N_EXPOSURES = n			# p0
	TRIG_IN = 24 			# p1
	TRIG_DELAY = 100		# p2
	TRIG_OUT = 5 			# p3
	TRIG_WIDTH = 100 		# p4
	LED_IN = 22 			# p5
	LED_DELAY = 200 		# p6
	LED_OUT = 17 			# p7
	LED_WIDTH = 250 		# p8
	STROBE_IN = 6 			# p9

	# cb = pig[].callback(TRIG_OUT)
	old_exceptions = pigpio[].exceptions
	pigpio[].exceptions = pybool(false)
	s = pig[].store_script(preprocess_script(trigger_script))
	@info "Stored script $s"

	try
		# Ensure the script has finished initializing.
		while scriptIniting(s)
			sleep(0.01)
		end

		pig[].run_script(s,	[
			N_EXPOSURES, 
			TRIG_IN, TRIG_DELAY, TRIG_OUT, TRIG_WIDTH,
			LED_IN, LED_DELAY, LED_OUT, LED_WIDTH,
			STROBE_IN
		])

		while scriptHalted(s)
			sleep(0.01)
		end

		while scriptRunning(s)
			sleep(0.01)
		end
	
	catch err
		@info "Caught error $err"
	finally
		@info "Stopping script $s"
		pig[].stop_script(s)
		@info "Deleting script $s"
		pig[].delete_script(s)
		pigpio[].exceptions = old_exceptions
	end
end

end # module CameraControl