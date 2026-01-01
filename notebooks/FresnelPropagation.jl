
using PlutoUI
using PlutoTeachingTools
using DSP, FFTW, Plots, Images, TestImages
using QuartzImageIO
using Colors
using Statistics
using LazyGrids
import StatsBase
import PlotlyJS
import Unitful
# using Unitful: nm, µm, mm, cm, m
# using Unitful: upreferred, ustrip, @u_str
using DynamicQuantities
const U = DynamicQuantities.Units
const C = DynamicQuantities.Constants
using BenchmarkTools
using HypertextLiteral
using FourierTools
using ProgressLogging
using HTTP
using HTTP.WebSockets
using JSON
using Base64
using FileIO
using ImageIO
using JpegTurbo
using ImageShow
using MosaicViews
using Random
using VideoIO

using FourierTools: resample  # override DSP.resample
using DSP: conv

using LinearAlgebra: BLAS

using TimerOutputs

THREADS = Threads.nthreads()
FFTW.set_num_threads(THREADS)
BLAS.set_num_threads(THREADS)

# Not sure why this is necessary, but it mitigates type errors
# that occur when a {Complex} type reaches plan_fft()
FFTW.fft(x::Matrix{Complex}) = fft(ComplexF32.(x))
# FourierTools.resample(m::Matrix{Complex}, args...) = resample(ComplexF32.(m), args...)

# setup TimerOutput for benchmarking
to = TimerOutput()

meshgrid(y, x) = (ndgrid(x, y)[[2, 1]]...,)

# XXX there's probably a better way to get rid of the "Premature end..." warning message
# import JpegTurbo
function JpegTurbo._jpeg_check_bytes(data::Vector{UInt8})
	length(data) > 623 || throw(ArgumentError("Invalid number of bytes."))
	data[1:2] == [0xff, 0xd8] || throw(ArgumentError("Invalid JPEG byte sequence."))
	# data[end-1:end] == [0xff, 0xd9] || @warn "Premature end of JPEG byte sequence."
	return true
end


# ENV["AF_JIT_KERNEL_TRACE"] = joinpath(homedir(), "fardel", "tmp")
# ENV["AF_JIT_KERNEL_TRACE"] = "stdout"
ENV["AF_PRINT_ERRORS"] = "1"
# ENV["AF_DISABLE_GRAPHICS"] = "1"
# ENV["AF_MEM_DEBUG"] = "1"
# ENV["AF_TRACE"] = "jit,platform"
# all: All trace outputs
# jit: Logs kernel fetch & respective compile options and any errors.
# mem: Memory management allocation, free and garbage collection information
# platform: Device management information
# unified: Unified backend dynamic loading information
# ENV["AF_CUDA_MAX_JIT_LEN"] = "100"
# ENV["AF_OPENCL_MAX_JIT_LEN"] = "50"
# ENV["AF_SYNCHRONOUS_CALLS"] = "0"

using Libdl
# ((x,y)->x∈y||push!(y,x))("/opt/arrayfire/lib", Libdl.DL_LOAD_PATH)
((x,y)->x∈y||push!(y,x))("/opt/homebrew/lib", Libdl.DL_LOAD_PATH)

using ArrayFire
# ArrayFire.set_backend(UInt32(0))
using ArrayFire: dim_t, af_lib, af_array, af_conv_mode, af_border_type
using ArrayFire: _error, RefValue, af_type

# does the GPU support double floats?
if ArrayFire.get_dbl_support(0)
	WOFloat = Float32
	WOArray = AFArray
else
	WOFloat = Float32
	WOArray = AFArray
end

function afstat()
	alloc_bytes, alloc_buffers, lock_bytes, lock_buffers =  device_mem_info()
	println("alloc: $(alloc_bytes÷(1024*1024))M, $alloc_buffers bufs; locked: $(lock_bytes÷(1024*1024))M, $lock_buffers bufs")
end

