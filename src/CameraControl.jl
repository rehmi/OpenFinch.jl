module CameraControl

using Images, ImageShow, Colors

using PythonCall

mutable struct PiGPIOScript
	pig
	index
	pptext
	text

	function PiGPIOScript(pig, text)
		pptext = preprocess_script(text)
		index = pyconvert(Int, pig.store_script(pptext))
		function f(o)
			stop(o)
			delete!(o)
			o.index = -1
		end
		finalizer(f, new(pig, index, pptext, text))
	end
end

function Base.show(io::IO, ::MIME"text/plain", scr::PiGPIOScript)
	print(io, "PiGPIOScript($(scr.pig), index=$(scr.index), status=$(status(scr)))")
end

function Base.delete!(scr::PiGPIOScript)
	scr.pig.delete_script(scr.index)
end

function start(scr::PiGPIOScript, args...)
    scr.pig.run_script(scr.index, collect(args))
end

function stop(scr::PiGPIOScript)
	scr.pig.stop_script(scr.index)
end

Base.run(scr::PiGPIOScript, args...) = start(scr, args)
halt(scr::PiGPIOScript) = stop(scr)

function status(scr::PiGPIOScript)
	if scr.index < 0
		return :FINALIZED
	end
    e, p = scr.pig.script_status(scr.index)
    p = Int64.(reinterpret(UInt32, Int32.(collect(pyconvert(Tuple, p)))))
    e = ScriptStatus(pyconvert(Int, e))
    return e, p
end

export PiGPIOScript, stop, start, halt, status

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

function start_pig(host="localhost", port=8888)
    pig = pigpio[].pi(host, port)
    if !pyconvert(Bool, pig.connected)
        error("Couldn't open connection to pigpiod")
    end
	return pig
end

@enum ScriptStatus begin
	INITING = 0
	HALTED = 1
	RUNNING = 2
	WAITING = 3
	FAILED = 4
end

export start_pigpio, start_pig
export storeScript, runScript, stopScript, deleteScript
export ScriptStatus
export scriptStatus, scriptHalted, scriptIniting, scriptRunning

function scriptStatus(s::Int)
	e, p = pig[].script_status(s)
	p = Int64.(reinterpret(UInt32, Int32.(collect(pyconvert(Tuple, p)))))
	e = ScriptStatus(pyconvert(Int, e))
	return e, p
end

function scriptHalted(s)
    e, p = scriptStatus(s)
    return e == HALTED
end

function scriptIniting(s)
    e, p = scriptStatus(s)
    return e == INITING
end

function scriptRunning(s)
    e, p = scriptStatus(s)
    return e == RUNNING
end

function storeScript(script)
    s = pyconvert(Int, pig[].store_script(preprocess_script(script)))
    @info "Stored script $s"
    return s
end

function runScript(s, args...)
    pig[].run_script(s, collect(args))
end

function stopScript(s)
	@info "Stopping script $s"
	pig[].stop_script(s)
end

function deleteScript(s)
	@info "Deleting script $s"
	pig[].delete_script(s)
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

export trigger_wave_script
function trigger_wave_script(pig;
	TRIG_IN = 25,
	TRIG_DELAY = 10,
	TRIG_OUT = 5,
	TRIG_WIDTH = 50,
	LED_IN = 22,
	LED_DELAY = 5555,
	LED_OUT = 17,	
	LED_WIDTH = 800,
	STROBE_IN = 6,
	INTERFRAME_DELAY = 16_000,
	G1 = 23,
	G2 = 27

)
	p = pigpio[]
	
	for pin ∈ [G1, G2, TRIG_OUT, LED_OUT]
		pig.set_mode(pin, p.OUTPUT)
	end
	for pin ∈ [TRIG_IN, LED_IN, STROBE_IN]
		pig.set_mode(pin, p.INPUT)
	end

	wave = @py []
	wave.append(p.pulse(1<<G1, 0, TRIG_DELAY))
	wave.append(p.pulse(0, 1<<TRIG_OUT, TRIG_WIDTH))
	wave.append(p.pulse(1<<TRIG_OUT, 0, LED_DELAY))
	wave.append(p.pulse(0, 1<<LED_OUT, LED_WIDTH))
	wave.append(p.pulse(1<<LED_OUT, 1<<G1, INTERFRAME_DELAY))
	pig.wave_add_generic(wave)
	wave_id = pyconvert(Int, pig.wave_create())

	script = PiGPIOScript(pig, """
	pads 0 16
tag 100

tag 101	r $TRIG_IN	jz 101
tag 102	r $TRIG_IN	jnz 102

	wvtx $wave_id

	mils 35

#	w $G2 1
#	lda $STROBE_IN	call 501	w $G2 0
#	lda $STROBE_IN	call 510	w $G2 1
#	lda $STROBE_IN	call 501	w $G2 0
#	lda $STROBE_IN	call 510	w $G2 1
#	mils 16
#	w $G2 0
	
	jmp 100

# tag 103
# 	wvbsy
# 	jnz 103
# 	jmp 100

	"""
    )
