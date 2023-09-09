using OpenFinch
using PythonCall
using Images, ImageShow, Colors
# using ImageMagick

using JSServe, JSServe.DOM
using JSServe: @js_str, onjs, onload, linkjs
using JSServe: App, Button, Checkbox, Dropdown, Session, Slider, TextField

import JSServe.TailwindDashboard as D

using WGLMakie, GeometryBasics, FileIO
using WGLMakie: volume

using Observables, Markdown

# set_theme!(resolution=(1200, 800))

# hbox(args...) = DOM.div(args...)
# vbox(args...) = DOM.div(args...)

JSServe.browser_display()

##

function make_slider(T::Type{Integer}; max=0, min=0, step=0, default=0, value=0, kw...)
	Slider(min:step:max, value=value)
end

function make_checkbox(;value=0, default=0)
	JSServe.Checkbox(value!=0)
end

img = Observable(Gray.(rand(1600,1200)))

capture_button = Button("capture frame")
continuous_capture = make_checkbox()

OV2311_defaults = Dict(
	"brightness"					=> 0,
	"contrast"						=> 32,
	"saturation"					=> 64,
	"hue"							=> 1,
	"gamma"							=> 72,
	"gain"							=> 54,
	"power_line_frequency"			=> 2,
	"sharpness"						=> 3,
	"backlight_compensation"		=> 0,
	"exposure_auto"					=> 1,
	"exposure_absolute"				=> 1,
	"exposure_auto_priority"		=> 0,
	# "white_balance_temperature" 	=> 4600
)

brightness = make_slider(Integer, min=-64, max=64, step=1, default=0, value=0)
contrast = make_slider(Integer, min=0, max=64, step=1, default=32, value=32)
saturation = make_slider(Integer, min=0, max=128, step=1, default=64, value=64)
hue = make_slider(Integer, min=-40, max=40, step=1, default=0, value=0)
gamma = make_slider(Integer, min=72, max=500, step=1, default=100, value=72)
gain = make_slider(Integer, min=0, max=100, step=1, default=0, value=54)
sharpness = make_slider(Integer, min=0, max=6, step=1, default=3, value=3)
exposure_absolute = make_slider(Integer, min=1, max=5000, step=1, default=157, value=1)

# white_balance_temperature = make_slider(Integer, min=2800, max=6500, step=1, default=4600, value=4600, flags=inactive)
# backlight_compensation = make_slider(Integer, min=0, max=2, step=1, default=1, value=0)

white_balance_temperature_auto = make_checkbox(default=1, value=1)
exposure_auto_priority = make_checkbox(default=0, value=0)

exposure_auto = make_slider(Integer, min=0, max=3, step=1, default=3, value=1)
power_line_frequency = make_slider(Integer, min=0, max=2, step=1, default=2, value=2)

laser1 = make_checkbox(default=0, value=0)
laser2 = make_checkbox(default=0, value=0)
laser3 = make_checkbox(default=0, value=0)

handlers = [
	on(brightness) do val
		dev.controls["brightness"].value = val
	end
	on(contrast) do val
		dev.controls["contrast"].value = val
	end
	on(saturation) do val
		dev.controls["saturation"].value = val
	end
	on(gamma) do val
		dev.controls["gamma"].value = val
	end
	on(gain) do val
		dev.controls["gain"].value = val
	end
	on(exposure_absolute) do val
		dev.controls["exposure_absolute"].value = val
	end
	on(sharpness) do val
		dev.controls["sharpness"].value = val
	end

	on(exposure_auto) do val
		dev.controls["exposure_auto"].value = val
	end
	on(power_line_frequency) do val
		dev.controls["power_line_frequency"].value = val
	end

	on(white_balance_temperature_auto) do val
		dev.controls["white_balance_temperature_auto"].value = val ? 1 : 0
	end

	on(exposure_auto_priority) do val
		dev.controls["exposure_auto_priority"].value = val ? 1 : 0
	end

	on(laser1) do val
		pig.write(17, val ? 0 : 1)
	end
]

cap_handler = on(capture_button) do click
    # img[] = rand(Gray, 1600, 1200)
    img[] = capture_frame(vc)
    @async begin
        yield()
        if continuous_capture[]
            capture_button[] = true
        end
    end
end

##

if true
    rpi = RemotePython("finch.local")
    pygpio = rpi.modules.pigpio
    cv2 = rpi.modules.cv2
    v4l2py = rpi.modules.v4l2py
    Device = v4l2py.Device
    VideoCapture = v4l2py.device.VideoCapture
    BufferType = v4l2py.device.BufferType
    PixelFormat = v4l2py.PixelFormat
else
    rpi = nothing
    pygpio = pyimport("pigpio")
    cv2 = pyimport("cv2")
    v4l2py = pyimport("v4l2py")
    Device = v4l2py.Device
    VideoCapture = v4l2py.device.VideoCapture
    BufferType = v4l2py.device.BufferType
    PixelFormat = v4l2py.PixelFormat
end

import JpegTurbo
function JpegTurbo._jpeg_check_bytes(data::Vector{UInt8})
    length(data) > 623 || throw(ArgumentError("Invalid number of bytes."))
    data[1:2] == [0xff, 0xd8] || throw(ArgumentError("Invalid JPEG byte sequence."))
    # data[end-1:end] == [0xff, 0xd9] || @warn "Premature end of JPEG byte sequence."
    return true
end

function capture_raw(vc)
    it = @py iter(vc)
    frame = @py next(it)
    return pyconvert(Array, frame.array)
end