function af_pad(A::AFArray{T,N}, bdims::Vector{dim_t}, edims::Vector{dim_t},
				type::af_border_type=AF_PAD_ZERO) where {T,N}
	out = RefValue{af_array}(0)
	_error(@ccall af_lib.af_pad(out::Ptr{af_array},
								A.arr::af_array,
								length(bdims)::UInt32,
								bdims::Ptr{Vector{dim_t}},
								length(edims)::UInt32,
								edims::Ptr{Vector{dim_t}},
								type::af_border_type
	)::af_err)
	n = max(N, length(bdims), length(edims))	# XXX might not be strictly correct
	return AFArray{T, n}(out[])
end

af_pad(A::AFArray{T, N}, bdims::Tuple, edims::Tuple, type::af_border_type=AF_PAD_ZERO) where {T, N} = af_pad(A, [bdims...], [edims...], type)

function af_conv(signal::AFArray{Ts,N}, filter::AFArray{Tf,N}; expand=false, inplace=true)::AFArray where {Ts<:Union{Complex,Real}, Tf<:Union{Complex,Real}, N}
	cT = AFArray{ComplexF32}
	S = cT(signal)
	F = cT(filter)
	sdims = size(S)
	fdims = size(F)
	odims = sdims .+ fdims .- 1
	pdims = nextpow.(2, odims)

	# pad beginning of signal by 1/2 width of filter
	# line up beginning of signal with center of filter in padded arrays
	Sbpad = fdims .÷ 2
	# pad end of signal by (nextpow2 size) - (size of (pad + signal))
	Sepad = pdims .- (Sbpad .+ sdims)

	# don't pad beginning of filter
	Fbpad = fdims .* 0
	# pad end of filter to nextpow2 size
	Fepad = pdims .- fdims

	if expand == true
		from = fdims .* 0 .+ 1
		to = odims
	elseif expand == :padded
		from = fdims .* 0 .+ 1
		to = pdims
	elseif expand==false
		from = fdims.÷2 .+ 1
		to = from .+ sdims .- 1
	else
		error("Cannot interpret value for keyword expand: $expand")
	end
	index  = tuple([a:b for (a,b) in zip(from, to)]...)

	pS = af_pad(S, Sbpad, Sepad, AF_PAD_ZERO)
	pF = af_pad(F, Fbpad, Fepad, AF_PAD_ZERO)
	shifts = -[(fdims.÷2)... [0 for i ∈ length(fdims):3]...]
	pF = ArrayFire.shift(pF, shifts...)

	# @info "data:" size(S) size(F)
	# @info "padded data:" size(pS) size(pF)
	# @info "fc2() calculations:" cT sdims fdims odims pdims index
	# @info "index calculation" expand from to index

	if inplace
		fft!(pS)
		fft!(pF)
		pS = pS .* pF
		ifft!(pS)
		SF = pS
	else
		fS = fft(pS)
		fF = fft(pF)
		fSF = fS .* fF
		SF = ifft(fSF)
	end

	if eltype(signal) <: Real && eltype(filter) <: Real
		out = allowslow(AFArray) do; real.(SF[index...]); end
	else
		out = allowslow(AFArray) do; (SF[index...]); end
	end

	return out
end

allowslow(AFArray, false)

# Accelerated CGH by incoherent photon sampling
@bind threshold Slider(-1.0:0.01:1.0, default=0, show_value=true)

W_λR   = @bind λR Slider(600:1:700, default=638, show_value=true);
W_λG   = @bind λG Slider(500:1:600, default=527, show_value=true);
W_λB   = @bind λB Slider(400:1:500, default=477, show_value=true);

W_rg   = @bind red_gain Slider(0.0:0.1:4.0, default=1, show_value=true)
W_bg   = @bind blue_gain Slider(0.0:0.1:4.0, default=1.5, show_value=true)
W_ag   = @bind analog_gain Slider(1.0:0.1:100.0, default=2, show_value=true)

W_LW   = @bind LED_WIDTH Slider(0:1:2560, default=1280, show_value=true)
W_LT   = @bind LED_TIME Slider(0:1:8333, default=0, show_value=true)

W_brt  = @bind brightness Slider(-1:0.1:1, default=0, show_value=true)
W_con  = @bind contrast Slider(0:0.1:32, default=1, show_value=true)
W_sat  = @bind saturation Slider(0:0.1:32, default=1, show_value=true)
W_nrm  = @bind nrmode Slider(0:1:4, default=0, show_value=true)
W_shp  = @bind sharpness Slider(0:0.1:16, default=1, show_value=true)

