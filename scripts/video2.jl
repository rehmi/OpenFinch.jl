using ImageCore

function create_buffer(w, h)
    w2 = 64ceil(Int, w/64) # dimension adjustments to hardware restrictions
    h2 = 32ceil(Int, h/32)
    nb = Int(w2*h2*3//2) # total number of bytes per frame
    return (w2, h2, Vector{UInt8}(undef, nb))
end

struct Camera
    o::Base.Process
    buff::Vector{UInt8}
    img # a reshaped view into the bytes buffer 
    function Camera(w, h, fps)
        w2, h2, buff = create_buffer(w, h)
        b = view(buff, 1:w2*h2)
        Y = reshape(b, w2, h2)
        img = colorview(Gray, normedview(view(Y, 1:w, 1:h)))
        cmd = `libcamera-vid -n --framerate $fps --width $w --height $h -t 0 --codec yuv420 -o -` # I imagine that there might be a number of arguments improving things here, or tailoring it to what the user needs/wants
        o = open(cmd) # to "close" the camera just `kill(c.o)`
        new(o, buff, img)
    end
end

function read_frame(c::Camera)
    read!(c.o, c.buff) # not sure if `readbytes!` might be better here...
    return c.img
end

##
;
##



ENV["DISPLAY"] = ":0"
ENV["JULIA_PYTHONCALL_EXE"]="@PyCall"

using PythonCall

time = pyimport("time")
picamera2 = pyimport("picamera2")
Picamera2 = picamera2.Picamera2
Preview = picamera2.Preview

picam2 = Picamera2()
camera_config = picam2.create_preview_configuration()
picam2.configure(camera_config)
picam2.start_preview(Preview.QT)
picam2.start()
time.sleep(10)
picam2.capture_file("test.jpg")

##

ENV["DISPLAY"] = ":0"
ENV["JULIA_PYTHONCALL_EXE"] = "@PyCall"

using PythonCall
# using PyCall

time = pyimport("time")
picamera2 = pyimport("picamera2")
Picamera2 = picamera2.Picamera2
Preview = picamera2.Preview

picam2 = Picamera2()
picam2.start_preview(Preview.QTGL)

# PythonCall
preview_config = @pyeval (picam2=picam2) => `picam2.create_preview_configuration(raw={"size": picam2.sensor_resolution})`

# PyCall
# preview_config = py"$picam2.create_preview_configuration(raw={'size': $picam2.sensor_resolution})"

println(preview_config)
picam2.configure(preview_config)

picam2.start()
time.sleep(2)

raw = picam2.capture_array("raw")
println(raw.shape)
println(picam2.stream_configuration("raw"))

##

ENV["DISPLAY"] = ":0"
using VideoIO, Images, ImageShow, BenchmarkTools

opts = VideoIO.DEFAULT_CAMERA_OPTIONS
opts["framerate]"] = "158"
opts["video_size"] = "640x480"
opts["pixel_format"] = "gray8"

cam = opencamera(VideoIO.DEFAULT_CAMERA_DEVICE[], VideoIO.DEFAULT_CAMERA_FORMAT[], opts)
