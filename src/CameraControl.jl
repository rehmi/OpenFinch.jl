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
			try
				stop(o)
				delete!(o)
			catch
			end
		end
		finalizer(f, new(pig, index, pptext, text))
	end
end

function Base.show(io::IO, ::MIME"text/plain", scr::PiGPIOScript)
	print(io, "PiGPIOScript($(scr.pig), index=$(scr.index), status=$(status(scr)))")
end

function Base.delete!(scr::PiGPIOScript)
	try
		scr.pig.delete_script(scr.index)
	catch
	end
	scr.index = -1
end

function start(scr::PiGPIOScript, args...)
    scr.pig.run_script(scr.index, collect(args))
end

function stop(scr::PiGPIOScript)
	try
		scr.pig.stop_script(scr.index)
	catch
	end
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
	e = pyconvert(Int, e)
	if e >= 0
		e = ScriptStatus(e)
		p = Int64.(reinterpret(UInt32, Int32.(collect(pyconvert(Tuple, p)))))
	else
		p = nothing
	end
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
	TRIG_TIME = 0,
	TRIG_OUT = 5,
	TRIG_WIDTH = 50,
	LED_IN = 22,
	LED_TIME = 5555,
	LED_OUT = 17,	
	LED_WIDTH = 250,
	STROBE_IN = 6,
	WAVE_DURATION = 16_667,
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

	dtled = max(0, LED_TIME - TRIG_WIDTH - TRIG_TIME)
	dtif = max(0, WAVE_DURATION - LED_TIME - LED_WIDTH - TRIG_TIME - TRIG_WIDTH)

	wave = @py []
	wave.append(p.pulse(0, 0, TRIG_TIME))
	wave.append(p.pulse(0, 1<<TRIG_OUT, TRIG_WIDTH))
	wave.append(p.pulse(1<<TRIG_OUT, 0, dtled))
	wave.append(p.pulse(0, 1<<LED_OUT, LED_WIDTH))
	wave.append(p.pulse(1<<LED_OUT, 0, dtif))
	pig.wave_add_generic(wave)
	wave_id = pyconvert(Int, pig.wave_create())

	script = PiGPIOScript(pig, """
	pads 0 16					# set pad drivers to 16 mA
tag 100
	w $G1 1
tag 101	r $TRIG_IN	jz 101		# wait for TRIG_IN to go high
tag 102	r $TRIG_IN	jnz 102		# wait for falling edge on TRIG_IN
	w $G1 0
	wvtx $wave_id 				# trigger the wave created above
	w $G2 1
tag 103	wvbsy	jnz 103 		# wait for wave to finish
	w $G2 0
	# wvdel $wave_id 				# release the wave resources
	ret
	"""
    )
end

function trigger_loop(pig; n=100, t_min=1200, t_max=1200+8333, kwargs...)
	c = Int(floor((t_max-t_min)/n))
	time = @elapsed for i = 0:n
		s = CameraControl.trigger_wave_script(pig; LED_TIME=t_min+i*c, kwargs...)
		while status(s)[1]==CameraControl.INITING; sleep(0.01); end
		start(s)
		while status(s)[1]==CameraControl.HALTED;  sleep(0.01); end
		while status(s)[1]==CameraControl.RUNNING; sleep(0.01); end
		delete!(s)
		pig.wave_clear()
		# finalize(s)
	end
	@info "$(n/time) fps"
end
export trigger_loop

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