W_f    = @bind f Slider(0:10:2500, default=1200, show_value=true)
W_df   = @bind df Slider(-5:0.1:5, default=0, show_value=true)
W_xoff = @bind xoff Slider(-100:1:100, default=0, show_value=true)
W_yoff = @bind yoff Slider(-100:1:100, default=-25, show_value=true)
W_ls   = @bind lens_scale Slider(1024:1024:16384, default=4096, show_value=true)

W_is   = @bind image_scale Slider(0.1:0.1:16, default=2, show_value=true)
W_ui   = @bind use_image CheckBox(true)
W_uc   = @bind use_chart CheckBox(true)

lens_scales = [ 256, 384, 512, 768, 1024, 1536, 2048,
				3072, 4096, 6144, 8192, 12288, 16384
]

W_Go = @bind G_only CheckBox(true);

## Generate and send interferograms

color_chart = load("../data/color_reschart02.png");
usaf_chart = load("../data/USAF512.png")
mono_chart = testimage("resolution_test_512");
cameraman = testimage("cameraman");
mandrill = testimage("mandrill");

source_img = usaf_chart;
# source_img = ba;

img = reverse(imresize(source_img, ratio=image_scale), dims=1);

fftshift(A::AFArray) = ArrayFire.shift(A, (size(A).÷2)..., 0, 0)

ArrayFire.device_gc()

ArrayFire.setafgcthreshold(4*1024^3)

afstat()

ArrayFire.allowslow(AFArray, false)

function extrema(a::AFArray{ComplexF32})
	# b = abs.(a)
	b = a
	return min_all(b), max_all(b)
end

function af_pad_centered(A::AFArray, final::Tuple)
	extra = final .- size(A)
	bdims = Int.(floor.(extra ./ 2))
	edims = Int.(ceil.(extra ./ 2))
	return af_pad(A, bdims, edims)
end

af_pad_centered(AFArray(Float32[1 2; 3 4]), (9, 9))

chart = usaf_chart

laplacian_kernel =
	[ 0  1  0;
		1 -4  1;
		0  1  0];
sobol_kernel = 
	[ -1 -1 -1;
		-1  9 -1;
		-1 -1 -1];

## Test ArrayFire performance

# RGB.(iG), RGB.(Array(AFArray(iG)))
# aiG = AFArray(iG)
# RGB.(Array(AFArray(iG))), RGB.(iG)
# alensG = AFArray(ϕlensG)
# aG = af_conv(iG, ϕlensG)
# (Array(ArrayFire.sync(aiG)))

af_conv(a::Array, b::Array) = Array(ArrayFire.sync(af_conv(AFArray(a), AFArray(b))))

# ϕ = [ ϕR, ϕG, ϕB ];

# Definitions

# @benchmark ArrayFire.sync(af_conv(a, b)) setup=(a=rand(AFArray{ComplexF32}, 8192, 8192); b=rand(AFArray{ComplexF32}, 8192, 8192))

BA = load("../data/Touhou - Bad Apple.mp4");

@bind frame Slider(1:length(BA), default=1684, show_value=true)

# ba = BA[frame] + imfilter(BA[frame], sharpening_factor*laplacian_kernel)
ba = BA[frame]

BA[frame]

ColorTypes.red(x::Gray) = x
ColorTypes.green(x::Gray) = x
ColorTypes.blue(x::Gray) = x

function extract_central(matrix::AbstractArray, dims::Tuple{Int, Int}; offset::Tuple{Int, Int}=(0, 0))
  rows, cols = size(matrix)
  target_rows, target_cols = dims
  row_offset, col_offset = offset

  # Handle cases where dimensions are too large, considering the offset
  target_rows = min(target_rows, rows - abs(row_offset))
  target_cols = min(target_cols, cols - abs(col_offset))

  # Calculate the central starting position
  start_row = (rows - target_rows) ÷ 2 + 1 
  start_col = (cols - target_cols) ÷ 2 + 1

  # Apply the offset
  start_row += row_offset 
  start_col += col_offset

  # Calculate the ending positions
  end_row = start_row + target_rows - 1
  end_col = start_col + target_cols - 1

  # Ensure the extracted region stays within the matrix bounds
  start_row = max(start_row, 1)
  end_row = min(end_row, rows)
  start_col = max(start_col, 1)
  end_col = min(end_col, cols)

  return matrix[start_row:end_row, start_col:end_col]
