module CameraControl

using Images, ImageShow, Colors

using PythonCall

mutable struct PiGPIOScript
	pig
	index
	pptext
	text

	function PiGPIOScript(pig, text::AbstractString)
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
	PiGPIOScript(pig, ind::Int) = new(pig, ind, "", "")
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
    e = pyconvert(Int, e)
    if e >= 0
        e = ScriptStatus(e)
    end
    return e
end

function params(scr::PiGPIOScript)
    if scr.index < 0
        return nothing
    end
    e, p = scr.pig.script_status(scr.index)
    e = pyconvert(Int, e)
    if e >= 0
        e = ScriptStatus(e)
        p = Int64.(reinterpret(UInt32, Int32.(collect(pyconvert(Tuple, p)))))
    else
        p = nothing
    end
    return p
end

Base.delete!(scr::Int) = Base.delete!(PiGPIOScript(pig[], scr))
Base.run(scr::Int) = Base.run(PiGPIOScript(pig[], scr))

start(scr::Int) = start(PiGPIOScript(pig[], scr))
stop(scr::Int) = stop(PiGPIOScript(pig[], scr))
halt(scr::Int) = halt(PiGPIOScript(pig[], scr))
status(scr::Int) = status(PiGPIOScript(pig[], scr))
params(scr::Int) = params(PiGPIOScript(pig[], scr))

export PiGPIOScript, stop, start, halt, status, params

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
export start_pigpio

function start_pig(host="localhost", port=8888)
    pig = pigpio[].pi(host, port)
    if !pyconvert(Bool, pig.connected)
        error("Couldn't open connection to pigpiod")
    end
	return pig
end
export start_pig

@enum ScriptStatus begin
	INITING = 0
	HALTED = 1
	RUNNING = 2
	WAITING = 3
	FAILED = 4
end
export ScriptStatus
export INITING, HALTED, RUNNING, WAITING, FAILED

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
	WAVE_DURATION = 33400,
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
	pads 0 16							# set pad drivers to 16 mA
	lda 0 sta p0

	lda $TRIG_IN sta p1
	lda $TRIG_TIME sta p2
	lda $LED_TIME sta p3
	lda $LED_WIDTH sta p4

tag 100
	tick sta p5
	w $G1 1
tag 101	mics 1	r $TRIG_IN	jz 101				# wait for TRIG_IN to go high
	tick sub p5 sta p6
tag 102	inr p0	mics 1 r $TRIG_IN	jnz 102		# wait for falling edge on TRIG_IN
	tick sub p5 sta p7
	w $G1 0

	wvtx $wave_id 						# trigger the wave created above

	w $G2 1
# tag 104	mics 1	r $STROBE_IN	jz 104	# wait for STROBE_IN to go high
# tag 105	mics 1	r $STROBE_IN	jnz 105	# wait for STROBE_IN to go low
# tag 106	mics 1	r $STROBE_IN	jz 106	# wait for STROBE_IN to go high
# tag 107	mics 1	r $STROBE_IN	jnz 107	# wait for STROBE_IN to go low
	tick sub p5 sta p8
tag 103	wvbsy	jnz 103 				# wait for wave to finish
	tick sub p5 sta p9
	# wvdel $wave_id 					# release the wave resources
	w $G2 0

	ret
	"""
    )
end

function trigger_loop(pig; n=100, t_min=1200, t_max=1200+8333, kwargs...)
	c = (t_max-t_min) ÷ n
	time = @elapsed for i = 0:n
		s = trigger_wave_script(pig; LED_TIME=t_min+i*c, kwargs...)
		while status(s)==INITING; end
		start(s)
		# while status(s)!=RUNNING;  sleep(0.001); end
		while status(s)==RUNNING; end
		delete!(s)
		pig.wave_clear()
		# finalize(s)
	end
	@info "$(n/time) fps"
end
export trigger_loop



end # module CameraControl
