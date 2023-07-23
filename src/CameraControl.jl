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

function waitNotHalted(s)
   for check ∈ 1:10
      sleep(0.1)
      e, p = pig[].script_status(s)
      if Bool(e != pigpio[].PI_SCRIPT_HALTED)
         return
	  end
	end
end

function testScript(n = 1)
	# @info("Script store/run/status/stop/delete tests.")
	
    script = """
     	ld v0 p0
		dcr v0
		w 26 1

	tag 0
		r p1
     	jz 0

		w 26 0

	tag 1
     	r p1
     	jnz 1

		w 26 1

		mics p2

		w 26 0

     	w p3 0
     	mics p4
     	w p3 1

		w 26 1

	tag 2
     	r p9
     	jz 2

		w 26 0

	tag 3
     	r p5
     	jz 3
		
		w 26 1

	tag 4
     	r p5
     	jnz 4
		
		w 26 0

     	mics p6

		w 26 1

     	w p7 0
     	mics p8
     	w p7 1

		w 26 0

	tag 5
     	r p9
     	jnz 5

		w 26 1

	tag 6
     	r p9
     	jz 6
		
		w 26 0

	tag 7
     	r p9
     	jnz 7

		w 26 1

		mils 175

		dcr v0
     	jp 0
	"""
	
	N_EXPOSURES = n
	TRIG_IN = 20 			# p1
	TRIG_DELAY = 100		# p2
	TRIG_OUT = 5 			# p3
	TRIG_WIDTH = 100 		# p4
	LED_IN = 16 			# p5
	LED_DELAY = 200 		# p6
	LED_OUT = 21 			# p7
	LED_WIDTH = 500 		# p8
	STROBE_IN = 6 			# p9

	# cb = pig[].callback(TRIG_OUT)
	old_exceptions = pigpio[].exceptions
	pigpio[].exceptions = pybool(false)
	s = pig[].store_script(script)
	@info "Stored script $s"

	try
		# Ensure the script has finished initing.
		while true
			e, p = pig[].script_status(s)
			if Bool(e != pigpio[].PI_SCRIPT_INITING)
				break
			end
			sleep(0.1)
		end

		# oc = cb.tally()

		pig[].run_script(s,	[N_EXPOSURES, 
			TRIG_IN, TRIG_DELAY, TRIG_OUT, TRIG_WIDTH,
			LED_IN, LED_DELAY, LED_OUT, LED_WIDTH,
			STROBE_IN])

		waitNotHalted(s)

		while true
			e, p = pig[].script_status(s)
			if Bool(e != pigpio[].PI_SCRIPT_RUNNING)
				break
			end
			sleep(0.1)
		end
	
		sleep(0.2)
		# c = cb.tally() - oc
		# @info c

# 	CHECK(9, 1, c, 100, 0, "store/run script")

#    	oc = cb.tally()
#    	pig[].run_script(s, [200, GPIO])

#    t9waitNotHalted(s)

#    while True:
#       e, p = pig[].script_status(s)
#       if e != pigpio.PI_SCRIPT_RUNNING:
#          break
#       time.sleep(0.1)
#    time.sleep(0.2)
#    c = cb.tally() - oc
#    CHECK(9, 2, c, 201, 0, "run script/script status")

#    oc = cb.tally()
#    pig[].run_script(s, [2000, GPIO])

#    t9waitNotHalted(s)

#    while True:
#       e, p = pig[].script_status(s)
#       if e != pigpio.PI_SCRIPT_RUNNING:
#          break
#       if p[9] < 1900:
#          pig[].stop_script(s)
#       time.sleep(0.1)
#    time.sleep(0.2)
#    c = cb.tally() - oc
#    CHECK(9, 3, c, 110, 20, "run/stop script/script status")

#    e = pig[].delete_script(s)
#    CHECK(9, 4, e, 0, 0, "delete script")
	catch err
		@info "Caught error $err"
	finally
		# @info "Cancelling callback"
   		# cb.cancel()
		@info "Stopping script $s"
		pig[].stop_script(s)
		@info "Deleting script $s"
		pig[].delete_script(s)
		pigpio[].exceptions = old_exceptions
	end