end


mutable struct OpenFinchConnection
	send_channel::Channel
	receive_channel::Channel
	send_task::Task
	receive_task::Ref

	function OpenFinchConnection(URI)
		send_channel = Channel(4)  # Channel for sending messages
		receive_channel = Channel(4)  # Channel for received messages
		receive_task = Ref{Any}(nothing)
		# Start task to handle sending and receiving messages asynchronously
		send_task = @async begin
			try
				HTTP.WebSockets.open(URI) do ws
					# Create a separate task for receiving messages
					receive_task[] = @async begin
						while isopen(receive_channel)
							try
								received_msg = HTTP.WebSockets.receive(ws)
								message = try
									# @debug "trying to JSON parse message"
									JSON.parse(received_msg)
								catch e
									# @debug "JSON parsing failed"
									received_msg
								end
								# lock(receive_channel) do
									if isfull(receive_channel)
										take!(receive_channel)
									end
									put!(receive_channel, message)
								# end
							catch e
								# @debug "WebSocket has been closed."
								break
							end
							sleep(0.01)  # Prevent tight loop from consuming too much CPU
						end
					end
	
					while isopen(send_channel)
						if isready(send_channel)  # Continue as long as there are messages to send
							message = take!(send_channel)
							if message isa Dict
								jsmessage = JSON.json(message)
								HTTP.WebSockets.send(ws, jsmessage)
							else
								HTTP.WebSockets.send(ws, message)
							end
						end
						sleep(0.01)  # Prevent tight loop from consuming too much CPU
					end
				end
			catch e
				@warn "Error in send/receive tasks: $e"
			finally
				close(send_channel)
				close(receive_channel)
			end
		end
	
		conn = new(send_channel, receive_channel, send_task, receive_task)
		finalizer(close, conn)  # Register the finalizer
		return conn
	end
end

function Base.close(conn::OpenFinchConnection)
	close(conn.send_channel)
	close(conn.receive_channel)
	# wait(conn.send_task)
	# wait(conn.receive_task)
end

function Base.put!(conn::OpenFinchConnection, obj)
	put!(conn.send_channel, obj)
end

function Base.take!(conn::OpenFinchConnection)
	conn.receive_channel.n_avail_items > 0 ? take!(conn.receive_channel) : nothing
end

isfull(ch) = !(ch.n_avail_items < ch.sz_max)


openfinch = OpenFinchConnection(URI)

put!(openfinch, Dict(
	"use_base64_encoding"=>Dict("value"=>false),
	"send_fps_updates"=>Dict("value"=>false),
	"stream_frames"=>Dict("value"=>false),
))

# API for OpenFinch server

function send_controls(channel, controls::Dict)
	put!(channel, Dict("set_control" => controls))  # Non-blocking put to the channel
end

function encode_image_file_to_base64(image_path::String)
	open(image_path, "r") do file
		return base64encode(file)
	end
end

function encode_image(image::Array{<:Colorant}, fmt)
	io = IOBuffer()
	save(Stream{fmt}(io), image)  # Save the image as fmt to the IOBuffer
	seekstart(io)  # Reset the buffer's position to the beginning
	return io
end

function image_to_base64(image::Array{<:Colorant}; lossless=true)
	fmt = lossless ? format"GIF" : format"JPEG"
	return base64encode(encode_image(image, fmt))  # Encode the buffer's content to base64
end

function base64_to_image(buf)
	imbuf = Base64.base64decode(buf)
	return load(IOBuffer(imbuf))
end

function send_image(channel, image::Array{<:Colorant}; lossless=true)
	encoded_image = image_to_base64(image, lossless=lossless)
	put!(channel, Dict("slm_image" => encoded_image))
end