end

function trigger_script(;
	TRIG_IN = 25,
	TRIG_DELAY = 100,
	TRIG_OUT = 5,
	TRIG_WIDTH = 50,
	LED_IN = 22,
	LED_DELAY = 100,
	LED_OUT = 17,	
	LED_WIDTH = 800,
	STROBE_IN = 6,
	INTERFRAME_DELAY = 16
)

	script = """
	tick	sta p8						# track the current tick
	pads 0 16							# drive GPIO 0-27 @ 16 mA
   	# ld v0 p0							# load parameter 0 into v0
   	dcr p0								# predecrement v0 because JP checks >= 0

tag 0
	lda $TRIG_IN
	call 501							# loop until TRIG_IN is HIGH
	call 510							# wait for falling edge on TRIG_IN

   	lda $TRIG_DELAY		call 555		# delay for TRIG_DELAY µs

	w $TRIG_OUT 0
	lda $TRIG_WIDTH		call 555
	w $TRIG_OUT 1

	lda $STROBE_IN
	call 510							# wait for rising edge on STROBE_IN
	call 501							# wait for falling edge on STROBE_IN
	# call 510
	# call 501

	lda $LED_IN
	call 501
	call 510

   	lda $LED_DELAY		call 555		# delay for LED_DELAY µs

	w $LED_OUT 0
	lda $LED_WIDTH		call 555
	w $LED_OUT 1

	lda $STROBE_IN
	# uncomment the next two lines when triggering camera
	call 510						 	# wait for STROBE_IN to go LOW
	call 501							# wait for rising edge on STROBE_IN
	call 510							# wait for falling edge on STROBE_IN

   	# mils $INTERFRAME_DELAY				# must wait (why?) before issuing another manual trigger
	lda $INTERFRAME_DELAY
	mlt 1000
	call 555

	tick	sta p9						# track the current tick
	evt		0
	
   	dcr p0
	jp 0
	ld p0 0
	ret

	# wait for rising edge on pin A
tag 501
	xa v5
tag 5011
	r v5
	jz 5011
	xa v5
	ret

	# wait for falling edge on pin A
tag 510
	xa v5
tag 5101
	r v5
	jnz 5101
	xa v5
	ret

	# wait for A microseconds in small bursts
tag 555
	ld v5 45							# maximum wait time
tag 5551
   	cmp v5
   	jm 5552
   	pusha
   	mics v5
   	popa
   	sub v5
   	jmp 5551
tag 5552
   	sta v5
   	mics v5
	ret

	"""

	return script
end

function trigger(n=1)
	s = storeScript(trigger_script())

	try
		# Ensure the script has finished initializing.
		while scriptIniting(s)
			sleep(0.01)
		end

		runScript(s, n)
		
		while scriptHalted(s)
			sleep(0.01)
		end

        while scriptRunning(s)
			sleep(0.1)
		end

		return scriptStatus(s)
	catch err
		@info "Caught error $err"
	finally
        stopScript(s)
        status = scriptStatus(s)
		tic = status[2][9]
        toc = status[2][10]
		np = status[2][1]
        @info "Parameters at end: " status
        time_s = (toc - tic) / 1e6
        fps = (n-np) / time_s
        @info "Runtime $time_s s ($fps fps)"
		deleteScript(s)
	end
end


end # module CameraControl