end

if false
	rpyc		= pyimport("rpyc")
	plumbum		= pyimport("plumbum")
	zerodeploy	= pyimport("rpyc.utils.zerodeploy")

	# mach 		= plumbum.SshMachine("cyl0n.ddns.net", user="rehmi")
	# mach.python.executable = "/usr/local/bin/python3"

	mach	 	= plumbum.SshMachine("finch.local", user="rehmi")
	server		= zerodeploy.DeployedServer(mach)
	rpi			= server.classic_connect()

	rpi.modules.os.getpid()
	rpi.modules.sys.version

	##

	v4l2py 		= rpi.modules.v4l2py
	Device 		= v4l2py.Device
	VideoCapture= v4l2py.device.VideoCapture
	BufferType 	= v4l2py.device.BufferType

	dev = Device.from_id(0)
	dev.open()
	vc = VideoCapture(dev)
	vc.open()
	it = @py iter(vc)
	frame = @py next(it)
	vc.close()
	dev.close()

	##

	bytes = pyconvert(Array{UInt8}, frame.array)
	words = reinterpret(UInt16, bytes)

	a = reshape(words, (1600, 1200))

	##


	cam.info.card

	cam.info.capabilities

	cam.info.formats

	cam.get_format(BufferType.VIDEO_CAPTURE)

	ctrls = collect(cam.controls.values())

	cam.close()

	##

	pywith(Device.from_id(1)) do cam
		for (i, frame) in @py enumerate(cam)
			println("frame #$i: $(len(frame)) bytes")
			if i > 9
				break
			end
		end
	end

	##


	capture = VideoCapture(device)

	capture.set_format(1600, 1200, "YUYV 4:2:2")

	# async def loop(variable):
	#     while True:
	#         await asyncio.sleep(0.1)
	#         variable[0] += 1


	# async def main():
	#     fmt = "%(threadName)-10s %(asctime)-15s %(levelname)-5s %(name)s: %(message)s"
	#     logging.basicConfig(level="INFO", format=fmt)

	#     data = [0]
	#     asyncio.create_task(loop(data))

	#     with Device.from_id(0) as device:
	#         capture = VideoCapture(device)
	#         capture.set_format(640, 480, "MJPG")
	#         with capture as stream:
	#             start = last = time.monotonic()
	#             last_update = 0
	#             async for frame in stream:
	#                 new = time.monotonic()
	#                 fps, last = 1 / (new - last), new
	#                 if new - last_update > 0.1:
	#                     elapsed = new - start
	#                     print(
	#                         f"frame {frame.frame_nb:04d} {len(frame)/1000:.1f} Kb at {fps:.1f} fps ; "
	#                         f" data={data[0]}; {elapsed=:.2f} s;",
	#                         end="\r",
	#                     )
	#                     last_update = new


	# try:
	#     asyncio.run(main())
	# except KeyboardInterrupt:
	#     logging.info("Ctrl-C pressed. Bailing out")

	##
	nothing
	##

	cv2 = rpi.modules.cv2
	cap = cv2.VideoCapture(1)

	ret, frame = cap.read()

	frame

	##

	##
	nothing
	##

