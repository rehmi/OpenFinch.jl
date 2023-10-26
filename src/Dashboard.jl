module Dashboard

using OpenFinch
using PythonCall
using Images, ImageShow, Colors
using JSServe, JSServe.DOM
using JSServe: @js_str, onjs, onload, linkjs
using JSServe: App, Button, Checkbox, Dropdown, Session, Slider, TextField
import JSServe.TailwindDashboard as D
using WGLMakie, GeometryBasics, FileIO
using WGLMakie: volume
using Observables, Markdown

# set_theme!(resolution=(1200, 800))

hbox(args...) = DOM.div(args...)
vbox(args...) = DOM.div(args...)

abstract type CameraControl end

struct SliderControl <: CameraControl
    label
    values
    value
	widget

	function SliderControl(label, values, default)
		new(label, values, default, Slider(values, value=default))
	end
end

struct CheckboxControl <: CameraControl
    label
    value::Bool
	widget

	function CheckboxControl(label, default)
		new(label, default, Checkbox(default))
	end
end

# function make_control(control::SliderControl)
#     Slider(control.values, value=control.value)
# end

# function make_control(control::CheckboxControl)
#     Checkbox(control.value)
# end

##

# this prevents the package from precompiling

# import JpegTurbo
# function JpegTurbo._jpeg_check_bytes(data::Vector{UInt8})
# 	length(data) > 623 || throw(ArgumentError("Invalid number of bytes."))
# 	data[1:2] == [0xff, 0xd8] || throw(ArgumentError("Invalid JPEG byte sequence."))
# 	# data[end-1:end] == [0xff, 0xd9] || @warn "Premature end of JPEG byte sequence."
# 	return true
# end

##

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

global camera_device, pygpio, cv2, v4l2py, vidcap

function start_connection(host="finch.local")
    if true
        rpi = RemotePython(host)
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


    pig = pygpio.pi()
    dev = Device.from_id(0)
    dev.open()
    vc = VideoCapture(dev)
    # vc.set_format(1600, 1200, "YUYV")
    vc.set_format(1600, 1200, "MJPG")
    vc.open()

	global camera_device = dev
	global pygpio = pygpio
	global cv2 = cv2
	global v4l2py = v4l2py
	global vidcap = vc
end

function stop_connection()
	vidcap.close()
	camera_device.close()
end

function display_dashboard()
    JSServe.browser_display()

    camera_controls = Dict(
		"brightness" => SliderControl("brightness", -64:1:64, 0),
		"contrast" => SliderControl("contrast", 0:1:64, 32),
		"saturation" => SliderControl("saturation", 0:1:128, 64),
		"hue" => SliderControl("hue", -40:1:40, 0),
		"gamma" => SliderControl("gamma", 72:1:500, 72),
		"gain" => SliderControl("gain", 0:1:100, 54),
		"sharpness" => SliderControl("sharpness", 0:1:6, 3),
		"exposure_absolute" => SliderControl("exposure_absolute", 1:1:5000, 1),
		"exposure_auto" => SliderControl("exposure_auto", 0:1:3, 1),
		"power_line_frequency" => SliderControl("power_line_frequency", 0:1:2, 2),
	)

    function on_control_update(control, dev, control_name)
        on(control) do val
			@info "on_control_update($control_name, $val)"
            # dev.controls[control_name].value = val
        end
    end

    img = Observable(Gray.(rand(1600, 1200)))
    capture_button = Button("capture frame")
    continuous_capture = CheckboxControl("continuous_capture", false)
    exposure_auto_priority = CheckboxControl("exposure_auto_priority", false)
    laser1 = CheckboxControl("laser1", false)

    cap_handler = on(capture_button) do click
        img[] = capture_frame(vidcap)
        @async begin
            yield()
            if continuous_capture[]
                capture_button[] = true
            end
        end
    end

    camera_control_handlers = [
		on_control_update(control.widget, camera_device, name)
			for (name, control) in camera_controls
	]

    app = App() do

        ctrls = D.FlexRow(
            D.FlexCol(
                DOM.div("gamma    				", camera_controls["gamma"].widget),
                DOM.div("gain 	  				", camera_controls["gain"].widget),
                DOM.div("exposure auto priority ", exposure_auto_priority.widget),
                DOM.div("exposure absolute 		", camera_controls["exposure_absolute"].widget),
                DOM.div("exposure auto 			", camera_controls["exposure_auto"].widget),
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
                D.Card(DOM.div("Laser 1 on ", laser1.widget)),
                D.Card(DOM.div("continuous capture  ", continuous_capture.widget)),
                D.Card(capture_button)
            ),
        )

        dom = D.FlexCol(
            D.Card(plt),
            D.Card(ctrls),
        )
        return JSServe.DOM.div(JSServe.MarkdownCSS, JSServe.Styling, dom)
    end

    display(app)
end

export display_dashboard, start_connection, stop_connection

end # module