send_controls(openfinch, Dict(
	"ILLUMINATION_MODE" => G_only ? "222" : "421",
	"LED_TIME" => LED_TIME,
	"LED_WIDTH" => LED_WIDTH,
	"ColourGains" => [red_gain, blue_gain],
	"AnalogueGain" => analog_gain,
	# "WAVE_DURATION" => round(Int, 8333*3.5),
	# "ScalerCrop" => [3, 0, 1456, 1088]
	# "ScalerCrop" => [0, 0, 64, 16]
	"NoiseReductionMode" => nrmode,
	"Brightness" => brightness,
	"Saturation" => saturation,
	"Contrast" => contrast,
	"Sharpness" => sharpness
));

# Conversion of RGB and M×{N}×{3} arrays

Hue(x::HSV{T} where T) = x.h
Sat(x::HSV{T} where T) = x.s
Val(x::HSV{T} where T) = x.v

MxNx3(x::Array{RGB{T},2} where T) = cat(red.(x), green.(x), blue.(x), dims=3)
MxNx3(x::Array{HSV{T},2} where T) = cat(Hue.(x), Sat.(x), Val.(x), dims=3)
MxNx3(x::Array{Lab{T},2} where T) = cat(getfield.(x, :l), getfield.(x, :a), getfield.(x, :b), dims=3)
MxNx3(x::Array{YIQ{T},2} where T) = cat(getfield.(x, :y), getfield.(x, :i), getfield.(x, :q), dims=3)

RGB(x::Array{T,3} where T) = RGB.(x[:,:,1], x[:,:,2], x[:,:,3])
BGR2RGB(x::Array{T,3} where T) = RGB.(x[:,:,3], x[:,:,2], x[:,:,1])
HSV(x::Array{T,3} where T) = HSV.(x[:,:,1], x[:,:,2], x[:,:,3])
Lab(x::Array{T,3} where T) = Lab.(x[:,:,1], x[:,:,2], x[:,:,3])
YIQ(x::Array{T,3} where T) = YIQ.(x[:,:,1], x[:,:,2], x[:,:,3])

cv2RGB(x::Array{T,3} where T) = RGB.(x[:,:,3]/255, x[:,:,2]/255, x[:,:,1]/255)
RGB2cv(x::Array{RGB{T},2} where T) = UInt8.(clamp.(round.(cat(blue.(x),green.(x),red.(x), dims=3)*255), 0, 255))

ComplexToHSV(z::T where T<:Complex) = HSV(angle(z)*180/π, 1, abs(z))
ComplexToHSV(z::T where T<:Real) = HSV(0, 0, abs(z))
ComplexToHSV(z::AbstractArray) = ComplexToHSV.(z)
# ComplexToHSV(z::T where T<:Number) = HSV(angle(z)*180/π, 1, abs(z))
# ComplexToHSV(z::Array{T,N} where {T<:Number, N}) = HSV.(angle.(z)*180/π, 1, normalize(abs.(z)))

ColorTypes.RGB(z::Complex) = HSV(angle(z)*180/π, 1, abs(z))

dx = 4.25u"µm"
# λs = (630, 530, 450) .* u"nm"
# λs = (λR, λG, λB) .* u"nm"

Nx, Ny = (1,1) .* lens_scale
Lx, Ly = dx.* (Nx, Ny)

# grid = meshgrid(range(-Nx/2, Nx/2, Nx), range(-Ny/2, Ny/2, Ny))
# X,Y = ustrip.(QuantityArray.(collect.(grid), dx))

Z = Float32(ustrip((f + df)*u"mm"))
x = AFArray(Float32.(ustrip(collect(range(-Lx/2, Lx/2, Nx) .- (xoff*1u"mm")))))'
y = AFArray(Float32.(ustrip(collect(range(-Ly/2, Ly/2, Ny) .- (yoff*1u"mm")))));
X2 = 1*x.*x .+ 0*y;
Y2 = 0*x .+ 1*y.*y;
R = sqrt.(X2 .+ Y2 .+ Z^2);

# ϕ_rand = [exp.(2f0π * im * rand(Float32, size(img)...)) for i in 1:3];
aϕ_rand = [exp.(2f0π * im * rand(AFArray{Float32}, size(img)...)) for i in 1:3];