function capture_frame(vc)
    fmt = vc.get_format()
    width, height = fmt.width, fmt.height
    if pyconvert(Bool, fmt.pixel_format == PixelFormat.MJPEG)
        # img = reverse(Gray.(capture_raw(vc) |> IOBuffer |> load), dims=(1,))
		img = reverse(JpegTurbo.jpeg_decode(Gray, capture_raw(vc)), dims=(1,))
		rotl90(img)
    else
        a = reshape(capture_raw(vc), (2, height, width))
        rotl90(Gray.(a[1, :, :] / 255))
    end
end

##

pig = pygpio.pi()
dev = Device.from_id(0)
dev.open()
vc = VideoCapture(dev)
# vc.set_format(1600, 1200, "YUYV")
vc.set_format(1600, 1200, "MJPG")
vc.open()

##

app = App() do
    ctrls = md"""
| Name | Value | Control |
|:---- |:-------:| -----:|
| sharpness | $(sharpness.value) | $(sharpness)|
| power line frequency | $(power_line_frequency.value) | $(power_line_frequency)|
| brightness | $(brightness.value) | $(brightness)|
| contrast | $(contrast.value) | $(contrast)|
| saturation | $(saturation.value) | $(saturation)|
| gamma | $(gamma.value) | $(gamma)|
| gain | $(gain.value) | $(gain)|
| exposure auto priority | $(exposure_auto_priority.value) | $(exposure_auto_priority)|
| exposure absolute | $(exposure_absolute.value) | $(exposure_absolute)|
| exposure auto | $(exposure_auto.value) | $(exposure_auto)|
"""

    ctrls = D.FlexRow(
		D.FlexCol(
			DOM.div("gamma    				", gamma),
			DOM.div("gain 	  				", gain),
			DOM.div("exposure auto priority ", exposure_auto_priority),
			DOM.div("exposure absolute 		", exposure_absolute),
			DOM.div("exposure auto 			", exposure_auto),
		)
# 		D.FlexCol(
# | sharpness | $(sharpness.value) | $(sharpness)|
# | power line frequency | $(power_line_frequency.value) | $(power_line_frequency)|
# | brightness | $(brightness.value) | $(brightness)|
# | contrast | $(contrast.value) | $(contrast)|
# | saturation | $(saturation.value) | $(saturation)|
# 		)
	)

	plt = D.FlexRow(
		image(img),
		D.FlexCol(
			D.Card(DOM.div("Laser 1 on ", laser1)),
			D.Card(DOM.div("continuous capture  ", continuous_capture)),
			D.Card(capture_button)
		),
	)

	dom = D.FlexCol(
		D.Card(plt),
		D.Card(ctrls),
	)
    return JSServe.DOM.div(JSServe.MarkdownCSS, JSServe.Styling, dom)
end;

display(app)

##
nothing
##

if false

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

	p = Pi(hostname)

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



# julia> dev,info
# driver = uvcvideo
# card = Arducam OV2311 USB Camera: Ardu
# bus = usb-0000:01:00.0-1.3
# version = 5.15.84
# capabilities = DEVICE_CAPS|EXT_PIX_FORMAT|META_CAPTURE|STREAMING|VIDEO_CAPTURE
# device_capabilities = EXT_PIX_FORMAT|STREAMING|VIDEO_CAPTURE
# buffers = VIDEO_CAPTURE
#
# julia> collect(dev.controls.values())
# 14-element Vector{Py}:
#  <Control brightness type=integer min=-64 max=64 step=1 default=0 value=0>
#  <Control contrast type=integer min=0 max=64 step=1 default=32 value=32>
#  <Control saturation type=integer min=0 max=128 step=1 default=64 value=64>
#  <Control hue type=integer min=-40 max=40 step=1 default=0 value=0>
#  <Control white_balance_temperature_auto type=boolean default=1 value=1>
#  <Control gamma type=integer min=72 max=500 step=1 default=100 value=72>
#  <Control gain type=integer min=0 max=100 step=1 default=0 value=54>
#  <Control power_line_frequency type=menu min=0 max=2 step=1 default=2 value=2>
#  <Control white_balance_temperature type=integer min=2800 max=6500 step=1 default=4600 value=4600 flags=inactive>
#  <Control sharpness type=integer min=0 max=6 step=1 default=3 value=3>
#  <Control backlight_compensation type=integer min=0 max=2 step=1 default=1 value=0>
#  <Control exposure_auto type=menu min=0 max=3 step=1 default=3 value=1>
#  <Control exposure_absolute type=integer min=1 max=5000 step=1 default=157 value=1>
#  <Control exposure_auto_priority type=boolean default=0 value=0>

# capture_frame(dev)

##

# cap = cv2.VideoCapture(1)
# cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1600)
# cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 1200)
# cap.set(cv2.CAP_PROP_FOURCC, reinterpret(UInt32, b"YUYV")[1])
# cap.set(cv2.CAP_PROP_CONVERT_RGB, 0)

##

# ret, fcap = cap.read(); img = pyconvert(Array, fcap); Gray.(img[end:-1:1,:,1]/255)

##

# bytes = pyconvert(Array{UInt8}, frame.array)
# words = reinterpret(UInt16, bytes)

# a = reshape(words, (1600, 1200))

##

# cam = Device.from_id(1)

# cam.open()

# cam.info.card

# cam.info.capabilities

# cam.info.formats

# cam.get_format(BufferType.VIDEO_CAPTURE)

# ctrls = collect(cam.controls.values())

# cam.close()

##

# pywith(Device.from_id(1)) do cam
#     for (i, frame) in @py enumerate(cam)
#         println("frame #$i: $(len(frame)) bytes")
#         if i > 9
#             break
# 		end
# 	end
# end

##

# capture = VideoCapture(device)

# capture.set_format(1600, 1200, "YUYV 4:2:2")

##


##

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