cv2test = """
import cv2

FRAME_WIDTH=3
FRAME_HEIGHT=4
FRAME_RATE=5
BRIGHTNESS=10
CONTRAST=11
SATURATION=12
HUE=13
GAIN=14
EXPOSURE=15


#Opens the first imaging device
cap = cv2.VideoCapture(0) 

#Check whether user selected camera is opened successfully.
if not (cap.isOpened()):
 print("Could not open video device")

#To set the resolution
cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc('M', 'J', 'P', 'G'))
#cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc('U', 'Y', 'V', 'Y'))

cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)

print("Width = ",cap.get(cv2.CAP_PROP_FRAME_WIDTH))
print("Height = ",cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
print("Framerate = ",cap.get(cv2.CAP_PROP_FPS))
print("Format = ",cap.get(cv2.CAP_PROP_FORMAT))

Brightness=cap.get(cv2.CAP_PROP_BRIGHTNESS)
Contrast=cap.get(cv2.CAP_PROP_CONTRAST)
Saturation=cap.get(cv2.CAP_PROP_SATURATION)
Gain=cap.get(cv2.CAP_PROP_GAIN)
Hue=cap.get(cv2.CAP_PROP_HUE)
Exposure=cap.get(cv2.CAP_PROP_EXPOSURE)
while(True):
    # Capture frame-by-frame
    ret, frame = cap.read()

    # Display the resulting frame
    cv2.imshow('preview',frame)
#Waits for a user input to quit the application
    k = cv2.waitKey(1)
    if (k == 27):#Esc key to quite the application 
        break
    elif k == ord('g'):
        print("******************************")
        print("Width = ",cap.get(FRAME_WIDTH))
        print("Height = ",cap.get(FRAME_HEIGHT))
        print("Framerate = ",cap.get(FRAME_RATE))
        print("Brightness = ",cap.get(BRIGHTNESS))
        print("Contrast = ",cap.get(CONTRAST))
        print("Saturation = ",cap.get(SATURATION))
        print("Gain = ",cap.get(GAIN))
        print("Hue = ",cap.get(HUE))
        print("Exposure = ",cap.get(EXPOSURE))
        print("******************************")  

    elif k == ord('w'):
        if(Brightness <= 0):
            Brightness = 0
        else:
            Brightness-=1
        cap.set(BRIGHTNESS,Brightness)
        print(Brightness)
    elif k == ord('s'):
        if(Brightness >= 255):
            Brightness = 255
        else:
            Brightness+=1
        cap.set(BRIGHTNESS,Brightness)
        print(Brightness)   

# When everything done, release the capture
cap.release()
cv2.destroyAllWindows() 
"""

	##



	Picamera2 = rpi.modules.picamera2.Picamera2
	Preview = rpi.modules.picamera2.Preview

	picam2 = Picamera2(0)

	##

	# Capture a full resolution image to memory rather than to a file.

	# picam2 = Picamera2()

	picam2.start_preview(Preview.QTGL)
	preview_config = picam2.create_preview_configuration()
	capture_config = picam2.create_still_configuration()

	picam2.configure(preview_config)
	picam2.start()

	sleep(2)

	image = picam2.switch_mode_and_capture_image(capture_config)
	# image.show()

	sleep(5)

	picam2.close()

	##

	pc.resolution = (1024,768)

	pc.start_preview()

	pc.stop_preview()


	##

	using PiGPIO

	free_pin = 17

	p = Pi("finch.local")

	set_mode(p, free_pin, PiGPIO.OUTPUT)

	try
		for i in 1:1000
			PiGPIO.write(p, free_pin, PiGPIO.HIGH)
			sleep(0.005)
			PiGPIO.write(p, free_pin, PiGPIO.LOW)
			sleep(0.005)
		end
	finally
		println("Cleaning up!")
		set_mode(p, free_pin, PiGPIO.INPUT)
	end

	##
		
	using OV2311

	RED_OUT = 21
	GRN_OUT = 26
	# BLU_OUT =

	TRIG_OUT = 19
	STROBE_IN = 20

	RED_IN = 12
	GRN_IN = 13
	BLU_IN = 16


	TRIG_PULSE_WIDTH = 50 # µs

	##

	function cam_trigger()
		pigs("trig $TRIG_OUT $TRIG_PULSE_WIDTH 1")
	end

	# # initialize GPIO pin modes
	# set_mode(pi, RED_OUT, PiGPIO.OUTPUT)
	# set_mode(pi, GRN_OUT, PiGPIO.OUTPUT)
	# # set_mode(pi, BLU_OUT, PiGPIO.OUTPUT)
	# set_mode(pi, RED_IN, PiGPIO.INPUT)
	# set_mode(pi, GRN_IN, PiGPIO.INPUT)
	# set_mode(pi, BLU_IN, PiGPIO.INPUT)

	# set_mode(pi, TRIG_OUT, PiGPIO.OUTPUT)
	# set_mode(pi, STROBE_IN, PiGPIO.INPUT)

	function cam_delayed_trigger(delay=3000)
		input_pin = GRN_IN
		trig_pin = TRIG_OUT
		trig_pulse_width = TRIG_PULSE_WIDTH
	end

	##

	script = pigs("proc tag 999 w $GRN_OUT 1 w $GRN_OUT 0 dcr p0 jp 199")

	result = pigs("procr $script 1000000")

	##

	##

	PERIOD = 8.33e-3

	for i ∈ 1:10000
		# not-so-great way to wait for a falling edge
		while !gpio_read(BLU_IN) yield(); end
		# while !gpio_read(GRN_IN) yield(); end
		# yield()
		while gpio_read(GRN_IN) yield(); end

		t0 = time_ns()				# mark the time

		t1 = t0 +    50_000			# 50 µs shutter pulse
		t2 = t0 + 3_000_000			# 3000 µs delay to laser pulse
		t3 = t2 +   300_000 		# 500 µs laser pulse
		
		gpio_set(TRIG_OUT)			# trigger camera shutter
		yield(); yield(); yield(); yield();
		while time_ns() < t1 yield(); end	# wait to end trigger pulse
		gpio_clear(TRIG_OUT)		# turn off trigger
		# yield()
		while time_ns() < t2 yield(); end	# wait to fire laser
		gpio_clear(RED_OUT)			# turn on laser
		while time_ns() < t3 yield(); end	# wait to turn off laser
		gpio_set(RED_OUT)			# turn off laser

		sleep(0.003)
	end

	##

	flash_RED=[] # flash every 500 ms
	flash_GRN=[] # flash every 100 ms

	#                              ON     OFF  DELAY

	push!(flash_RED, PiGPIO.Pulse(1<<RED_OUT, 0, 500000))
	push!(flash_RED, PiGPIO.Pulse(0, 1<<RED_OUT, 500000))

	push!(flash_GRN, PiGPIO.Pulse(1<<GRN_OUT, 0, 100000))
	push!(flash_GRN, PiGPIO.Pulse(0, 1<<GRN_OUT, 100000))

	PiGPIO.wave_clear(pi) # clear any existing waveforms

	PiGPIO.wave_add_generic(pi, flash_RED) # 500 ms flashes
	fRED = PiGPIO.wave_create(pi) # create and save id

	PiGPIO.wave_add_generic(pi, flash_GRN) # 100 ms flashes
	fGRN = PiGPIO.wave_create(pi) # create and save id

	PiGPIO.wave_send_repeat(pi, fRED)

	sleep(4)

	PiGPIO.wave_send_repeat(pi, fGRN)

	time.sleep(4)

	PiGPIO.wave_send_repeat(pi, fRED)

	time.sleep(4)

	PiGPIO.wave_tx_stop(pi, ) # stop waveform

	PiGPIO.wave_clear(pi, ) # clear all waveforms


	##

	# Hello Dash from https://github.com/plotly/Dash.jl/issues/50#issue-674077393
	using Dash
	using PlotlyJS

	#      Status `~/.julia/environments/v1.7/Project.toml`
	#  [1b08a953] Dash v1.1.2

	function powplot(n)
		x = 0:0.01:1
		y = x .^ n
		p = plot(x, y, mode="lines")
		p.plot
	end

	app =
		dash(external_stylesheets=["https://codepen.io/chriddyp/pen/bWLwgP.css"])

	app.layout = html_div(style=Dict(:width => "50%")) do
		html_h1("Hello Dash"),
		html_div() do
			html_div("slider", style=(width="10%", display="inline-block")),
			html_div(dcc_slider(
					id="slider",
					min=0,
					max=9,
					marks=Dict(i => "$i" for i = 0:9),
					value=1,
				), style=(width="70%", display="inline-block"))
		end,
		html_br(),
		dcc_graph(id="power", figure=powplot(1))
	end

	callback!(app, Output("power", "figure"), Input("slider", "value")) do value
		powplot(value)
	end

	run_server(app)

	##

end # if false

end # module CamControl