iR = AFArray(Float32.(red.(img))) .* aϕ_rand[1];
iG = AFArray(Float32.(green.(img))) .* aϕ_rand[2];
iB = AFArray(Float32.(blue.(img))) .* aϕ_rand[3];

aϕlensG = sync(exp.((2f0π * 1im * R / Float32(ustrip(λG*u"nm")))));
# ϕlensG = exp.(2f0π * 1im * R / Float32(ustrip(λG*u"nm")));
ϕlensG = Array(aϕlensG);
ϕlensR = G_only ? ϕlensG : exp.(2f0π * 1im * R / Float32(ustrip(λR*u"nm")));
ϕlensB = G_only ? ϕlensG : exp.(2f0π * 1im * R / Float32(ustrip(λB*u"nm")));

# aϕG = use_image ? Array(af_conv(iG, aϕlensG)) : aϕlensG;
# ϕG = ArrayFire.convolve2(iG, aϕlensG, AF_CONV_DEFAULT, AF_CONV_AUTO);
# ϕG = ifft(sync(fft(iG)) .* sync(fft(aϕlensG)))

ϕG = ifft(fft(iG) .* fft(fftshift(aϕlensG))/lens_scale)
ϕR = G_only ? ϕG : use_image ? conv(iR, ϕlensR) : ϕlensR;
ϕB = G_only ? ϕG : use_image ? conv(iB, ϕlensB) : ϕlensB;

cgh = G_only ? Gray.(Array(real.(ϕG).>0)) :
	RGB.(
		Array(real.(ϕR).>0),
		Array(real.(ϕG).>0),
		Array(real.(ϕB).>0)
	);

slm_img = extract_central(cgh, (1280, 1280))

send_image(openfinch, slm_img)

size(img).*dx./u"cm"

ϕG[1:10, 1:10]

function decode_image(msg)
	if msg isa Dict
		try
			imbuf = Base64.base64decode(msg["image_response"]["image_base64"])
		catch e
			return nothing
		end
	else
		imbuf = msg
	end
	return load(IOBuffer(imbuf))
end

