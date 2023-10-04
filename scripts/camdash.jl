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