dashboard_html = """
<!DOCTYPE html>
<html>

<head>
	<title>OpenFinch dashboard</title>
</head>

<body>
	<h1>OpenFinch dashboard</h1>

	<div>
		<input type="checkbox" id="stream_frames" name="stream_frames" unchecked>
		<label for="stream_frames">Stream Frames</label>
	</div>

	<div>
		<input type="checkbox" id="use_base64_encoding" name="use_base64_encoding" unchecked>
		<label for="use_base64_encoding">Use base64 encoding</label>
	</div>

	<div>
		<input type="checkbox" id="send_fps_updates" name="send_fps_updates" unchecked>
		<label for="send_fps_updates">Send FPS updates</label>
	</div>

	<p>

	<div style="position: relative;">
		<img id="image" alt="image">
		<div style="position: absolute; bottom: 0%; left: 6%; z-index: 10;">
			<p style="color: hsl(0, 0%, 0%); text-shadow: rgb(255, 255, 255) 0px 0px 15px;">
				Reader/Capture/Controller fps:
				<span id="image_capture_reader_fps">0</span> /
				<span id="image_capture_capture_fps">0</span> /
				<span id="system_controller_fps">0</span>
			</p>
		</div>
	</div>

	<script>
		// default values for host and port if they have not been previously defined
		if (typeof host === 'undefined') { var host = window.location.hostname; }
		if (typeof port === 'undefined') { var port = window.location.port; }
		var uri = 'ws://' + host + ':' + port + '/ws';
		console.log("dashboard: uri = " + uri);
		var ws = new WebSocket(uri);
		ws.binaryType = 'blob'; // Set the binaryType to 'blob'
		var throttle = false;
		var nextIsImage = false;

		ws.onopen = function (event) {
			// nothing yet
		};

		ws.onmessage = function (event) {
			if (nextIsImage && event.data instanceof Blob) {
				var imgElement = document.getElementById('image');
				if (imgElement.src !== '') {
					// console.log('Revoke blob URL:', imgElement.src);
					URL.revokeObjectURL(imgElement.src); // Revoke the old object URL
				}
				var url = URL.createObjectURL(event.data);
				imgElement.src = url;
				throttle = false;
				nextIsImage = false;
			} else {
				var data = JSON.parse(event.data);

				// Handle image response
				if (data.image_response) {
					if (data.image_response.image === 'next') {
						nextIsImage = true;
					} else if (data.image_response.image === 'here') {
						var imgElement = document.getElementById('image');
						var base64Image = data.image_response.image_base64;
						imgElement.src = 'data:image/jpeg;base64,' + base64Image;
						nextIsImage = false;
					}
					// Handle metadata response
					// if (data.image_response.metadata) {
					// 	document.getElementById('metadata').textContent = data.image_response.metadata;
					// }
					if (data.image_response.metadata) {
						var metadata = data.image_response.metadata;
						var prettyMetadata = JSON.stringify(metadata, null, 2); // Pretty-print the JSON object
						document.getElementById('metadata').textContent = prettyMetadata;
					}
				} else if (data.update_controls) {
					Object.keys(data.update_controls).forEach(function (key) {
						updateElementValue(key, data.update_controls[key]);
					});
				} else {
					// Handle updates for each control element
					Object.keys(data).forEach(function (key) {
						if (data[key] && data[key].hasOwnProperty('value')) {
							updateElementValue(key, data[key].value);
						}
					});

					// Handle FPS update
					if (data.fps_update) {
						if (data.fps_update.image_capture_reader_fps !== undefined) {
							document.getElementById('image_capture_reader_fps').textContent = data.fps_update.image_capture_reader_fps.toFixed(2);
						}
						if (data.fps_update.image_capture_capture_fps !== undefined) {
							document.getElementById('image_capture_capture_fps').textContent = data.fps_update.image_capture_capture_fps.toFixed(2);
						}
						if (data.fps_update.system_controller_fps !== undefined) {
							document.getElementById('system_controller_fps').textContent = data.fps_update.system_controller_fps.toFixed(2);
						}
					}
				}
			}
		};

		document.getElementById('stream_frames').addEventListener('change', function () {
			// Send the preference to the server using the websocket connection
			ws.send(JSON.stringify({ 'stream_frames': { 'value': this.checked } }));
		});

		document.getElementById('use_base64_encoding').addEventListener('change', function () {
			// Send the preference to the server using the websocket connection
			ws.send(JSON.stringify({ 'use_base64_encoding': { 'value': this.checked } }));
		});

		document.getElementById('send_fps_updates').addEventListener('change', function () {
			// Send the preference to the server using the websocket connection
			ws.send(JSON.stringify({ 'send_fps_updates': { 'value': this.checked } }));
		});

		function sendInitialControlStates(controlIds) {
			controlIds.forEach(id => {
				const controlElement = document.getElementById(id);
				if (controlElement) {
					const controlValue = controlElement.type === 'checkbox' ? controlElement.checked : controlElement.value;
					ws.send(JSON.stringify({
						'set_control': {
							[id]: controlValue
						}
					}));
				}
			});
		}
	</script>
</body>

</html>
""";

HTML("""
<html><body><script> 
var host = "$host";
var port = "$port";
</script></body></html>
$dashboard_html
""");

# Persistent websocket API (experimental)

# from https://discourse.julialang.org/t/http-jl-websockets-help-getting-started/102867/4
function rawws(url,headers =[])
    headers = [
        "Upgrade" => "websocket",
        "Connection" => "Upgrade",
        "Sec-WebSocket-Key" => base64encode(rand(Random.RandomDevice(), UInt8, 16)),
        "Sec-WebSocket-Version" => "13",
        headers...
    ]
    r = HTTP.openraw("GET",url,headers)[1]

    ws = WebSockets.WebSocket(r)
    return ws
end

# ws = rawws(URI);
# WebSockets.send(ws, JSON.json(Dict(
# 	"use_base64_encoding"=>Dict("value"=>false),
# 	"send_fps_updates"=>Dict("value"=>false),
# 	"stream_frames"=>Dict("value"=>false),
# )))
# ws
# send(ws, JSON.json(Dict("image_request"=>true)))
