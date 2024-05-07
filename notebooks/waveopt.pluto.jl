### A Pluto.jl notebook ###
# v0.19.41

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
end

# ╔═╡ a5816c6c-3fc4-11eb-3356-e19b884ebb0d
begin
	using PlutoUI
	using PlutoTeachingTools
	using DSP, FFTW, Plots, Images, TestImages
	using QuartzImageIO
	using Colors
	using Statistics
	using LazyGrids
	import StatsBase
	import PlotlyJS
	using Unitful
	using Unitful: nm, µm, mm, cm, m
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

	# XXX there's probably a better way to get rid of the "Premature end..." warning message
	# import JpegTurbo
	function JpegTurbo._jpeg_check_bytes(data::Vector{UInt8})
		length(data) > 623 || throw(ArgumentError("Invalid number of bytes."))
		data[1:2] == [0xff, 0xd8] || throw(ArgumentError("Invalid JPEG byte sequence."))
		# data[end-1:end] == [0xff, 0xd9] || @warn "Premature end of JPEG byte sequence."
		return true
	end

	md"## Initialize execution environment"
end

# ╔═╡ 9a8d10f7-e387-46c0-aaa4-df825d7fd143
md"""
# Incoherent photon sampling
"""

# ╔═╡ af5d6dcd-2663-419a-90ab-a4e3b7b567eb
begin
	md"""
	Enable Table of Contents $(@bind enable_TOC CheckBox(false)) 
	
	Show figures $(@bind enable_figs CheckBox(false))
	
	$(ChooseDisplayMode())
	"""
end

# ╔═╡ 640c5c2e-a463-4041-a6a5-867cf9a4dd1c
enable_TOC ? TableOfContents() : nothing

# ╔═╡ 92b03dd1-0466-48ec-84e5-f3c05251ae8f
begin
	host = "winch.local"
	port = 8000
	URI = "ws://$host:$port/ws"
end

# ╔═╡ 351cfd74-e7fb-4ad7-ba54-3c64eb9134c1
begin
	
    mutable struct OpenFinchConnection
        send_channel::Channel{Dict}
        receive_channel::Channel{Dict}
        send_task::Task
        receive_task::Task

        function OpenFinchConnection(URI)
            send_channel = Channel{Dict}(10)  # Channel for sending messages
            receive_channel = Channel{Dict}(10)  # Channel for received messages
			
            # Start a task to handle sending messages asynchronously
            send_task = @async begin
                try
                    HTTP.WebSockets.open(URI) do ws
						# XXX how do we receive messages in this block?!
                        while isopen(send_channel)
                            if isready(send_channel)  # Continue as long as there are messages to send
                                message = take!(send_channel)
                                jsmessage = JSON.json(message)
                                HTTP.WebSockets.send(ws, jsmessage)
                            end
                            sleep(0.01)  # Prevent tight loop from consuming too much CPU
                        end
                    end
                catch e
                    @warn "Error in send task: $e"
                finally
                    close(send_channel)
                end
            end

			# XXX THIS NEEDS TO BE IN THE WebSockets.open CONTEXT ABOVE
            # Start a separate task to handle receiving messages asynchronously
            receive_task = @async begin
                try
                    HTTP.WebSockets.open(URI) do ws
                        while isopen(receive_channel)
                            try
                                received_msg = HTTP.WebSockets.receive(ws)
                            catch e
                                @warn "WebSocket has been closed."
                                break
                            end
                            try
                                parsed_msg = JSON.parse(received_msg)
                                if !isfull(receive_channel)
                                    put!(receive_channel, parsed_msg)
                                else
                                    @warn "Receive channel is full, dropping oldest message"
                                    take!(receive_channel)
                                    put!(receive_channel, parsed_msg)
                                end
                            catch e
                                @warn "Failed to parse received message"
                            end
                            sleep(0.01)  # Prevent tight loop from consuming too much CPU
                        end
                    end
                catch e
                    @warn "Error in receive task: $e"
                finally
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
		take!(conn.receive_channel)
	end

	isfull(ch) = !(ch.n_avail_items < ch.sz_max)

	OpenFinchConnection
end

# ╔═╡ 328bd3ac-b559-43f6-b4f6-ddcf33ee06eb
begin
	function send_controls(channel, controls::Dict)
	    put!(channel, Dict("set_control" => controls))  # Non-blocking put to the channel
	end

	function encode_image_file_to_base64(image_path::String)
	    open(image_path, "r") do file
	        return base64encode(file)
	    end
	end

	function image_to_base64(image::Array{<:Colorant})
		io = IOBuffer()
		save(Stream{format"PNG"}(io), image)  # Save the image as PNG to the IOBuffer
		seekstart(io)  # Reset the buffer's position to the beginning
		return base64encode(io)  # Encode the buffer's content to base64
	end

	function send_image(channel, image::Array{<:Colorant})
		encoded_image = image_to_base64(image)
		put!(channel, Dict("slm_image" => encoded_image))
	end

	md"""
	## API for OpenFinch server
	"""
end

# ╔═╡ 556b65ee-f79d-402f-a48c-8e0ce65cc499
openfinch = OpenFinchConnection(URI)

# ╔═╡ bc2fa5a2-82e5-4602-9a68-3248662ed917
openfinch

# ╔═╡ 829e9956-f198-46db-b98f-cdb9e0e57536
@bind clock Clock(1)

# ╔═╡ b8cdde01-ebc8-4a84-96aa-8bad2264a5ab
send_controls(openfinch, Dict("LED_TIME" => 0, "LED_WIDTH" => 100))

# ╔═╡ 9e994b57-876a-43da-b479-519737dda20b
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
put!(openfinch, Dict(
	"use_base64_encoding"=>Dict("value"=>true),
	"send_fps_updates"=>Dict("value"=>true),
	"stream_frames"=>Dict("value"=>false),
))
  ╠═╡ =#

# ╔═╡ 4f761eb7-0428-4ace-bd52-c1e30f169e5a
begin
	dashboard_html = """
	<!DOCTYPE html>
	<html>
	
	<head>
		<title>OpenFinch dashboard</title>
	</head>
	
	<body>
		<h1>OpenFinch dashboard</h1>
	
		<div>
			<input type="checkbox" id="stream_frames" name="stream_frames" checked>
			<label for="stream_frames">Stream Frames</label>
		</div>
	
		<div>
			<input type="checkbox" id="use_base64_encoding" name="use_base64_encoding" unchecked>
			<label for="use_base64_encoding">Use base64 encoding</label>
		</div>
	
		<div>
			<input type="checkbox" id="send_fps_updates" name="send_fps_updates" checked>
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
	
	md"""
	# HTML dashboard: will it blend?
	
	Here, a simplified dashboard has been incorporated directly into the notebook.
	
	Note that `HypertextLiteral` also defines `@htl` and `@htl_str`, and then there's `@html_str`, all of which have different escaping rules and conversions
	"""
end

# ╔═╡ a3eeaff1-1f98-4b9e-ace9-2d3a5c0110bf
HTML("""
<html><body><script> 
var host = "$host";
var port = "$port";
</script></body></html>
$dashboard_html
""")

# ╔═╡ e2482eb4-2bbd-4fef-9572-16287f0d11de
md"""
| control | value |
| --: | :-- |
| red gain | $(@bind red_gain Slider(0.0:0.1:4.0, default=1, show_value=true)) |
| blue gain | $(@bind blue_gain Slider(0.0:0.1:4.0, default=1.5, show_value=true)) |
| analog gain | $(@bind analog_gain Slider(1.0:0.1:10.0, default=2, show_value=true)) |
| LED width | $(@bind LED_WIDTH Slider(0:1:200, default=16, show_value=true)) |
| LED time | $(@bind LED_TIME Slider(0:1:3000, default=000, show_value=true)) |
| Image scaling factor | $(@bind image_scale Slider(0.1:0.1:10, default=2, show_value=true)) |
"""

# ╔═╡ 35cbfad7-825d-4961-b24d-56f8cb70a513
send_controls(openfinch, Dict(
	"LED_TIME" => LED_TIME,
	"LED_WIDTH" => LED_WIDTH,
	"ColourGains" => [red_gain, blue_gain],
	"AnalogueGain" => analog_gain,
	"ScalerCrop" => [3, 0, 1456, 1088] # [384, 0, 1024, 768]
));

# ╔═╡ 57e9ca9d-9427-40bd-8945-3c9f64dd600a
send_image(openfinch, imresize(testimage("resolution_test_512"), ratio=image_scale));

# ╔═╡ 2f5afb7c-8b1c-4592-bf2a-4259030a1009
testimage("resolution_test_512")

# ╔═╡ 54e4d041-0476-48d6-974d-7b0820a6f1ed
# ╠═╡ disabled = true
#=╠═╡
send_image(openfinch, test_image);
  ╠═╡ =#

# ╔═╡ e44a420c-7355-46a9-a87b-754bb15c6483
image_names = [
	# "71D-PfmrvjL._AC_SL1200_.jpg",
	# "CGH_9_dots_at_15_cm_v2.png",
	# "ISO_12233-reschart.png",
	"RCA_Indian_Head_test_pattern.jpeg",
	"USAF512.png",
	"color_reschart02.png",
	"jwcolourtestcard1024.jpg",
	# "output.png",
]

# ╔═╡ 70ad1a78-ddf2-41bb-b488-e64c6acc5e5d
md"""
Select image number: $(@bind image_number Slider(1:length(image_names), default=1, show_value=true))
"""

# ╔═╡ 36127489-a94e-4ca8-afd1-4db7575a0b81
test_image = load(joinpath("..", "data", image_names[image_number]))

# ╔═╡ 95e08cb9-bda6-4ac9-8c30-65f3228efa2c
md"""
## Test wave optics model
"""

# ╔═╡ 98b5c944-20fd-481f-a945-fc8cd997e9aa
md"""
!!! note "Note to self"

    A simple test of the wave optics model would be to perform a $2f$ Fourier transform.
"""

# ╔═╡ b1987990-4097-11eb-0b47-a5a4066542c3
md"""
Split an image into RGB slices, optionally randomizing their phase.
"""

# ╔═╡ 74904e50-a788-4710-87d3-53e7f53972e6
md"Randomize object phase $(@bind randomize_phase CheckBox(default=true))"

# ╔═╡ 6274213d-915c-433b-99ea-9388b6286ea1
md"""
Diffraction slice side length: $(@bind propL Slider(0.1:0.1:5.0, default=1, show_value=true)) mm

Propagation distance: $(@bind propdist Slider(0.0:0.1:1000.0, default=10.0, show_value=true)) mm
"""

# ╔═╡ fae6711e-650c-48e9-86cd-8444b4adcde9
#=╠═╡
vγ = mosaicview(RGB.(γ_cshots[(1:Int(floor(sqrt(length(cshots))))).^2]), ncol=4, rowmajor=true)
  ╠═╡ =#

# ╔═╡ 344b90cf-2eac-4c98-b3c3-7d72b743fb29
#=╠═╡
plot([HSV(cshots[end]) HSV(γ_cshots[end])], size=(2N, N))
  ╠═╡ =#

# ╔═╡ fa530546-233a-42fc-a8c2-7d41a2ceff89
#=╠═╡
cshots = cumsum(abs2.(shots))
  ╠═╡ =#

# ╔═╡ ec6f05d6-cef8-449b-8020-40a9621b0b89
#=╠═╡
γ_cshots = cumsum(γ_shots)
  ╠═╡ =#

# ╔═╡ 8c98fed2-7f04-4ded-95cd-4f957deb8581
#=╠═╡
[ cshots[end] γ_cshots[end] ]
  ╠═╡ =#

# ╔═╡ 431fff7c-8a82-4197-8e7d-11a74fd271f8
#=╠═╡
γ_shots = γ_sample.(shots)
  ╠═╡ =#

# ╔═╡ 3c9e67b8-a232-4d47-a04c-57a76f4b2afb
#=╠═╡
γ_sample(shots[1])
  ╠═╡ =#

# ╔═╡ f54518c6-f215-4438-a1e6-81c93e9cca4f
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
begin
	# showfield(x) = ComplexToHSV(x)
	# showfield(x::LightField) = x
	# showfield(x::PhasorField) = x
	
	initial = test_lf
	L       = 1mm * propL
	s 		= 1mm
	dist 	= s *propdist
	shots 	= []
	@progress for i ∈ 1:256
		# forward = normalize(propTF(initial, L, λ, scale*propdist))
		forward  = propagate(randomizephase(initial), dist, L; prop=propfn)
		# backward = normalize((propTF(forward, L, λ, -scale*propdist)))
		backward = propagate((forward), -dist, L; prop=propfn)
		push!(shots, backward)
	end
end
  ╠═╡ =#

# ╔═╡ 81f6131a-84f5-42b9-af6a-5eb35e459efe
# let
# 	# start with the object field
# 	obj = LightField([λG], [object[:,:,2]])
# 	obj = object_lf

# 	# convolve with spherical kernel to propagate distance z₁
# 	# sphericalkernelG = acc_spherical_wavefront(xA, yA, z₁, kG)
# 	# ϕ_into_lens = acc_convsame(obj.ϕ[1], sphericalkernelG)
# 	ϕ_into_lens = propagate(obj, z₁, L1)
	
# 	# modulate by lens transfer function
# 	ϕ_lens = acc_thin_lens(xA,yA,f₀,kG)
# 	ϕ_outof_lens = ϕ_into_lens.ϕ[1] * PhasorField(ϕ_lens)
	
# 	# propagate distance L to image place
# 	ϕ_image = propagate(ϕ_outof_lens, λG, L, L1)
# 	LightField([λG], [ϕ_image.ϕ])
# end

# ╔═╡ d5719963-e960-499a-bc36-d258d829ada0
md"""
# Calculate PSF for given mask
"""

# ╔═╡ 59abdc6e-eff9-490d-be7a-1808a6a8c808
#=
wv_start
400
Starting wavelength (nm)

wv_stop
700
Stopping wavelength (nm)

wv_step
2.5
wavelength step size over interval (nm)

wv_units
1e-6
unit convertion w.r.t nm. (1e-6 mm ) or 1 nm

dev
20
range from center of current wavelength

dev_steps
2
wavelength sampling step size (for psf execution)

batch_size
121
Run N parallel wavelength computations. Max wavelengths are 121

dx
0.5e-3
sample spacing, mm

ps
2.24e-3
sample spacing, mm

z0
340
distance, obj to mask, mm

zML
2
distace, mask to lens, mm

fL
3.04
lens focal length

Ra
0.76
aperture radius, mm  # 1.52 is diameter

theta
0
mask rotation in degrees, needed for correlation study.

psf_size
600
final size of the PSF generated

mask_filename	# default=../data/Mask26.tif
joinpath(dirname(pathof(WaveOptics)), ../data/Mask26.tif)
path to mask file tiff

mask_center
8000
center: center of the cropped region

mask_sp
1800
width of the cropped patch

LEDspect # default=../data/LEDspect.mat
joinpath(dirname(pathof(WaveOptics)), ../data/LEDspect.mat)
Bayer pattern led spectral response

dtype
float32
default datatype for execution

output_size
600
Output (padded) size of final psf.
=#

# ╔═╡ 51a7dbdc-af5a-4c6e-a406-cd98fb96d464
md"""
## Simulation parameters
"""

# ╔═╡ a0230cb0-3536-4d9e-beb9-9dcf5e38700a
md"Use impulse as point source for PSF calculation: $(@bind PSF_source_impulse CheckBox())"

# ╔═╡ 53031cc2-5191-4457-b28f-a7133d0bdafd
md"""Source wavelengths for PSF calculation: $(@bind PSF_source_RGB Select(["RGB", "R", "G", "B"]))"""

# ╔═╡ 9820b76a-4b42-41cb-b9f1-eebcc8b6f507
md"Simulation resolution: N=$(@bind N_sim Select(repr.([256, 512, 1024, 1280, 1536, 2048, 2560, 3072, 3584, 4096])))"

# ╔═╡ 5b7e57a6-3f27-464b-8781-64134aa6a1ca
md"""
Propagator type: $(@bind propstring Select([
	"PropFresnel"	=> "Fresnel kernel convolution",
	"PropTF"		=> "Transfer function propagator [Voelz]",
	"PropIR"		=> "Impulse response propagator [Voelz]",
]))
"""

# ╔═╡ 34028967-3c01-49f2-877e-7d557873689c
@bind psf_prop_dist Slider(0.0:0.01:2.0, default=1.0, show_value=true)

# ╔═╡ 93b85f08-36c1-480f-9057-0f1ca65d99c4
# psf_corrector = let
# 	# modulate by mask transfer function
# 	ϕ_into_lens = ϕ_into_mask.ϕ[1] * mask
	
# 	# modulate by lens transfer function
# 	ϕ_outof_lens = ϕ_into_lens.ϕ * PhasorField(ϕ_lens)
	
# 	# propagate distance L to image place
# 	ϕ_image = propagate(ϕ_outof_lens, λG, f_obj, L1)
	
# 	complex(normalize(abs2.(ϕ_image.ϕ)))
# 	# LightField([λG], [ϕ_image.ϕ])
# end

# ╔═╡ 06d42379-e45e-4082-9b9e-2386c224a313
to

# ╔═╡ f8e8cdf3-3b8b-48c6-9476-84acb3cfb808
#=
let
	initial = normalize(object_lf.ϕ[1])
	L = propL * 1e-3 # 5e-3
	λ = 550e-9
	scale = 1e-3
	dist = scale * propdist

	forward = normalize(propTF(initial, L, λ, dist))
	backward = normalize((propTF(forward, L, λ, -dist)))
	final = normalize(abs.(backward))
	difference = final - abs.(initial)
	
	showfield(x) = ComplexToHSV(x)

	md"""
	| Initial light field | Forward propagation to $(round(dist*1000, sigdigits=4)) mm | Backward propagation to 0 mm |
	| :-: | :-: | :-: |
	| $(showfield(initial)) | $(showfield(forward)) | $(showfield(backward)) |
	"""
end
=#

# ╔═╡ edcaf4f8-77f5-4ceb-8370-6490c2b825f3
md"""
# Free space propagation
"""

# ╔═╡ d9b4bf70-c032-4fea-9f8f-a0716cf04767
# function propFresnel(ϕ::Matrix, λ::Number, dist::Number, L1::Number)
# 	M,N = size(ϕ)
# 	if M != N; error("propFresnel() requires a square matrix"); end
# 	k = 2π/λ
# 	Δx = L1/N
# 	# fx = -1/2Δx:1/L1:(1/2Δx-1/L1)
# 	# fx = -N/2L1:1/L1:(N/2L1-1/L1)
# 	fx = ((-N/2):1:(N/2-1))*L1/N
# 	xs,ys = meshgrid(fx,fx);
# 	K = acc_fresnel_kernel(xs, ys, dist, k)
# 	ϕ_out = acc_convsame(ComplexF32.(ϕ), K)
# end

# ╔═╡ c864f046-3f0b-11eb-3973-4f53d2419f30
md"""
---
# Definitions
"""

# ╔═╡ bb9a52ae-8929-4656-a985-15bad69216f8
md"""
## CSS to modify Pluto notebook layout
"""

# ╔═╡ 73918b6a-60bd-4c57-8963-d9a6da3c2d38
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
if enable_TOC
	TableOfContents()
end
  ╠═╡ =#

# ╔═╡ f41607f8-cd04-4937-8c59-c952221f9112
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
@bind screenWidth @htl("""
	<div>
	<script>
		var div = currentScript.parentElement
		div.value = screen.width
	</script>
	</div>
""")
  ╠═╡ =#

# ╔═╡ 5ac55af9-b174-44e8-a9fa-8790c20bd0be
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
begin
	cellWidth= min(850, screenWidth*0.9)
	@htl("""
		<style>
			pluto-notebook {
				margin: auto;
				# margin-top: auto;
				# margin-right: 50px;
				# margin-bottom: auto;
				# margin-left: 0px;
				width: $(cellWidth)px;
		
				#display: inline-block;	
				#width: 300px;
				#border: 15px solid green;
				#padding: 50px;
				#margin: 10px;
			}
		</style>
	""")
end
  ╠═╡ =#

# ╔═╡ 20f5da3a-6180-4412-b746-61273c77587e
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
#= html"""<style>
main {
    max-width: 1000px;
}
""" =#
  ╠═╡ =#

# ╔═╡ 75b66ef5-972b-412b-aee5-d63791de9b7f
begin
	struct PhasorField
		ϕ::Array{T where T <: Complex}
	end
	
	struct RGBComplexField
		R::Array{T} where {T <: Complex}
		G::Array{T} where {T <: Complex}
		B::Array{T} where {T <: Complex}
	end
	
	struct LightField
		λ::Vector{S} where {S<:Number}
		ϕ::Vector{Matrix{T}} where {T<:Complex}

		function LightField(l, f::Vector{Matrix{T}} where {T<:Complex})
			if length(l) != length(f)
				error("Lengths of λ[] and ϕ[] must match")
			end
			new(l, f)
		end
		
		function LightField(l, f)
			# cvf::Vector{Matrix{T}} where {T<:Complex} = complex.(f)
			LightField(l, complex.(f))
		end
	end

	Base.abs(lf::LightField) =
		LightField(lf.λ, [abs.(ϕ) for ϕ ∈ lf.ϕ])
	
	Base.abs2(lf::LightField) =
		LightField(lf.λ, [abs2.(ϕ) for ϕ ∈ lf.ϕ])
	
	function Base.:-(f1::LightField, f2::LightField)
		if f1.λ != f2.λ
			error("LightField wavelengths must match")
		end
		return LightField(f1.λ, f1.ϕ - f2.ϕ)
	end
	
	Base.:*(a::PhasorField, b::Matrix{T} where {T<:Number}) =
		PhasorField(a.ϕ .* resample(ComplexF32.(b),   size(a.ϕ)))

	Base.:*(a::Matrix{T} where {T<:Number}, b::PhasorField) =
		PhasorField(a   .* resample(ComplexF32.(b.ϕ), size(a)))

	Base.:*(a::PhasorField, b::PhasorField) =
		PhasorField(a.ϕ .* resample(ComplexF32.(b.ϕ), size(a.ϕ)))
	
	Base.:*(a::LightField, b::PhasorField) =
		LightField(a.λ, [ (ϕ*b).ϕ for ϕ ∈ a.ϕ ])

	Base.:≈(a::PhasorField, b::PhasorField) =
		a.ϕ ≈ b.ϕ
	
	Base.:-(a::PhasorField, b::PhasorField) =
		PhasorField(a.ϕ - b.ϕ)

	Base.:+(a::PhasorField, b::PhasorField) =
		PhasorField(a.ϕ + b.ϕ)

	Base.:/(a::PhasorField, b::PhasorField) =
		PhasorField(a.ϕ / b.ϕ)
	
	Base.size(p::PhasorField) =
		size(p.ϕ)
	
	Base.abs(p::PhasorField) =
		abs.(p.ϕ)

	Base.abs2(p::PhasorField) =
		abs2.(p.ϕ)
	
	Broadcast.broadcasted(::typeof(/), p::PhasorField, x::Number) =
		Broadcast.broadcasted(Base.:/, p.ϕ, x)
	
	convert(::PhasorField, x::Matrix{<:Complex}) = PhasorField(ComplexF32.(x))
	
	Base.:^(lf::LightField, x) = LightField(lf.λ, [ϕ.^x for ϕ ∈ lf.ϕ])
	
	FourierTools.resample(lf::LightField, dims) = LightField(lf.λ, [resample(ϕ, dims) for ϕ ∈ lf.ϕ ])

	to_m(x::Number) = x
	to_m(x::Quantity) = ustrip(u"m", x)
	to_nm(x::Number) = x*1e-9
	to_nm(x::Quantity) = ustrip(u"nm", x)

	#
	
    meshgrid(y, x) = (ndgrid(x, y)[[2, 1]]...,)
	
	function padtocenterofNxN(A, N)
		N_A = size(A)
		N_diff = N .- N_A
		N_start = N_diff .÷ 2
		indices = [ s+1:s+n for (s,n) ∈ zip(N_start, N_A) ]

		pA = zeros(eltype(A), N,N)
		pA[indices...] .= A
		pA
	end
	
	function equalize(A)
		lo,hi = extrema(A)
		return (A.-lo)/(hi-lo)
	end

	unitaryscale(A) = ((lo,hi)->(A.-lo)/(hi-lo))(extrema(abs.(A))...)
	
"""
    `normalize(A; percentile=99)`

Return a rescaled copy of array `A` such that the magnitude of the specfied `percentile` (default 99%) becomes 1.
"""
	normalize(A::Array; percentile=99) = A ./ StatsBase.percentile(abs.(A)[:], percentile)
	normalize(p::PhasorField; args...) = PhasorField(normalize(p.ϕ; args...))	
	normalize(lf::LightField; args...) = LightField(lf.λ, [normalize(ϕ; args...) for ϕ ∈ lf.ϕ])

"""
    `normalize!(A; percentile=99)`

Rescale array `A` in place so that the magnitude of the specfied `percentile` (default 99%) becomes 1.
"""
	normalize!(A::Array; percentile=99) = A ./= StatsBase.percentile(abs.(A)[:], percentile)
	
	###
		
	md"## `PhasorField`s and `LightField`s"
end

# ╔═╡ f4527ccf-ffcc-402f-b22d-542e2efdb75a
function Base.:+(f1::LightField, f2::LightField)
	if f1.λ != f2.λ
		error("LightField wavelengths must match")
	end
	return LightField(f1.λ, [ϕ1 .+ ϕ2 for (ϕ1, ϕ2) ∈ zip(f1.ϕ, f2.ϕ)])
end

# ╔═╡ 069947d4-c67f-4039-95d7-6049aa415847
function Base.:/(f1::LightField, f2::LightField)
	if f1.λ != f2.λ
		error("LightField wavelengths must match")
	end
	return LightField(f1.λ, [ϕ1 ./ ϕ2 for (ϕ1, ϕ2) ∈ zip(f1.ϕ, f2.ϕ)])
end

# ╔═╡ f47f01a1-cb57-43c7-b323-73a63858c532
!enable_figs ? nothing : md"""
## Wave optics summarized in one figure
$(html"<center>")
$(imresize(load("waveopt_fig1.png"), ratio=2/3))
$(html"</center>")
"""

# ╔═╡ 69e56aef-0ceb-4cb2-bdec-e6f23e145b5b
!enable_figs ? nothing : md"""
## Wave optics simulation design notes
 $(html"<center>")
 $(imresize(load("Optical system with 4f filter.png"), ratio=2/3))
 $(html"</center>")

To simulate the optical system shown above from object plane (1) to image plane (9) we might take the following steps:

1) define point source (spherical wave) $P$ as a degenerate grid $g_P$ (*i.e.* a grid with a single point)

2) propagate from $g_P$ with wavenumber $k$ for distance $d_1$ to grid at mask plane $g_M$ to obtain phasor field $\phi_{M1}$

3) modulate phasor field $\phi_{M1}$ at $g_M$ by mask phase map $M$ to obtain phasor field $\phi_{M2}$

4) propagate $\phi_{M2}$ with wavenumber $k$ for distance $d_2$ from grid $g_M$ to grid $g_L$ at lens to obtain phasor field $\phi_{L1}$

5) modulate phasor field $\phi_{L1}$ at $g_L$ by lens phase map $L$ to obtain phasor field $\phi_{L2}$

6) propagate $\phi_{M2}$ with wavenumber $k$ for distance $d_3$ from grid $g_L$ to grid $g_C$ at corrector to obtain phasor field $\phi_{C1}$

7) modulate phasor field $\phi_{C1}$ at $g_C$ by corrector phase map $C$ to obtain phasor field $\phi_{C2}$

8) propagate $\phi_{C2}$ with wavenumber $k$ for distance $d_4$ from grid $g_C$ to grid $g_S$ at sensor to obtain phasor field $\phi_{S}$

9) calculate squared modulus of phasor field $\phi_S$ on grid $g_S$ to obtain image intensity $I_S$


Note that there are several repeated object types and operations. The necessary object types include:

* a `Plane`, defined by unit vectors $\hat u, \hat v$

* a `Grid`, defined by a `Plane`, an origin `Point` $O$, extents $\Delta u , \Delta v$ and number of samples $M, N$ along those directions

* a `PhasorField`, defined by a `Grid` and a complex amplitude array $\Phi$

The necessary operations include:

* `propagate(g_from::PhasorField, g_to::Grid, k::Wavenumber)::PhasorField`
* the usual arithmetic operations on PhasorFields (`+`, `-`, `*`, `/`, *etc.*)

"""

# ╔═╡ 5adb649d-0165-4503-bc51-1f876573a1a4
function Base.:*(f1::LightField, f2::LightField)
	if f1.λ != f2.λ
		error("LightField wavelengths must match")
	end
	return LightField(f1.λ, [ϕ1 .* ϕ2 for (ϕ1, ϕ2) ∈ zip(f1.ϕ, f2.ϕ)])
end

# ╔═╡ 35d55d37-559d-4606-bb8a-209a29798ce2
Base.:*(c::Number, f::LightField) = 
	return LightField(f.λ, [c .* ϕ for ϕ ∈ f.ϕ])

# ╔═╡ ef1c75f7-f833-406b-84f1-672276b9f282
begin
	randomizephase(A::Matrix) = cis.(2π*rand(Float32, size(A))) .* A
	randomizephase(lf::LightField) = LightField(lf.λ, randomizephase.(lf.ϕ))
	randomizephase(pf::PhasorField) = PhasorField(randomizephase.(pf.ϕ))
end

# ╔═╡ 8bc690fa-409a-11eb-0f03-cf55800897bb
begin
	# ENV["AF_JIT_KERNEL_TRACE"] = joinpath(homedir(), "fardel", "tmp")
	# ENV["AF_JIT_KERNEL_TRACE"] = "stdout"
	ENV["AF_PRINT_ERRORS"] = "1"
	ENV["AF_DISABLE_GRAPHICS"] = "1"
	# ENV["AF_MEM_DEBUG"] = "1"
	# ENV["AF_TRACE"] = "jit,platform"
	# all: All trace outputs
	# jit: Logs kernel fetch & respective compile options and any errors.
	# mem: Memory management allocation, free and garbage collection information
	# platform: Device management information
	# unified: Unified backend dynamic loading information
	ENV["AF_CUDA_MAX_JIT_LEN"] = "100"
	ENV["AF_OPENCL_MAX_JIT_LEN"] = "50"
	ENV["AF_SYNCHRONOUS_CALLS"] = "0"

	using Libdl
	((x,y)->x∈y||push!(y,x))("/opt/arrayfire/lib", Libdl.DL_LOAD_PATH)
	((x,y)->x∈y||push!(y,x))("/opt/homebrew/lib", Libdl.DL_LOAD_PATH)

	# using WaveOptics
	# using WaveOptics.ArrayFire
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
	
	md"## ArrayFire extensions"
end

# ╔═╡ 9e296c81-2438-4c84-9be3-7c64ea1634b1
begin
	Base.real(lf::LightField) =
		LightField(lf.λ, [complex(real.(ϕ)) for ϕ ∈ lf.ϕ])

	Base.imag(lf::LightField) =
		LightField(lf.λ, [complex(imag.(ϕ)) for ϕ ∈ lf.ϕ])
end

# ╔═╡ d5c4a808-06be-4992-9ad2-d7480c6898e3
begin
	γ_sample(A::Matrix) = complex(real.(unitaryscale(abs2.(A))) .> rand(size(A)...))
	γ_sample(pf::PhasorField) = PhasorField(γ_sample(pf.ϕ))
	γ_sample(lf::LightField) = LightField(lf.λ, γ_sample(ϕ) for ϕ ∈ lf.ϕ)
end

# ╔═╡ 6e9b127b-7bcd-43b7-9571-2e4a52600c66
function propFresnel(ϕ::Matrix, λ::Number, dist::Number, L1::Number)
	function af_spherical_wavefront(x, y, d, k)
		k1 = ComplexF32(ustrip(upreferred(1im*k)))
		xf = AFArray(Float32.(ustrip(upreferred.(x))))
		yf = AFArray(Float32.(ustrip(upreferred.(y))))
		rf = xf.*xf + yf.*yf + Float32(ustrip(upreferred(d^2)))
		sf = sqrt(rf)
		Array(exp(k1*sf))
	end

	function af_thin_lens(x, y, f, k)
		k1 = ComplexF32(ustrip(upreferred(1im*k)))
		xf = AFArray(Float32.(ustrip(upreferred.(x))))
		yf = AFArray(Float32.(ustrip(upreferred.(y))))
		f1 = Float32(ustrip(upreferred(f)))
		rf = xf.*xf + yf.*yf + f1^2
		sf = f1 .- sqrt(rf)
		Array(exp(k1*sf))
	end
	
	function af_fresnel_kernel(x,y,d,k)
		c1 = ComplexF32(ustrip(upreferred(1im*(k/(2*d)))))
		xf = AFArray(Float32.(ustrip(upreferred.(x))))
		yf = AFArray(Float32.(ustrip(upreferred.(y))))
		Array(exp(c1 * (xf.*xf + yf.*yf)))
	end

	function af_convsame(A,k)
		return Array(af_conv(
				AFArray{ComplexF32}(ComplexF32.(A)),
				AFArray{ComplexF32}(ComplexF32.(k)),
				expand=false, inplace=true))
	end

	@timeit to "propFresnel" begin
		@timeit to "setup" begin
			M,N = size(ϕ)
			if M != N; error("propFresnel() requires a square matrix"); end
			k = 2π/λ
			Δx = L1/N
			# fx = -1/2Δx:1/L1:(1/2Δx-1/L1)
			# fx = -N/2L1:1/L1:(N/2L1-1/L1)
			fx = ((-N/2):1:(N/2-1))*L1/N
		end
		@timeit to "meshgrid$N" xs,ys = meshgrid(fx,fx)
		@timeit to "af_fresnel_kernel$N" K = af_fresnel_kernel(xs, ys, dist, k)
		@timeit to "af_convsame$N" ϕ_out = af_convsame(ComplexF32.(ϕ), K)
	end
end

# ╔═╡ 9a6f26c4-35f9-4627-aee2-3f7641ba2138
"""
	propIR(u,L,λ,z)

Coherently propagate complex amplitude field via impulse response approach;
assumes same ``x`` and ``y`` side lengths and uniform sampling

# Arguments
- `u`: source plane field
- `L`: source and observation plane side length
- `λ`: wavelength
- `z`: propagation distance
"""
function propIR(u1,L,lambda,z)
	# Adapted from
	# David George Voelz - Computational Fourier Optics, a MATLAB tutorial
	# (SPIE Tutorial Texts Vol. TT89)-SPIE Press (2010)
	M,N = size(u1);           #get input field array size
	dx=L/M;                   #sample interval
	k=2*pi/lambda;            #wavenumber

	x=-L/2:dx:L/2-dx;         #spatial coords

	# x = ((-M/2):1:(M/2-1))/L

	X,Y =meshgrid(x,x);

	h=1/(1im*lambda*z)*exp.(1im*k/(2*z)*(X.^2+Y.^2)); #impulse
	H=fft(fftshift(h))*dx^2; #create trans func
	U1=fft(fftshift(u1));    #shift, fft src field
	U2=H.*U1;                 #multiply
	u2=ifftshift(ifft(U2));  #inv fft, center obs field
	return u2
end

# ╔═╡ 12bd7c0d-063a-4d1a-925e-868e625123a4
"""
	propTF(u, L, λ, z)

Coherently propagate complex amplitude field via transfer function approach;
assumes same ``x`` and ``y`` side lengths and uniform sampling

# Arguments
- `u`: source plane field
- `L`: source and observation plane side length
- `λ`: wavelength
- `z`: propagation distance
"""
function propTF(u1,L,lambda,z)
	# Adapted from
	# David George Voelz - Computational Fourier Optics, a MATLAB tutorial
	# (SPIE Tutorial Texts Vol. TT89)-SPIE Press (2010)
	M,N =size(u1);           #get input field array size
	dx=L/M;                   #sample interval
	k=2*pi/lambda;            #wavenumber

	fx=-1/(2*dx):1/L:1/(2*dx)-1/L; #freq coords
	# fx = -M/2L:1/L:(M/2L - 1/L)
	fx = ((-M/2):1:(M/2-1))/L

	FX,FY = meshgrid(fx,fx);
	H=exp.(-1im*pi*lambda*z*(FX.^2+FY.^2));  #trans func
	H=fftshift(H);            #shift trans func
	U1=fft(fftshift(u1));    #shift, fft src field
	U2=H.*U1;                 #multiply
	u2=ifftshift(ifft(U2));  #inv fft, center obs field
	return u2
end

# ╔═╡ 7b8609ac-8198-48f9-8b43-79f577668527
"""
	propFF(u1,L1,lambda,z)

Coherently propagate complex amplitude via Fraunhofer far-field approximation;
assumes same ``x`` and ``y`` side lengths and uniform sampling

# Arguments
- `u1`: source plane field
- `L1`: source plane side length
- `λ`: wavelength
- `z`: propagation distance

# Return value
`propFF` returns a tuple `(u2, L2)` where
- `u2` is the observation plane field
- `L2` is the observation plane side length

"""
function propFF(u1,L1,lambda,z)
	# Adapted from
	# David George Voelz - Computational Fourier Optics, a MATLAB tutorial
	# (SPIE Tutorial Texts Vol. TT89)-SPIE Press (2010)
	M,N=size(u1);           #get input field array size
	dx1=L1/M;                 #source sample interval
	k=2*pi/lambda;            #wavenumber
	#
	L2=lambda*z/dx1;          #obs sidelength
	dx2=lambda*z/L1;          #obs sample interval
	x2=-L2/2:dx2:L2/2-dx2;    #obs coords
	X2,Y2 = meshgrid(x2,x2);
	#
	c=1/(1im*lambda*z)*exp.(1im*k/(2*z)*(X2.^2+Y2.^2));
	u2=c.*ifftshift(fft(fftshift(u1)))*dx1^2;
	return u2, L2
end

# ╔═╡ 0379641b-62e7-4118-be6d-4af457481a90
"""
	prop2step(u1, L1, L2, λ, z)

Two step Fresnel diffraction method; assumes uniform sampling and square array


# Arguments
- `u1`: complex field at source plane
- `L1`: source plane side-length
- `L2`: observation plane side-length
- `λ`: wavelength
- `z`: propagation distance

# Returns
output field at observation plane
"""
function prop2step(u1, L1, L2, λ, z)
	# Adapted from
	# David George Voelz - Computational Fourier Optics, a MATLAB tutorial
	# (SPIE Tutorial Texts Vol. TT89)-SPIE Press (2010)

	M,N = size(u1) 	  	# input array size
	k = 2π/λ	        # wavenumber

	# source plane
	dx1 = L1/M
	x1 = (-L1/2):dx1:(L1/2-dx1)
	Xs,Ys = meshgrid(x1,x1)

	u = u1.*exp.(1im*k/(2*z*L1)*(L1-L2)*(Xs.^2+Ys.^2))
	u = fft(fftshift(u))

	# dummy (frequency) plane
	fx1 = (-1/(2*dx1)):(1/L1):(1/(2*dx1)-1/L1)
	fx1 = fftshift(fx1)
	FX1,FY1 = meshgrid(fx1,fx1)

	u = exp.(-1im*pi*λ*z*L1/L2*(FX1.^2+FY1.^2)).*u
	u = ifftshift(ifft(u))

	# observation plane
	dx2 = L2/M
	x2 = (-L2/2):dx2:(L2/2-dx2)
	Xo,Yo = meshgrid(x2,x2)

	u2 = (L2/L1)*u.*exp.(-1im*k/(2*z*L2)*(L1-L2)*(Xo.^2+Yo.^2))
	u2 = u2*dx1^2/dx2^2   # x1 to x2 scale adjustment

	return u2
end

# ╔═╡ 52debc73-6c49-4eb8-b83a-1c643ee48bb4
begin
	abstract type Propagator <: Any end
	struct PropFresnel <: Propagator end
	struct Prop2Step <: Propagator end
	struct PropFF <: Propagator end
	struct PropIR <: Propagator end
	struct PropTF <: Propagator end
	
	# first define the propagators for PhasorFields with different method types
	_propagate(P::PhasorField, λ::Quantity, dist::Quantity, L1::Quantity, L2::Quantity, prop::Prop2Step)::PhasorField =
		PhasorField(prop2step(P.ϕ, to_m(L1), to_m(L2), to_m(λ), to_m(dist)))
	
	_propagate(P::PhasorField, λ::Quantity, dist::Quantity, L1::Quantity, L2::Quantity, prop::PropIR)::PhasorField =
		PhasorField(propIR(P.ϕ, to_m(L1), to_m(λ), to_m(dist)))
	
	_propagate(P::PhasorField, λ::Quantity, dist::Quantity, L1::Quantity, L2::Quantity, prop::PropTF)::PhasorField =
		PhasorField(propTF(P.ϕ, to_m(L1), to_m(λ), to_m(dist)))

	_propagate(P::PhasorField, λ::Quantity, dist::Quantity, L1::Quantity, L2::Quantity, prop::PropFresnel)::PhasorField =
		PhasorField(propFresnel(P.ϕ, to_m(λ), to_m(dist), to_m(L1)))
	
	# then define the top level propagator methods
	propagate(P::PhasorField, λ::Quantity, dist::Quantity, L1::Quantity;
		L2::Quantity=L1, prop::Propagator=PropFresnel())::PhasorField =
		_propagate(P, λ, dist, L1, L2, prop)
	
  	propagate(M::Matrix, λ::Quantity, dist::Quantity, L1::Quantity;
		L2::Quantity=L1, prop::Propagator=PropFresnel()) =
		_propagate(PhasorField(M), λ, dist, L1, L2, prop).ϕ
	
	propagate(L::LightField, dist::Quantity, L1::Quantity;
		L2::Quantity=L1, prop::Propagator=PropFresnel())::LightField =
 		LightField(L.λ, [
			propagate(PhasorField(ϕ), λ, dist, L1; L2=L2, prop=prop).ϕ
 		for (λ, ϕ) in zip(L.λ, L.ϕ) ])
end;

# ╔═╡ 75870b96-527b-49c7-9b11-05f12be34a56
begin
	# propfn = eval(Meta.parse(propstring * "()"));	# 🤔🤨🧐🤭😶😐😑😫🥺😢😭
	if propstring == "PropFresnel"
		propfn = PropFresnel()
	elseif propstring == "PropTF"
		propfn = PropTF()
	elseif propstring == "PropIR"
		propfn = PropIR()
	end

	N=Meta.parse(N_sim)
end;

# ╔═╡ 3207f15d-aaf6-4f57-b8a0-c8f7c83293a3
begin
	# mask = PhasorField(resample(ComplexF32.((1.0+0im)*(load("../../data/boe_mask.tif") .> 0)), (N, N)) .* (gaussian((N,N), 0.33).>0.33))
	mask = PhasorField((gaussian((N,N), 0.33) .> 0.33))
	md"### Load mask"
end

# ╔═╡ bf6b94ea-4caa-419f-a166-ffeb9d311a9e
begin
	function Colors.XYZ(lf::LightField)
		colors = [ colormatch(to_nm(λ)) for λ in lf.λ ]
		planes = [ (real(AFArray(ComplexF32.(ϕ)))) for ϕ in lf.ϕ ]
		return sum([c.*Array(p/maximum(p)) for (c,p) in zip(colors, planes)])
	end

	Colors.RGB(lf::LightField) = Colors.RGB.(XYZ(lf))
	Colors.HSV(lf::LightField) = Colors.HSV.(XYZ(lf))
	
	Colors.HSV(f::Matrix{T} where {T<:Number}) = ComplexToHSV.(f)
	Colors.HSV(af::AFMatrix{T} where {T<:Number}) = ComplexToHSV.(Array(af))
	Colors.HSV(f::PhasorField) = ComplexToHSV.(f.ϕ)
	Colors.HSV(f::Array{T,3} where {T<:Number}) = ComplexToHSV.(hcat([f[:,:,i] for i ∈ 1:size(f, 3)]...))
end

# ╔═╡ 60218002-f04c-4b35-8d72-7228338a665a
begin
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
	
	md"## Conversion of RGB and ``M\times{N}\times{3}`` arrays"
end

# ╔═╡ b6dfbf4a-148f-43d6-96b8-52da7802b4af
begin
	# p = plot([])
	anim = @animate for i ∈ 1:length(cshots)
		plot([HSV(γ_cshots[i]) HSV(cshots[i])], legend=false, xaxis=false, yaxis=false, xticks=false, yticks=false, size=(2N,N))
		annotate!((0,0, (repr(i), :white, :top, :left)))
		# HSV(cshots[i])
	end
	ganim = gif(anim)
end;

# ╔═╡ 5c00adf5-7148-4a31-b667-28ce74105cb1
ganim

# ╔═╡ bc851704-6b05-4398-8152-2955fed0a704
begin
	PhasorField([0])
	
	### Extensions to show objects visually
	
	# Base.show(io, mime::MIME"image/html", f::RGBComplexField) =
	# 	show(io, mime, md"""
	# 	$(summary(f))
	# 	$(htl"<p>")
	# 	$(ComplexToHSV.([f.R f.G f.B]))
	# 	""")

	# 	Base.show(io, mime::MIME"image/png", f::RGBComplexField) =
	# 		show(io, mime, ComplexToHSV.([f.R f.G f.B]))

	Base.show(io, mime::MIME"image/png", f::Matrix{T} where {T <: Complex}) =
		show(io, mime, ComplexToHSV.(f))

	Base.show(io, mime::MIME"image/png", f::PhasorField) =
		show(io, mime, f.ϕ)

	Base.show(io, mime::MIME"image/png", f::Array{T,3} where {T <: Complex}) =
		show(io, mime, ComplexToHSV.(hcat([f[:,:,i] for i ∈ 1:size(f, 3)]...)))

	function Base.show(io, mime::MIME"image/png", lf::LightField)
		colors = [ colormatch(to_nm(λ)) for λ in lf.λ ]
		planes = [ (real(AFArray(ComplexF32.(ϕ)))) for ϕ in lf.ϕ ]

		show(io, mime, sum([c.*Array(p/maximum(p)) for (c,p) in zip(colors, planes)]))

		# scales = [ StatsBase.percentile(p[:], 99) for p in planes ]
		# ys = getfield.(colors, :y)
		# sum([c.*p./s for (s,c,p) in zip(scales, colors, planes)])./sum(ys)
		# sum([c.*normalize(p) for (c,p) in zip(colors, planes)])./sum(ys)
		# sum([c.*p./s for (s,c,p) in zip(scales, colors, planes)])./sum(ys)
		# sum([c.*normalize(p) for (s,c,p) in zip(scales, colors, planes)])./sum(ys)
		# sum([c.*normalize(p) for (c,p) in zip(colors, planes)])./sum(ys)
	end
	
	# function Base.show(io, mime::MIME"image/png", lf::LightField)
	# 	planes = [ colormatch(to_nm(λ)) .* abs.(ϕ) for (λ, ϕ) in zip(lf.λ, lf.ϕ) ]
	# 	s = sum(planes)
	# 	y_max = max(1, maximum(getfield.(s, :y)))
	# 	show(io, mime, s./y_max)
	# end
	
	initialized = true

	md"## Visualization of `PhasorField`s and `LightField`s"
end

# ╔═╡ 11725909-3a35-485b-8295-098917ef4c92
begin
	if initialized 			# ensure packages have been loaded and core methods defined
		# wavelengths to be used for three-color imaging
		# λR, λG, λB = 640.0nm, 532.8nm, 460.0nm
		λR, λG, λB = 638.0nm, 527.0nm, 477.0nm  # wavelengths from a scanning laser projector
		λG = (λR + λB)/2
		
		# wavenumbers corresponding to colors
		kR, kG, kB = 2π ./ (λR, λG, λB)

		# definition of default diffraction slice used in wave propagation
		L1 = 2mm					# diffraction slice side length (L1 × L1)
		# N = 2048					# number of samples along each slice side (N × N)

		# BOE parameters from WaveOptics.jl
		dₒₘ = 340.0mm 					# object to mask distance
		dₘₗ = 2.0mm 					# mask to lens distance
		rₐ  = 0.76mm 					# aperture radius (diam 1.52 mm)
		f₀  = 3.04mm 					# lens focal length
		dₗᵩ = dₘₗ 						# lens to corrector distance
		dₗₛ = 1/(1/f₀ - 1/(dₒₘ+dₘₗ))	# lens to sensor distance, calculated
		dᵩₛ = dₗₛ - dₗᵩ 				# corrector to sensor distance
	end
	md"## Optical system and visualization parameters"
end

# ╔═╡ 81c811fa-77d6-11eb-317b-654187ffcd48
begin
	function testobject(img, N)
		img = RGB.(imrotate(img, π))
		P = maximum(size(img)) ÷ 4
		src = padarray(img, Fill(0, (P,P), (P,P)))
		ϕᵣ = exp.(2π * 1im * randomize_phase * rand(N,N,3))
		chart = Float32.(MxNx3(imresize(src, N, N))) .* ϕᵣ
	end

	test_color  = testobject(testimage("resolution_test_512"), N)
	# test_color = testobject(load("color_reschart01.png")[55:1055,250:1250], N)
	
	test_lf = LightField([λR, λG, λB], [test_color[:,:,i] for i ∈ 1:3])
	
	md"""
	| `test_lf` | `abs2(test_lf)` |
	| :-: | :-: |
	| $(test_lf) | $(abs2(test_lf)) |
	"""
end

# ╔═╡ 0f21175d-d4d8-418a-a038-91a4cd6fab39
let
	# showfield(x) = ComplexToHSV(x)
	# showfield(x::LightField) = x
	# showfield(x::PhasorField) = x
	
	initial = test_lf
	L       = 1mm * propL
	scale   = 1mm
	dist 	= scale*propdist
	
	# output = cshots[end]
	forward  = propagate(initial, dist, L; prop=propfn)
	backward = propagate(forward, -dist, L; prop=propfn)

	# difference = normalize(backward) - normalize(initial) #abs2(normalize(initial)) - abs2(normalize(backward))
	# difference = (backward - initial)
	
	# ComplexF32.([initial forward; backward difference])
	# ComplexToHSV.(normalize(initial))
	md"""
	| Initial light field | Forward to $(dist) | Backward to 0 mm |
	| :-: | :-: | :-: |
	| $(abs2(initial)) | $(abs2(forward)) | $(abs2(backward)) |
	| | pixel pitch: $(uconvert(u"µm", propL*1mm/N)) | |
	"""
end

# ╔═╡ bc55d354-8ee0-4fe1-92b7-967cdb51dc2e
begin
	# calculate sampling coordinates for the default diffraction slice
	# xs, ys are ranges of coordinates
	# xs = ((-N/2):1:(N/2-1)).*(2mm)/N
	xs = [((-N/2):1:(N/2-1))...] .* L1/N
	# xs = -1.0mm:1µm:1mm
	ys = xs

	# xA, yA are matrices of coordinate ranges for fast evaluation
	yA = repeat(ys, 1, length(xs))
	xA = repeat(xs', length(ys), 1)
end;

# ╔═╡ 16253161-0e9c-4b5d-bf81-0dd2a35812a8
begin
	# define the object field for a point
	obj_point = let
		if PSF_source_impulse
			z = zeros(ComplexF32, N, N)
			z[N÷2,N÷2] = 1
		else
			z = gaussian((N,N), 0.0005) # .* exp.(2π*im*rand(N,N))
		end
		if PSF_source_RGB == "RGB"
			LightField([λR, λG, λB], [z, z, z])
		elseif PSF_source_RGB == "R"
			LightField([λR], [z])
		elseif PSF_source_RGB == "G"
			LightField([λG], [z])
		elseif PSF_source_RGB == "B"
			LightField([λB], [z])
		end
	end

	# obj = LightField([λG], [objmono[:,:,1]])
	object = obj_point
	
	md"### Define point source (for PSF calculation)"
end

# ╔═╡ abb11bb2-876a-49b3-866c-4b3b9e8fc7f5
md"""
$(html"<center><b>")
### Table of simulation parameters
$(html"</b></center>")
| Parameter | Value | Comments |
| :-: | :-: | :-- |
| ``λ_R`` | $λR | wavelength of red light |
| ``λ_G`` | $λG | wavelength of green light |
| ``λ_B`` | $λB | wavelength of blue light |
| ``k_R/2π`` | $(round(typeof(1.0u"µm^-1"), kR/2π, sigdigits=4)) | wavenumber of red light |
| ``k_G/2π`` | $(round(typeof(1.0u"µm^-1"), kG/2π, sigdigits=4)) | wavenumber of green light |
| ``k_B/2π`` | $(round(typeof(1.0u"µm^-1"), kB/2π, sigdigits=4)) | wavenumber of blue light |
| ``d_{om}`` | $dₒₘ | object to mask distance |
| ``d_{ml}`` | $dₘₗ | mask to lens distance |
| ``r_a``| $rₐ | aperture radius (diam $(2rₐ)) |
| ``f_0``| $f₀ | lens focal length |
| ``d_{ls}``| $(round(typeof(1.0u"mm"), dₗₛ, sigdigits=3)) | lens to sensor distance, calculated |
| ``d_{l\Phi}``| $(round(typeof(1.0u"mm"), dₗᵩ, sigdigits=3)) | lens to corrector distance, calculated |
| ``d_{{\Phi}s}``| $(round(typeof(1.0u"mm"), dᵩₛ, sigdigits=3)) | corrector to sensor distance, calculated |

"""

# ╔═╡ 2bf78920-2e25-4b42-823c-2874a4d8c3cb
# convolve with spherical kernel to propagate distance z₁
# sphericalkernelG = acc_spherical_wavefront(xA, yA, z₁, kG)
# ϕ_into_lens = acc_convsame(obj.ϕ[1], sphericalkernelG)
ϕ_into_mask = propagate(object, dₒₘ, L1, prop=propfn);

# ╔═╡ 5f80f6de-6041-456d-a2a6-7ce741779691
# modulate by mask transfer function
ϕ_outof_mask = ϕ_into_mask * mask;

# ╔═╡ 0cf2d97d-9ad0-40a8-8807-8e3cccaa25db
md"""
| ``~~~~~~~~~~~~~~~~`` | in | modulation | out |
| --: | :-: | :-: | :-: |
| mask | $((ϕ_into_mask)) | $((mask)) | $((ϕ_outof_mask)) |
"""

# ╔═╡ 01a1aeb2-b136-49de-a48f-fc7a7a3b143a
# ϕ_into_lens = ϕ_outof_mask;
ϕ_into_lens = propagate(ϕ_outof_mask, dₘₗ, L1, prop=propfn);

# ╔═╡ 6c42ea7c-d1ed-445c-bb6c-0c23f1a63dab
begin
#=
	mutable struct Vec3{T<:Real} <: Number
		x::T
		y::T
		z::T
	end

	Vec3() = Vec3(0,0,0)
	# Vec3(x,y,z) = (x,y,z)

	Base.:+(v::Vec3, w::Vec3) = Vec3(v.x+w.x, v.y+w.y, v.z+w.z)
	Base.:-(v::Vec3, w::Vec3) = Vec3(v.x+w.x, v.y+w.y, v.z+w.z)
	Base.:*(c::Number, w::Vec3) = Vec3(c*w.x, c*w.y, c*w.z)
	Base.:/(v::Vec3, c::Number) = Vec3(v.x/c, v.y/c, v.z/c)

	# abstract type Point <: Vec3 end

	Base.abs(v::Vec3) = sqrt(abs2(v))
	Base.abs2(v::Vec3) = v.x^2 + v.y^2 + v.z^2

	Base.conj(v::Vec3) = v

	struct Plane
		origin::Vec3
		û::Vec3
		v̂::Vec3
	end

	Plane() = Plane(
		Vec3(0,0,0),
		Vec3(1,0,0), Vec3(0,1,0)
	)

	struct Grid
		plane::Plane
		Δu::Vec3
		Δv::Vec3
		M::Integer
		N::Integer
	end

	Grid() = Grid(Plane(), Vec3(1,0,0), Vec3(0,1,0), 0, 0)

	Grid(dx::Number, dy::Number, N::Integer, M::Integer) =
		Grid(Plane(), dx*Vec3(1,0,0), dy*Vec3(0,1,0), M, N)

	struct Propagation
		input::Plane
		output::Plane
		r::Vec3
	end
	
	Base.show(io::IO, v::Vec3) =
		print(IOContext(io, :compact=>true), "Vec3($(v.x), $(v.y), $(v.z))")

	Base.show(io::IOContext, g::Grid) =
		print(IOContext(io, :compact=>true),
			"Grid(origin=$(g.plane.origin), $(N)×$(M), Δu=$(g.Δu), Δu=$(g.Δu))")
	
	function reify(g::Grid)
		_x = collect(1-g.N/2:1:g.N/2) .* g.Δu .+ g.plane.origin
		_y = collect(1-g.M/2:1:g.M/2) .* g.Δv .+ g.plane.origin  # was negative
		y, x = meshgrid(_x, _y) #, indexing = "xy")
		return x, y
	end
	
	function getxy(g::Grid)
		_x = collect(1-g.N/2:1:g.N/2) .* abs(g.Δu) .+ g.plane.origin.x
		_y = collect(1-g.M/2:1:g.M/2) .* abs(g.Δv) .+ g.plane.origin.y  # was negative
		y, x = meshgrid(_x, _y) #, indexing = "xy")
		return x, y
	end
=#
	md"## Vec3, Plane, Grid, Propagation"
end

# ╔═╡ 449a1328-e17d-4d1a-9a85-384d4fe801b4
begin
	spherical_wavefront(x, y, d, k) =
		exp.(1.0im*k*sqrt.(x.^2 + y.^2 .+ d^2))

	thin_lens(x, y, f, k) =
		exp.(1im*k * (f .- sqrt(x.^2 + y.^2 .+ f^2)))
	
	fresnel_kernel(x,y,L,k) =
		exp.(1im*(k/(2*L))*(x.^2 + y.^2)) # * exp(1im*k*L) / (1im*(2π/k)*L)
	
	fresnel_kernel_unapprox(x,y,z,k) =
		exp.(1im*k*sqrt.(x.^2 + y.^2 .+ z.^2)) # .* exp.(1im*k*z) ./ (1im*(2π/k).*z)
	
	function convsame(A,k)
		central_region = map((axis,n)->axis.+(n÷2), axes(A), size(k))
		return conv(A, k)[central_region...]
	end

	md"""
	## Primitives to create complex fields

	For reference, the Fresnel propagation (approximation) kernel is
	``$h(x, y, z) = \frac{e^{ikz}}{i \lambda z} e^{i \frac{k}{2z} \left(x^2 + y^2\right)}$``
	"""
end

# ╔═╡ 81d2d4d8-489f-4cb3-8bbf-387e9a577148
begin
	function acc_spherical_wavefront(x, y, d, k)
		k1 = ComplexF32(ustrip(upreferred(1im*k)))
		xf = AFArray(Float32.(ustrip(upreferred.(x))))
		yf = AFArray(Float32.(ustrip(upreferred.(y))))
		rf = xf.*xf + yf.*yf + Float32(ustrip(upreferred(d^2)))
		sf = sqrt(rf)
		Array(exp(k1*sf))
	end

	function acc_thin_lens(x, y, f, k)
		k1 = ComplexF32(ustrip(upreferred(1im*k)))
		xf = AFArray(Float32.(ustrip(upreferred.(x))))
		yf = AFArray(Float32.(ustrip(upreferred.(y))))
		f1 = Float32(ustrip(upreferred(f)))
		rf = xf.*xf + yf.*yf + f1^2
		sf = f1 .- sqrt(rf)
		Array(exp(k1*sf))
	end
	
	function acc_fresnel_kernel(x,y,d,k)
		c1 = ComplexF32(ustrip(upreferred(1im*(k/(2*d)))))
		xf = AFArray(Float32.(ustrip(upreferred.(x))))
		yf = AFArray(Float32.(ustrip(upreferred.(y))))
		Array(exp(c1 * (xf.*xf + yf.*yf)))
	end

	function acc_convsame(A,k)
		return Array(af_conv(
				AFArray{ComplexF32}(ComplexF32.(A)),
				AFArray{ComplexF32}(ComplexF32.(k)),
				expand=false, inplace=true))
	end

	md"""
	### Accelerated equivalents (using ArrayFire)
	"""
end

# ╔═╡ 121dae3d-6731-4207-bb51-e9e79f0d93f8
ϕ_lens = acc_thin_lens(xA,yA,f₀,2π/λG);

# ╔═╡ 173bbd6a-16eb-473a-8aaa-5efb92150124
# modulate by lens transfer function
ϕ_outof_lens = ϕ_into_lens * PhasorField(ϕ_lens);

# ╔═╡ 79bdf5b6-76dd-40ea-a713-ac394ca53b4c
md"""
| ``~~~~~~~~~~~~~~~~`` | in | modulation | out |
| --: | :-: | :-: | :-: |
| lens | $((ϕ_into_lens)) | $((ϕ_lens)) | $((ϕ_outof_lens)) |
"""

# ╔═╡ 0ce01c4b-fe97-4208-995a-beb2f8e98e23
# propagate distance L to image place
ϕ_image = propagate(ϕ_outof_lens, dₗₛ, L1, prop=propfn);

# ╔═╡ b034e3e2-4b52-4655-ac7c-756c0f45da12
# LightField([λG], [ϕ_image.ϕ])
psf_amplitude = ϕ_image;

# ╔═╡ 64c5375b-0bab-45c9-bdaf-223a7b77ede2
md"""
| ``~~~~~~~~~~~~~~~~`` | `object` | `psf_amplitude` | `psf` |  |
| --: | :-: | :-: | :-: | :-: |
| | $(object) | $(psf_amplitude) | $(abs2(ϕ_image)^0.2) | |
"""

# ╔═╡ 4d071a23-a75b-4415-8903-77ee4bec3dd0
begin
	psf = (abs2.(psf_amplitude.ϕ[1]));
	psf /= sum(psf);
end;

# ╔═╡ 0c72b231-1bbe-4066-bd64-5f5d963d1d98
let
	out = abs2(propagate(ϕ_outof_lens, psf_prop_dist*dₗₛ, L1, prop=propfn))
	
	function cross_section(A); center = findmax(A);	return A[center[2][1],:]; end

	p = plot([cross_section(abs.(x))./sqrt(sum(abs2.(x))) for x ∈ out.ϕ],
		size=(320,320),  legend=false, color=[:red :green :blue], ylims=(10^-6, 1))
	

#	| ``$ \sum_{\phi~ \in~ PSF} \phi $`` | ``\Vert PSF \Vert ^2`` |
#	| $(normalize(sum(psf_amplitude.ϕ))) | $(cn(psf, percentile=99.9)) |

	md"""
	| PSF out | cross_section |
	| :-: | :-: |
	| $(resample(out, (310,310))) | $p |
	"""
end

# ╔═╡ a9c30e06-a931-4dfe-90ab-bacd5d532159
begin
	#=
	# Explicit RGB waveoptics simulation

	# Create point source wave fronts at distance $z_1$:

	ϕₛ = let
		ϕR = acc_spherical_wavefront(xA,yA,z₁,kR)
		ϕG = acc_spherical_wavefront(xA,yA,z₁,kG)
		ϕB = acc_spherical_wavefront(xA,yA,z₁,kB)
		LightField([λR, λG, λB], [ϕR, ϕG, ϕB])
	end

	# Convolve the object with the point source wavefronts,

	oR = acc_convsame(ϕₛ.ϕ[1], object[:,:,1])
	oG = acc_convsame(ϕₛ.ϕ[2], object[:,:,2])
	oB = acc_convsame(ϕₛ.ϕ[3], object[:,:,3])
	lf = cat(oR,oG,oB, dims=3)

	# Calculate thin lens phase maps for each wavelength.

	lR = acc_thin_lens(xA,yA,f₀,kR)
	lG = acc_thin_lens(xA,yA,f₀,kG)
	lB = acc_thin_lens(xA,yA,f₀,kB)
	# lR = [thin_lens(x,y,f₀,kR) for x ∈ xs, y ∈ ys]
	# lG = [thin_lens(x,y,f₀,kG) for x ∈ xs, y ∈ ys]
	# lB = [thin_lens(x,y,f₀,kB) for x ∈ xs, y ∈ ys]
	l_all = cat(lR, lG, lB, dims=3)

	# Combine the monochromatic lens phase maps into a composite multi-wavelength phase map.

	# lC = lG
	# lC = [l_all[i,j,rand(1:3)] for i in axes(lR)[1], j in axes(lR)[2]]
	lC = lR + lG + lB;

	# Modulate the object waves by the lens phase map.

	fR = oR .* lC
	fG = oG .* lC
	fB = oB .* lC

	# Calculate Fresnel kernels to propagate the wavefronts from the lens to the image plane.

	pR = acc_fresnel_kernel(xA,yA,L,kR)
	pG = acc_fresnel_kernel(xA,yA,L,kG)
	pB = acc_fresnel_kernel(xA,yA,L,kB)

	# Convolve each wavefront with its corresponding propagation kernel.

	iR = acc_convsame(fR, pR)
	iG = acc_convsame(fG, pG)
	iB = acc_convsame(fB, pB)
	output = cat(iR, iG, iB, dims=3);

	let
		imgs = mosaicview(ncol=2, imrotate(RGB(abs2.(object)), π), RGB(normalize(abs2.(output), percentile=99).^(γ^-1)))

		md"""
		## Image at focal plane
		$(html"<figure>")
		$(imgs)
		$(html"<figcaption>")
		Intensity at object plane (left) and focal plane (right, gamma = $(γ^-1)). 
		$(html"</figcaption>")
		$(html"</figure>")
		"""
	end

	md"""
	``x_0`` $(@bind xo Slider(-10:0.1:10, default=0, show_value=true))

	``y_0`` $(@bind yo Slider(-10:0.1:10, default=0, show_value=true))

	``z_0`` $(@bind zo  Slider(0:1:100, default=20, show_value=true))

	``\gamma^{-1}`` $(@bind γ Slider(0.1:0.1:10.0, show_value=true, default=1.0))
	"""

	x₀,y₀ = xo*1mm, yo*1mm; #, zo*1mm;
	=#

	md"""
	!!! note "Expand this cell to see the obsolete waveoptics simulation code"
	"""

	md"## Obsolete RGB waveoptics (for reference)"
end

# ╔═╡ 6ca9a99a-8f25-47ec-bce5-3f847570879c
md"""
## Mapping wavelengths to XYZ colorspace
"""

# ╔═╡ 7e003a22-ed86-4e13-8a52-66609a7e8c15
md"""
!!! note

    Wavelengths are mapped to colors in XYZ space and thence to RGB for display. See 

| Red | Green | Blue |
| :--: | :--: | :--: |
| $(RGB(colormatch(to_nm(λR)))) | $(RGB(colormatch(to_nm(λG)))) | $(RGB(colormatch(to_nm(λB)))) |
| $(λR) | $(λG) | $(λB) |

!!! note 

    See `Base.show(::LightField, ...)` methods defined above for details on how `LightField` objects are displayed using this mapping.

"""

# ╔═╡ 7628b409-86e2-41d6-ab82-62175eabaf49
colormatch.(CIE2006_10_CMF, to_nm.((400:5:700)*nm))

# ╔═╡ 47dde459-4cb4-4bf5-a4df-6c54b545d07c
let
	conversions = [
		:CIE1931_CMF, :CIE1931J_CMF, :CIE1931JV_CMF,
		:CIE1964_CMF, :CIE2006_2_CMF, :CIE2006_10_CMF
	]
	spectrum = colormatch.(CIE2006_10_CMF, to_nm.((400:5:700)*nm))
	wl = 400:700
	plots = []
	for C in conversions
		colors = colormatch.(eval(C), wl)
		y = [q.y for q ∈ colors]
		p = plot(wl, y, title=String(C), color=colors, width=10)
		push!(plots, p)
	end
	out = plot(layout=@layout[a b; c d; e f], plots..., legend=false)
end

# ╔═╡ 5992a716-65e6-4d55-981e-efbe88ccf8ba
md"""
---
---
"""

# ╔═╡ 91c66b4d-029d-45d9-a992-1a05db6ae0ac
md"""
# Scratchpad area
"""

# ╔═╡ a72c6eba-4c1e-44f0-b9c2-c9bfabd43106
"""
    documentation_markdown_examples(x[, y])

Compute the Foo index between `x` and `y`.

If `y` is unspecified, compute the Bar index between all pairs of columns of `x`.

# Arguments
- `n::Integer`: the number of elements to compute.
- `dim::Integer=1`: the dimensions along which to perform the computation.

# Examples
```julia-repl
julia> foo([1, 2], [1, 2])
1
```

Some nice documentation here.

# Examples
```jldoctest
julia> a = [1 2; 3 4]
2×2 Array{Int64,2}:
 1  2
 3  4
```

See also: [`bar!`](@ref), [`baz`](@ref), [`baaz`](@ref)
"""
function documentation_markdown_examples()
end

# ╔═╡ 3c68a8ec-4ffd-47fc-a9dc-3f2af9b89d07
module Voelz

	# meshgrid(n,m) = (0collect(m) .+ n', m .+ 0n')

	#=
	#
	# Adapted from
	# David George Voelz - Computational Fourier Optics, a MATLAB tutorial
	# (SPIE Tutorial Texts Vol. TT89)-SPIE Press (2010)
	#
	=#

	################

	"""
	circle function

	evaluates circ(r)
	note: returns odd number of samples for diameter
	"""
	function circ(r)
		return abs.(r) .<= 1;
	end

	"""
	jinc function

	evaluates J1(2*pi*x)/x
	with divide by zero fix
	"""
	function jinc(x)
		# locate non-zero elements of x
		mask = (x.!=0);
		# initialize output with pi (value for x=0)
		out=pi*ones(size(x));
		# compute output values for all other x
		out[mask] = besselj.(1,2*pi*x[mask])./(x[mask]);
		return out
	end

	################


	"""
	rectangle function

	evaluates rect(x)
	note: returns odd number of samples for full width
	"""
	function rect(x)
		out = abs(x) .<= 1/2;
		return out
	end
	"""
	triangle function

	evaluates tri(x)
	"""
	function tri(x)
		# create lines
		t = 1 .- abs.(x);
		# keep lines for |x|<=1, out=0 otherwise
		mask = abs.(x) .<= 1;
		out = t.*mask;
		return out
	end

	################

	"""
	unit sample “comb” function

	sequence of unit values for x=integer value
	round is used to truncate roundoff error
	"""
	function ucomb(x)
		x=round(x*10^6)/10^6;   #round to 10^6ths place
		out=rem(x,1)==0;        #place 1 in out where rem = 0
		return out
	end

	################


	"""
	unit sample “delta” function

	unit value for x=0
	round is used to truncate roundoff error
	"""
	function udelta(x)
		x=round(x*10^6)/10^6;  #round to 10^6ths place
		out=x==0;              #place 1 in out where x = 0
		return out
	end

	################
#=

	"""
	jinc function

	J1(2*pi*x)/x -- divide by zero fix

	locate non-zero elements of x
	"""
	function jinc(x)
		mask=(x~=0);
		# initialize output with pi (value for x=0)
		out=pi*ones(size(x));
		# compute output values for all other x
		out(mask)=besselj(1,2*pi*x(mask))./(x(mask));
		return out
	end


	"""
	tilt phasefront
	uniform sampling assumed
	uin - input field
	L - side length
	lambda - wavelength
	alpha - tilt angle
	theta - rotation angle (x axis 0)
	uout - output field
	"""
	function tilt(uin,L,lambda,alpha,theta)
		[M,N]=size(uin);        #get input field array size
		dx=L/M;                 #sample interval
		k=2*pi/lambda;          #wavenumber

		x=-L/2:dx:L/2-dx;       #coords
		[X,Y]=meshgrid(x,x);

		uout=uin.*exp(j*k*(X*cos(theta)+Y*sin(theta))*tan(alpha));       #apply tilt
		return uout
	end

	################

	"""
	converging or diverging phase-front
	uniform sampling assumed
	uin - input field
	L - side length
	lambda - wavelength
	zf - focal distance (+ converge, - diverge)
	uout - output field
	"""
	function focus(uin,L,lambda,zf)
		[M,N]=size(uin);        #get input field array size
		dx=L/M;                 #sample interval
		k=2*pi/lambda;          #wavenumber
		#
		x=-L/2:dx:L/2-dx;       #coords
		[X,Y]=meshgrid(x,x);

		uout=uin.*exp(-j*k/(2*zf)*(X.^2+Y.^2)); #apply focus
		return uout
	end
=#

	################

	"""
	seidel_5
	Compute wavefront OPD for first 5 Seidel wavefront
	aberration coefficients + defocus


	u0,v0 - normalized image plane coordinate
	X,Y - normalized pupil coordinate arrays
			(like from meshgrid)
	wd-defocus; w040-spherical; w131-coma;
	w222-astigmatism; w220-field curvature;
	w311-distortion
	"""
	function seidel_5(u0,v0,X,Y,wd,w040,w131,w222,w220,w311)

		beta=atan2(v0,u0);     # image rotation angle
		u0r=sqrt(u0^2+v0^2);   # image height

		# rotate grid
		Xr=X*cos(beta)+Y*sin(beta);
		Yr=-X*sin(beta)+Y*cos(beta);

		# Seidel polynomials
		rho2=Xr.^2+Yr.^2;
	w=wd*rho2+w040*rho2.^2+w131*u0r*rho2.*Xr+w222*u0r^2*Xr.^2+w220*u0r^2*rho2+w311*u0r^3*Xr
		return w
	end
end

# ╔═╡ c6932382-5ac5-4d5a-af59-3c22141ac2ea
begin
	g_s = @bind g Slider(-1.0:0.05:1.0, default=0, show_value=true)
	md"``g`` $g_s"
end

# ╔═╡ dc401f46-4f9b-4679-84eb-860c3c11b82c
begin
	function z(x,y,g)
		f1,f2 = (-2/(1-g), 2/(1+g))
		1/hypot(f1-x, y) + 1/hypot(f2-x, y)
	end

	ix = -10:0.02:10
	iy = ix
	mx,my = meshgrid(ix,iy)

	# surface(ix, iy, z.(mx,my,g), seriescolor=:rainbow, zaxis=:log10)
	surface(ix, iy, log10.(z.(mx,my,g)), seriescolor=:rainbow)
	# plot!(zaxis=(:log10,))
end

# ╔═╡ bf8befeb-0a82-4722-b76a-f912cead0e7d
[-2/(1-g), 2/(1+g)]

# ╔═╡ b6b10e8e-059f-4e20-927e-f9ffcacd5516
let
	books = [
     (name="Who Gets What & Why", year=2012, authors=["Alvin Roth"]),
     (name="Switch", year=2010, authors=["Chip Heath", "Dan Heath"]),
     (name="Governing The Commons", year=1990, authors=["Elinor Ostrom"])]

    render_row(book) = @htl("""
      <tr><td>$(book.name) ($(book.year))<td>$(join(book.authors, " & "))
    """)

    render_table(list) = @htl("""
      <table><caption><h3>Selected Books</h3></caption>
      <thead><tr><th>Book<th>Authors<tbody>
      $((render_row(b) for b in list))</tbody></table>""")

    render_table(books)
    #=>
    <table><caption><h3>Selected Books</h3></caption>
    <thead><tr><th>Book<th>Authors<tbody>
      <tr><td>Who Gets What &amp; Why (2012)<td>Alvin Roth
      <tr><td>Switch (2010)<td>Chip Heath &amp; Dan Heath
      <tr><td>Governing The Commons (1990)<td>Elinor Ostrom
    </tbody></table>
    =#
end

# ╔═╡ d13dc80d-7c2f-4642-9569-8ada8e3c769d
# blart=abs2(propagate(ϕ_from_sensor, dᵩₛ, L1, prop=propfn));

# ╔═╡ 026fb497-dbed-4dec-9e9d-4f8dc7f88409
# cleanup(blart; percentile=100)

# ╔═╡ 1a8c1acc-eeac-42ce-a933-2d50d89804bd
# (lf->LightField(lf.λ, [normalize(ϕ; percentile=1) for ϕ ∈ lf.ϕ]))(abs2(blart))

# ╔═╡ 0d617142-237e-47be-852e-fe7fab7eeed0
# normalize(abs2(blart), percentile=50)

# ╔═╡ 3413c40e-d3dc-478b-bd08-40accb34e86e
# typeof(blart.ϕ[1])

# ╔═╡ 2ed6f4cd-5062-47a7-a429-8fb976bac7a4
# cleanup(lf::LightField; args...) = LightField(lf.λ, [normalize(ϕ; args...) for ϕ ∈ lf.ϕ])

# ╔═╡ 4e5d95e5-e895-484c-8def-51d4f38b3103
# let
# 	foo(x, args...; kwargs...) = [x, args, kwargs]
# 	foo(0, 1, j=2, 3, bar=4, baz=5)
# end

# ╔═╡ 51cdbd12-38ea-44ff-a5cd-12f88b664a13
md"""
### Benchmarking ArrayFire code
"""

# ╔═╡ deca9332-8df0-4cf3-bb22-9db514a364a8
function fc(;N=1024, L=1f-3)
	i = Float32.(collect((-(N-1)/2):((N-1)/2)))
	a = (i.*L/N)
	x = 0a .+  a'
	y =  a .+ 0a'
	z = L+L
	d = sqrt.(x.*x + y.*y .+ z*z)
	λ = 500f-9
	ϕ = 2f0π*im*d/λ
	exp.(ϕ)
end

# ╔═╡ ff04ec0b-4ba4-4b14-9f31-e753c9456a45
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
function fg(;N=1024, L=1f-3)
	i = Float32.(collect((-(N-1)/2):((N-1)/2)))
	a = AFArray(i.*L/N)
	x = 0a +  a'
	y =  a + 0a'
	z = L+L
	d = sqrt.(x.*x + y.*y + z*z)
	λ = 500f-9
	ϕ = 2f0π*im*d/λ
	exp.(ϕ)
end
  ╠═╡ =#

# ╔═╡ 0de3996e-1604-44bc-b16f-ebf638b1250b
function fg(;N=1024, L=1f-3)
	i = Float32.(collect((-(N-1)/2):((N-1)/2))) * L/N
	a = AFArray(i)
	b = AFArray(i)'
	x = 0*a +   b
	y =   a + 0*b
	z = L+L
	d = sqrt.(x.*x + y.*y + z*z)
	λ = 500f-9
	ϕ = 2f0π*im*d/λ
	exp.(ϕ)
end

# ╔═╡ 7004ea3e-7e0b-47fa-b5d1-e004b72919ec
a = AFArray(collect(1:10))

# ╔═╡ ee501cd2-5994-4c21-b2f6-7f5ae5085cf6
a, a', a + 0a', 0a + a'

# ╔═╡ df92f9a8-3296-4613-8ec8-aa83894c41c3
x = 0a + a'

# ╔═╡ 7789a11d-8e19-4988-962c-a273a12c916b
y = a + 0a'

# ╔═╡ b5dfef37-0aaf-4fd1-8c4e-f629216a6f27
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
@benchmark fc()
  ╠═╡ =#

# ╔═╡ 7f37b5d1-ae65-41e3-b9de-9bacf73005d3
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
@benchmark Array(sync(fg()))
  ╠═╡ =#

# ╔═╡ 005d09bd-5f61-4b3c-8531-0080d92661ca
# ╠═╡ skip_as_script = true
#=╠═╡
fc()
  ╠═╡ =#

# ╔═╡ 34227e32-ca2d-4099-8f52-f7842491c0a5
# ╠═╡ skip_as_script = true
#=╠═╡
extrema(abs.(Array(fg()) - fc())[:])
  ╠═╡ =#

# ╔═╡ 9dfa5cf9-ce6e-4578-8a8c-df6bdeaafe0f
# ╠═╡ skip_as_script = true
#=╠═╡
Array(fg())
  ╠═╡ =#

# ╔═╡ 34dfa9e2-528a-443e-80d5-39ee2050089a
# ╠═╡ skip_as_script = true
#=╠═╡
typeof(fg())
  ╠═╡ =#

# ╔═╡ 9f7c161f-185d-4c10-88a5-e781ef06ba05
# ╠═╡ skip_as_script = true
#=╠═╡
HSV(fg())
  ╠═╡ =#

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
ArrayFire = "b19378d9-d87a-599a-927f-45f220a2c452"
Base64 = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"
BenchmarkTools = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"
Colors = "5ae59095-9a9b-59fe-a467-6f913c188581"
DSP = "717857b8-e6f2-59f4-9121-6e50c889abd2"
FFTW = "7a1cc6ca-52ef-59f5-83cd-3a7055c09341"
FileIO = "5789e2e9-d7fb-5bc7-8068-2c6fae9b9549"
FourierTools = "b18b359b-aebc-45ac-a139-9c0ccbb2871e"
HTTP = "cd3eb016-35fb-5094-929b-558a96fad6f3"
HypertextLiteral = "ac1192a8-f4b3-4bfe-ba22-af5b92cd3ab2"
ImageIO = "82e4d734-157c-48bb-816b-45c225c6df19"
ImageShow = "4e3cecfd-b093-5904-9786-8bbb286a6a31"
Images = "916415d5-f1e6-5110-898d-aaa5f9f070e0"
JSON = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
JpegTurbo = "b835a17e-a41a-41e7-81f0-2f016b05efe0"
LazyGrids = "7031d0ef-c40d-4431-b2f8-61a8d2f650db"
Libdl = "8f399da3-3557-5675-b5ff-fb832c97cbdb"
LinearAlgebra = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"
MosaicViews = "e94cdb99-869f-56ef-bcf0-1ae2bcbe0389"
PlotlyJS = "f0f68f2c-4968-5e81-91da-67840de0976a"
Plots = "91a5bcdd-55d7-5caf-9e0b-520d859cae80"
PlutoTeachingTools = "661c6b06-c737-4d37-b85c-46df65de6f69"
PlutoUI = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
ProgressLogging = "33c8b6b6-d38a-422a-b730-caa89a2f386c"
QuartzImageIO = "dca85d43-d64c-5e67-8c65-017450d5d020"
Statistics = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"
StatsBase = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"
TestImages = "5e47fb64-e119-507b-a336-dd2b206d9990"
TimerOutputs = "a759f4b9-e2f1-59dc-863e-4aeb61b1ea8f"
Unitful = "1986cc42-f94f-5a68-af5c-568840ba703d"

[compat]
ArrayFire = "~1.0.7"
BenchmarkTools = "~1.5.0"
Colors = "~0.12.10"
DSP = "~0.6.10"
FFTW = "~1.8.0"
FileIO = "~1.16.3"
FourierTools = "~0.4.3"
HTTP = "~1.10.6"
HypertextLiteral = "~0.9.5"
ImageIO = "~0.6.7"
ImageShow = "~0.3.8"
Images = "~0.26.1"
JSON = "~0.21.4"
JpegTurbo = "~0.1.5"
LazyGrids = "~0.5.0"
MosaicViews = "~0.3.4"
PlotlyJS = "~0.18.13"
Plots = "~1.40.4"
PlutoTeachingTools = "~0.2.15"
PlutoUI = "~0.7.59"
ProgressLogging = "~0.1.4"
QuartzImageIO = "~0.7.5"
StatsBase = "~0.34.3"
TestImages = "~1.8.0"
TimerOutputs = "~0.5.23"
Unitful = "~1.19.0"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

[[AbstractFFTs]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "d92ad398961a3ed262d8bf04a1a2b8340f915fef"
uuid = "621f4979-c628-5d54-868e-fcf4e3e8185c"
version = "1.5.0"
weakdeps = ["ChainRulesCore", "Test"]

    [AbstractFFTs.extensions]
    AbstractFFTsChainRulesCoreExt = "ChainRulesCore"
    AbstractFFTsTestExt = "Test"

[[AbstractNFFTs]]
deps = ["LinearAlgebra", "Printf"]
git-tree-sha1 = "292e21e99dedb8621c15f185b8fdb4260bb3c429"
uuid = "7f219486-4aa7-41d6-80a7-e08ef20ceed7"
version = "0.8.2"

[[AbstractPlutoDingetjes]]
deps = ["Pkg"]
git-tree-sha1 = "6e1d2a35f2f90a4bc7c2ed98079b2ba09c35b83a"
uuid = "6e696c72-6542-2067-7265-42206c756150"
version = "1.3.2"

[[Adapt]]
deps = ["LinearAlgebra", "Requires"]
git-tree-sha1 = "6a55b747d1812e699320963ffde36f1ebdda4099"
uuid = "79e6a3ab-5dfb-504d-930d-738a2a938a0e"
version = "4.0.4"
weakdeps = ["StaticArrays"]

    [Adapt.extensions]
    AdaptStaticArraysExt = "StaticArrays"

[[ArgCheck]]
git-tree-sha1 = "a3a402a35a2f7e0b87828ccabbd5ebfbebe356b4"
uuid = "dce04be8-c92d-5529-be00-80e4d2c0e197"
version = "2.3.0"

[[ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"
version = "1.1.1"

[[ArnoldiMethod]]
deps = ["LinearAlgebra", "Random", "StaticArrays"]
git-tree-sha1 = "d57bd3762d308bded22c3b82d033bff85f6195c6"
uuid = "ec485272-7323-5ecc-a04f-4719b315124d"
version = "0.4.0"

[[ArrayFire]]
deps = ["DSP", "FFTW", "Libdl", "LinearAlgebra", "Random", "SparseArrays", "SpecialFunctions", "Statistics", "Test"]
git-tree-sha1 = "9153a509145fc1666b070a47ea5024c2242755be"
uuid = "b19378d9-d87a-599a-927f-45f220a2c452"
version = "1.0.7"

[[ArrayInterface]]
deps = ["IfElse", "LinearAlgebra", "Requires", "SparseArrays", "Static"]
git-tree-sha1 = "d84c956c4c0548b4caf0e4e96cf5b6494b5b1529"
uuid = "4fba245c-0d91-5ea0-9b3e-6abc04ee57a9"
version = "3.1.32"

[[Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"

[[AssetRegistry]]
deps = ["Distributed", "JSON", "Pidfile", "SHA", "Test"]
git-tree-sha1 = "b25e88db7944f98789130d7b503276bc34bc098e"
uuid = "bf4720bc-e11a-5d0c-854e-bdca1663c893"
version = "0.1.0"

[[AxisAlgorithms]]
deps = ["LinearAlgebra", "Random", "SparseArrays", "WoodburyMatrices"]
git-tree-sha1 = "01b8ccb13d68535d73d2b0c23e39bd23155fb712"
uuid = "13072b0f-2c55-5437-9ae7-d433b7a33950"
version = "1.1.0"

[[AxisArrays]]
deps = ["Dates", "IntervalSets", "IterTools", "RangeArrays"]
git-tree-sha1 = "16351be62963a67ac4083f748fdb3cca58bfd52f"
uuid = "39de3d68-74b9-583c-8d2d-e117c070f3a9"
version = "0.4.7"

[[BangBang]]
deps = ["Compat", "ConstructionBase", "InitialValues", "LinearAlgebra", "Requires", "Setfield", "Tables"]
git-tree-sha1 = "7aa7ad1682f3d5754e3491bb59b8103cae28e3a3"
uuid = "198e06fe-97b7-11e9-32a5-e1d131e6ad66"
version = "0.3.40"

    [BangBang.extensions]
    BangBangChainRulesCoreExt = "ChainRulesCore"
    BangBangDataFramesExt = "DataFrames"
    BangBangStaticArraysExt = "StaticArrays"
    BangBangStructArraysExt = "StructArrays"
    BangBangTypedTablesExt = "TypedTables"

    [BangBang.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
    StaticArrays = "90137ffa-7385-5640-81b9-e52037218182"
    StructArrays = "09ab397b-f2b6-538f-b94a-2f83cf4a842a"
    TypedTables = "9d95f2ec-7b3d-5a63-8d20-e2491e220bb9"

[[Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"

[[Baselet]]
git-tree-sha1 = "aebf55e6d7795e02ca500a689d326ac979aaf89e"
uuid = "9718e550-a3fa-408a-8086-8db961cd8217"
version = "0.1.1"

[[BasicInterpolators]]
deps = ["LinearAlgebra", "Memoize", "Random"]
git-tree-sha1 = "3f7be532673fc4a22825e7884e9e0e876236b12a"
uuid = "26cce99e-4866-4b6d-ab74-862489e035e0"
version = "0.7.1"

[[BenchmarkTools]]
deps = ["JSON", "Logging", "Printf", "Profile", "Statistics", "UUIDs"]
git-tree-sha1 = "f1dff6729bc61f4d49e140da1af55dcd1ac97b2f"
uuid = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"
version = "1.5.0"

[[BitFlags]]
git-tree-sha1 = "2dc09997850d68179b69dafb58ae806167a32b1b"
uuid = "d1d4a3ce-64b1-5f1a-9ba4-7e7e69966f35"
version = "0.1.8"

[[BitTwiddlingConvenienceFunctions]]
deps = ["Static"]
git-tree-sha1 = "0c5f81f47bbbcf4aea7b2959135713459170798b"
uuid = "62783981-4cbd-42fc-bca8-16325de8dc4b"
version = "0.1.5"

[[Blink]]
deps = ["Base64", "Distributed", "HTTP", "JSExpr", "JSON", "Lazy", "Logging", "MacroTools", "Mustache", "Mux", "Pkg", "Reexport", "Sockets", "WebIO"]
git-tree-sha1 = "bc93511973d1f949d45b0ea17878e6cb0ad484a1"
uuid = "ad839575-38b3-5650-b840-f874b8c74a25"
version = "0.12.9"

[[Bzip2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "9e2a6b69137e6969bab0152632dcb3bc108c8bdd"
uuid = "6e34b625-4abd-537c-b88f-471c36dfa7a0"
version = "1.0.8+1"

[[CEnum]]
git-tree-sha1 = "389ad5c84de1ae7cf0e28e381131c98ea87d54fc"
uuid = "fa961155-64e5-5f13-b03f-caf6b980ea82"
version = "0.5.0"

[[CPUSummary]]
deps = ["CpuId", "IfElse", "Static"]
git-tree-sha1 = "a7157ab6bcda173f533db4c93fc8a27a48843757"
uuid = "2a0fbf3d-bb9c-48f3-b0a9-814d99fd7ab9"
version = "0.1.30"

[[Cairo_jll]]
deps = ["Artifacts", "Bzip2_jll", "CompilerSupportLibraries_jll", "Fontconfig_jll", "FreeType2_jll", "Glib_jll", "JLLWrappers", "LZO_jll", "Libdl", "Pixman_jll", "Xorg_libXext_jll", "Xorg_libXrender_jll", "Zlib_jll", "libpng_jll"]
git-tree-sha1 = "a4c43f59baa34011e303e76f5c8c91bf58415aaf"
uuid = "83423d85-b0ee-5818-9007-b63ccbeb887a"
version = "1.18.0+1"

[[CatIndices]]
deps = ["CustomUnitRanges", "OffsetArrays"]
git-tree-sha1 = "a0f80a09780eed9b1d106a1bf62041c2efc995bc"
uuid = "aafaddc9-749c-510e-ac4f-586e18779b91"
version = "0.2.2"

[[ChainRulesCore]]
deps = ["Compat", "LinearAlgebra"]
git-tree-sha1 = "575cd02e080939a33b6df6c5853d14924c08e35b"
uuid = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
version = "1.23.0"
weakdeps = ["SparseArrays"]

    [ChainRulesCore.extensions]
    ChainRulesCoreSparseArraysExt = "SparseArrays"

[[CloseOpenIntervals]]
deps = ["ArrayInterface", "Static"]
git-tree-sha1 = "80eeab249deff1024ad827982ead7dd3192d332b"
uuid = "fb6a15b2-703c-40df-9091-08a04967cfa9"
version = "0.1.3"

[[Clustering]]
deps = ["Distances", "LinearAlgebra", "NearestNeighbors", "Printf", "Random", "SparseArrays", "Statistics", "StatsBase"]
git-tree-sha1 = "9ebb045901e9bbf58767a9f34ff89831ed711aae"
uuid = "aaaa29a8-35af-508c-8bc3-b662a17a0fe5"
version = "0.15.7"

[[CodeTracking]]
deps = ["InteractiveUtils", "UUIDs"]
git-tree-sha1 = "c0216e792f518b39b22212127d4a84dc31e4e386"
uuid = "da1fd8a2-8d9e-5ec2-8556-3022fb5608a2"
version = "1.3.5"

[[CodecZlib]]
deps = ["TranscodingStreams", "Zlib_jll"]
git-tree-sha1 = "59939d8a997469ee05c4b4944560a820f9ba0d73"
uuid = "944b1d66-785c-5afd-91f1-9de20f533193"
version = "0.7.4"

[[ColorSchemes]]
deps = ["ColorTypes", "ColorVectorSpace", "Colors", "FixedPointNumbers", "PrecompileTools", "Random"]
git-tree-sha1 = "67c1f244b991cad9b0aa4b7540fb758c2488b129"
uuid = "35d6a980-a343-548e-a6ea-1d62b119f2f4"
version = "3.24.0"

[[ColorTypes]]
deps = ["FixedPointNumbers", "Random"]
git-tree-sha1 = "b10d0b65641d57b8b4d5e234446582de5047050d"
uuid = "3da002f7-5984-5a60-b8a6-cbb66c0b333f"
version = "0.11.5"

[[ColorVectorSpace]]
deps = ["ColorTypes", "FixedPointNumbers", "LinearAlgebra", "Requires", "Statistics", "TensorCore"]
git-tree-sha1 = "a1f44953f2382ebb937d60dafbe2deea4bd23249"
uuid = "c3611d14-8923-5661-9e6a-0046d554d3a4"
version = "0.10.0"
weakdeps = ["SpecialFunctions"]

    [ColorVectorSpace.extensions]
    SpecialFunctionsExt = "SpecialFunctions"

[[Colors]]
deps = ["ColorTypes", "FixedPointNumbers", "Reexport"]
git-tree-sha1 = "fc08e5930ee9a4e03f84bfb5211cb54e7769758a"
uuid = "5ae59095-9a9b-59fe-a467-6f913c188581"
version = "0.12.10"

[[CommonSubexpressions]]
deps = ["MacroTools", "Test"]
git-tree-sha1 = "7b8a93dba8af7e3b42fecabf646260105ac373f7"
uuid = "bbf7d656-a473-5ed7-a52c-81e309532950"
version = "0.3.0"

[[Compat]]
deps = ["TOML", "UUIDs"]
git-tree-sha1 = "c955881e3c981181362ae4088b35995446298b80"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "4.14.0"
weakdeps = ["Dates", "LinearAlgebra"]

    [Compat.extensions]
    CompatLinearAlgebraExt = "LinearAlgebra"

[[CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"
version = "1.1.1+0"

[[CompositionsBase]]
git-tree-sha1 = "802bb88cd69dfd1509f6670416bd4434015693ad"
uuid = "a33af91c-f02d-484b-be07-31d278c5ca2b"
version = "0.1.2"

    [CompositionsBase.extensions]
    CompositionsBaseInverseFunctionsExt = "InverseFunctions"

    [CompositionsBase.weakdeps]
    InverseFunctions = "3587e190-3f89-42d0-90ee-14403ec27112"

[[ComputationalResources]]
git-tree-sha1 = "52cb3ec90e8a8bea0e62e275ba577ad0f74821f7"
uuid = "ed09eef8-17a6-5b46-8889-db040fac31e3"
version = "0.3.2"

[[ConcurrentUtilities]]
deps = ["Serialization", "Sockets"]
git-tree-sha1 = "6cbbd4d241d7e6579ab354737f4dd95ca43946e1"
uuid = "f0e56b4a-5159-44fe-b623-3e5288b988bb"
version = "2.4.1"

[[ConstructionBase]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "260fd2400ed2dab602a7c15cf10c1933c59930a2"
uuid = "187b0558-2788-49d3-abe0-74a17ed4e7c9"
version = "1.5.5"
weakdeps = ["IntervalSets", "StaticArrays"]

    [ConstructionBase.extensions]
    ConstructionBaseIntervalSetsExt = "IntervalSets"
    ConstructionBaseStaticArraysExt = "StaticArrays"

[[ContextVariablesX]]
deps = ["Compat", "Logging", "UUIDs"]
git-tree-sha1 = "25cc3803f1030ab855e383129dcd3dc294e322cc"
uuid = "6add18c4-b38d-439d-96f6-d6bc489c04c5"
version = "0.1.3"

[[Contour]]
git-tree-sha1 = "439e35b0b36e2e5881738abc8857bd92ad6ff9a8"
uuid = "d38c429a-6771-53c6-b99e-75d170b6e991"
version = "0.6.3"

[[CoordinateTransformations]]
deps = ["LinearAlgebra", "StaticArrays"]
git-tree-sha1 = "f9d7112bfff8a19a3a4ea4e03a8e6a91fe8456bf"
uuid = "150eb455-5306-5404-9cee-2592286d6298"
version = "0.6.3"

[[CpuId]]
deps = ["Markdown"]
git-tree-sha1 = "fcbb72b032692610bfbdb15018ac16a36cf2e406"
uuid = "adafc99b-e345-5852-983c-f28acb93d879"
version = "0.3.1"

[[CustomUnitRanges]]
git-tree-sha1 = "1a3f97f907e6dd8983b744d2642651bb162a3f7a"
uuid = "dc8bdbbb-1ca9-579f-8c36-e416f6a65cce"
version = "1.0.2"

[[DSP]]
deps = ["FFTW", "IterTools", "LinearAlgebra", "Polynomials", "Random", "Reexport", "SpecialFunctions", "Statistics"]
git-tree-sha1 = "2a63cb5fc0e8c1f0f139475ef94228c7441dc7d0"
uuid = "717857b8-e6f2-59f4-9121-6e50c889abd2"
version = "0.6.10"

[[DataAPI]]
git-tree-sha1 = "abe83f3a2f1b857aac70ef8b269080af17764bbe"
uuid = "9a962f9c-6df0-11e9-0e5d-c546b8b5ee8a"
version = "1.16.0"

[[DataStructures]]
deps = ["Compat", "InteractiveUtils", "OrderedCollections"]
git-tree-sha1 = "1d0a14036acb104d9e89698bd408f63ab58cdc82"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.18.20"

[[DataValueInterfaces]]
git-tree-sha1 = "bfc1187b79289637fa0ef6d4436ebdfe6905cbd6"
uuid = "e2d170a0-9d28-54be-80f0-106bbe20a464"
version = "1.0.0"

[[Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"

[[DefineSingletons]]
git-tree-sha1 = "0fba8b706d0178b4dc7fd44a96a92382c9065c2c"
uuid = "244e2a9f-e319-4986-a169-4d1fe445cd52"
version = "0.1.2"

[[DelimitedFiles]]
deps = ["Mmap"]
git-tree-sha1 = "9e2f36d3c96a820c678f2f1f1782582fcf685bae"
uuid = "8bb1440f-4735-579b-a4ab-409b98df4dab"
version = "1.9.1"

[[DiffResults]]
deps = ["StaticArraysCore"]
git-tree-sha1 = "782dd5f4561f5d267313f23853baaaa4c52ea621"
uuid = "163ba53b-c6d8-5494-b064-1a9d43ac40c5"
version = "1.1.0"

[[DiffRules]]
deps = ["IrrationalConstants", "LogExpFunctions", "NaNMath", "Random", "SpecialFunctions"]
git-tree-sha1 = "158232a81d43d108837639d3fd4c66cc3988c255"
uuid = "b552c78f-8df3-52c6-915a-8e097449b14b"
version = "1.14.0"

[[Distances]]
deps = ["LinearAlgebra", "Statistics", "StatsAPI"]
git-tree-sha1 = "66c4c81f259586e8f002eacebc177e1fb06363b0"
uuid = "b4f34e82-e78d-54a5-968a-f98e89d6e8f7"
version = "0.10.11"
weakdeps = ["ChainRulesCore", "SparseArrays"]

    [Distances.extensions]
    DistancesChainRulesCoreExt = "ChainRulesCore"
    DistancesSparseArraysExt = "SparseArrays"

[[Distributed]]
deps = ["Random", "Serialization", "Sockets"]
uuid = "8ba89e20-285c-5b6f-9357-94700520ee1b"

[[DocStringExtensions]]
deps = ["LibGit2"]
git-tree-sha1 = "b19534d1895d702889b219c382a6e18010797f0b"
uuid = "ffbed154-4ef7-542d-bbb7-c09d3a79fcae"
version = "0.8.6"

[[Downloads]]
deps = ["ArgTools", "FileWatching", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"
version = "1.6.0"

[[EpollShim_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "8e9441ee83492030ace98f9789a654a6d0b1f643"
uuid = "2702e6a9-849d-5ed8-8c21-79e8b8f9ee43"
version = "0.0.20230411+0"

[[ExceptionUnwrapping]]
deps = ["Test"]
git-tree-sha1 = "dcb08a0d93ec0b1cdc4af184b26b591e9695423a"
uuid = "460bff9d-24e4-43bc-9d9f-a8973cb893f4"
version = "0.1.10"

[[Expat_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "4558ab818dcceaab612d1bb8c19cee87eda2b83c"
uuid = "2e619515-83b5-522b-bb60-26c02a35a201"
version = "2.5.0+0"

[[ExprTools]]
git-tree-sha1 = "27415f162e6028e81c72b82ef756bf321213b6ec"
uuid = "e2ba6199-217a-4e67-a87a-7c52f15ade04"
version = "0.1.10"

[[FFMPEG]]
deps = ["FFMPEG_jll"]
git-tree-sha1 = "b57e3acbe22f8484b4b5ff66a7499717fe1a9cc8"
uuid = "c87230d0-a227-11e9-1b43-d7ebe4e7570a"
version = "0.4.1"

[[FFMPEG_jll]]
deps = ["Artifacts", "Bzip2_jll", "FreeType2_jll", "FriBidi_jll", "JLLWrappers", "LAME_jll", "Libdl", "Ogg_jll", "OpenSSL_jll", "Opus_jll", "PCRE2_jll", "Pkg", "Zlib_jll", "libaom_jll", "libass_jll", "libfdk_aac_jll", "libvorbis_jll", "x264_jll", "x265_jll"]
git-tree-sha1 = "74faea50c1d007c85837327f6775bea60b5492dd"
uuid = "b22a6f82-2f65-5046-a5b2-351ab43fb4e5"
version = "4.4.2+2"

[[FFTViews]]
deps = ["CustomUnitRanges", "FFTW"]
git-tree-sha1 = "cbdf14d1e8c7c8aacbe8b19862e0179fd08321c2"
uuid = "4f61f5a4-77b1-5117-aa51-3ab5ef4ef0cd"
version = "0.3.2"

[[FFTW]]
deps = ["AbstractFFTs", "FFTW_jll", "LinearAlgebra", "MKL_jll", "Preferences", "Reexport"]
git-tree-sha1 = "4820348781ae578893311153d69049a93d05f39d"
uuid = "7a1cc6ca-52ef-59f5-83cd-3a7055c09341"
version = "1.8.0"

[[FFTW_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "c6033cc3892d0ef5bb9cd29b7f2f0331ea5184ea"
uuid = "f5851436-0d7a-5f13-b9de-f02708fd171a"
version = "3.3.10+0"

[[FLoops]]
deps = ["BangBang", "Compat", "FLoopsBase", "InitialValues", "JuliaVariables", "MLStyle", "Serialization", "Setfield", "Transducers"]
git-tree-sha1 = "ffb97765602e3cbe59a0589d237bf07f245a8576"
uuid = "cc61a311-1640-44b5-9fba-1b764f453329"
version = "0.2.1"

[[FLoopsBase]]
deps = ["ContextVariablesX"]
git-tree-sha1 = "656f7a6859be8673bf1f35da5670246b923964f7"
uuid = "b9860ae5-e623-471e-878b-f6a53c775ea6"
version = "0.1.1"

[[FileIO]]
deps = ["Pkg", "Requires", "UUIDs"]
git-tree-sha1 = "82d8afa92ecf4b52d78d869f038ebfb881267322"
uuid = "5789e2e9-d7fb-5bc7-8068-2c6fae9b9549"
version = "1.16.3"

[[FileWatching]]
uuid = "7b1f6079-737a-58dc-b8bc-7a2ca5c1b5ee"

[[FixedPointNumbers]]
deps = ["Statistics"]
git-tree-sha1 = "335bfdceacc84c5cdf16aadc768aa5ddfc5383cc"
uuid = "53c48c17-4a7d-5ca2-90c5-79b7896eea93"
version = "0.8.4"

[[Fontconfig_jll]]
deps = ["Artifacts", "Bzip2_jll", "Expat_jll", "FreeType2_jll", "JLLWrappers", "Libdl", "Libuuid_jll", "Pkg", "Zlib_jll"]
git-tree-sha1 = "21efd19106a55620a188615da6d3d06cd7f6ee03"
uuid = "a3f928ae-7b40-5064-980b-68af3947d34b"
version = "2.13.93+0"

[[Format]]
git-tree-sha1 = "9c68794ef81b08086aeb32eeaf33531668d5f5fc"
uuid = "1fa38f19-a742-5d3f-a2b9-30dd87b9d5f8"
version = "1.3.7"

[[ForwardDiff]]
deps = ["CommonSubexpressions", "DiffResults", "DiffRules", "LinearAlgebra", "LogExpFunctions", "NaNMath", "Preferences", "Printf", "Random", "SpecialFunctions"]
git-tree-sha1 = "cf0fe81336da9fb90944683b8c41984b08793dad"
uuid = "f6369f11-7733-5829-9624-2563aa707210"
version = "0.10.36"
weakdeps = ["StaticArrays"]

    [ForwardDiff.extensions]
    ForwardDiffStaticArraysExt = "StaticArrays"

[[FourierTools]]
deps = ["ChainRulesCore", "FFTW", "IndexFunArrays", "LinearAlgebra", "NDTools", "NFFT", "PaddedViews", "Reexport", "ShiftedArrays"]
git-tree-sha1 = "675b74c435b2b7c8ee85a7727ec295407f77d0b1"
uuid = "b18b359b-aebc-45ac-a139-9c0ccbb2871e"
version = "0.4.3"

[[FreeType2_jll]]
deps = ["Artifacts", "Bzip2_jll", "JLLWrappers", "Libdl", "Zlib_jll"]
git-tree-sha1 = "d8db6a5a2fe1381c1ea4ef2cab7c69c2de7f9ea0"
uuid = "d7e528f0-a631-5988-bf34-fe36492bcfd7"
version = "2.13.1+0"

[[FriBidi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "aa31987c2ba8704e23c6c8ba8a4f769d5d7e4f91"
uuid = "559328eb-81f9-559d-9380-de523a88c83c"
version = "1.0.10+0"

[[FunctionalCollections]]
deps = ["Test"]
git-tree-sha1 = "04cb9cfaa6ba5311973994fe3496ddec19b6292a"
uuid = "de31a74c-ac4f-5751-b3fd-e18cd04993ca"
version = "0.5.0"

[[Future]]
deps = ["Random"]
uuid = "9fa8497b-333b-5362-9e8d-4d0656e87820"

[[GLFW_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libglvnd_jll", "Xorg_libXcursor_jll", "Xorg_libXi_jll", "Xorg_libXinerama_jll", "Xorg_libXrandr_jll"]
git-tree-sha1 = "ff38ba61beff76b8f4acad8ab0c97ef73bb670cb"
uuid = "0656b61e-2033-5cc2-a64a-77c0f6c09b89"
version = "3.3.9+0"

[[GR]]
deps = ["Artifacts", "Base64", "DelimitedFiles", "Downloads", "GR_jll", "HTTP", "JSON", "Libdl", "LinearAlgebra", "Pkg", "Preferences", "Printf", "Random", "Serialization", "Sockets", "TOML", "Tar", "Test", "UUIDs", "p7zip_jll"]
git-tree-sha1 = "8e2d86e06ceb4580110d9e716be26658effc5bfd"
uuid = "28b8d3ca-fb5f-59d9-8090-bfdbd6d07a71"
version = "0.72.8"

[[GR_jll]]
deps = ["Artifacts", "Bzip2_jll", "Cairo_jll", "FFMPEG_jll", "Fontconfig_jll", "GLFW_jll", "JLLWrappers", "JpegTurbo_jll", "Libdl", "Libtiff_jll", "Pixman_jll", "Qt5Base_jll", "Zlib_jll", "libpng_jll"]
git-tree-sha1 = "da121cbdc95b065da07fbb93638367737969693f"
uuid = "d2c73de3-f751-5644-a686-071e5b155ba9"
version = "0.72.8+0"

[[Gettext_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Libiconv_jll", "Pkg", "XML2_jll"]
git-tree-sha1 = "9b02998aba7bf074d14de89f9d37ca24a1a0b046"
uuid = "78b55507-aeef-58d4-861c-77aaff3498b1"
version = "0.21.0+0"

[[Ghostscript_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "43ba3d3c82c18d88471cfd2924931658838c9d8f"
uuid = "61579ee1-b43e-5ca0-a5da-69d92c66a64b"
version = "9.55.0+4"

[[Glib_jll]]
deps = ["Artifacts", "Gettext_jll", "JLLWrappers", "Libdl", "Libffi_jll", "Libiconv_jll", "Libmount_jll", "PCRE2_jll", "Zlib_jll"]
git-tree-sha1 = "359a1ba2e320790ddbe4ee8b4d54a305c0ea2aff"
uuid = "7746bdde-850d-59dc-9ae8-88ece973131d"
version = "2.80.0+0"

[[Graphics]]
deps = ["Colors", "LinearAlgebra", "NaNMath"]
git-tree-sha1 = "d61890399bc535850c4bf08e4e0d3a7ad0f21cbd"
uuid = "a2bd30eb-e257-5431-a919-1863eab51364"
version = "1.1.2"

[[Graphite2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "344bf40dcab1073aca04aa0df4fb092f920e4011"
uuid = "3b182d85-2403-5c21-9c21-1e1f0cc25472"
version = "1.3.14+0"

[[Graphs]]
deps = ["ArnoldiMethod", "Compat", "DataStructures", "Distributed", "Inflate", "LinearAlgebra", "Random", "SharedArrays", "SimpleTraits", "SparseArrays", "Statistics"]
git-tree-sha1 = "3863330da5466410782f2bffc64f3d505a6a8334"
uuid = "86223c79-3864-5bf0-83f7-82e725a168b6"
version = "1.10.0"

[[Grisu]]
git-tree-sha1 = "53bb909d1151e57e2484c3d1b53e19552b887fb2"
uuid = "42e2da0e-8278-4e71-bc24-59509adca0fe"
version = "1.0.2"

[[HTTP]]
deps = ["Base64", "CodecZlib", "ConcurrentUtilities", "Dates", "ExceptionUnwrapping", "Logging", "LoggingExtras", "MbedTLS", "NetworkOptions", "OpenSSL", "Random", "SimpleBufferStream", "Sockets", "URIs", "UUIDs"]
git-tree-sha1 = "2c3ec1f90bb4a8f7beafb0cffea8a4c3f4e636ab"
uuid = "cd3eb016-35fb-5094-929b-558a96fad6f3"
version = "1.10.6"

[[HarfBuzz_jll]]
deps = ["Artifacts", "Cairo_jll", "Fontconfig_jll", "FreeType2_jll", "Glib_jll", "Graphite2_jll", "JLLWrappers", "Libdl", "Libffi_jll", "Pkg"]
git-tree-sha1 = "129acf094d168394e80ee1dc4bc06ec835e510a3"
uuid = "2e76f6c2-a576-52d4-95c1-20adfe4de566"
version = "2.8.1+1"

[[Hiccup]]
deps = ["MacroTools", "Test"]
git-tree-sha1 = "6187bb2d5fcbb2007c39e7ac53308b0d371124bd"
uuid = "9fb69e20-1954-56bb-a84f-559cc56a8ff7"
version = "0.2.2"

[[HistogramThresholding]]
deps = ["ImageBase", "LinearAlgebra", "MappedArrays"]
git-tree-sha1 = "7194dfbb2f8d945abdaf68fa9480a965d6661e69"
uuid = "2c695a8d-9458-5d45-9878-1b8a99cf7853"
version = "0.3.1"

[[HostCPUFeatures]]
deps = ["BitTwiddlingConvenienceFunctions", "IfElse", "Libdl", "Static"]
git-tree-sha1 = "eb8fed28f4994600e29beef49744639d985a04b2"
uuid = "3e5b6fbb-0976-4d2c-9146-d79de83f2fb0"
version = "0.1.16"

[[Hyperscript]]
deps = ["Test"]
git-tree-sha1 = "179267cfa5e712760cd43dcae385d7ea90cc25a4"
uuid = "47d2ed2b-36de-50cf-bf87-49c2cf4b8b91"
version = "0.0.5"

[[HypertextLiteral]]
deps = ["Tricks"]
git-tree-sha1 = "7134810b1afce04bbc1045ca1985fbe81ce17653"
uuid = "ac1192a8-f4b3-4bfe-ba22-af5b92cd3ab2"
version = "0.9.5"

[[IOCapture]]
deps = ["Logging", "Random"]
git-tree-sha1 = "8b72179abc660bfab5e28472e019392b97d0985c"
uuid = "b5f81e59-6552-4d32-b1f0-c071b021bf89"
version = "0.2.4"

[[IfElse]]
git-tree-sha1 = "debdd00ffef04665ccbb3e150747a77560e8fad1"
uuid = "615f187c-cbe4-4ef1-ba3b-2fcf58d6d173"
version = "0.1.1"

[[ImageAxes]]
deps = ["AxisArrays", "ImageBase", "ImageCore", "Reexport", "SimpleTraits"]
git-tree-sha1 = "2e4520d67b0cef90865b3ef727594d2a58e0e1f8"
uuid = "2803e5a7-5153-5ecf-9a86-9b4c37f5f5ac"
version = "0.6.11"

[[ImageBase]]
deps = ["ImageCore", "Reexport"]
git-tree-sha1 = "eb49b82c172811fd2c86759fa0553a2221feb909"
uuid = "c817782e-172a-44cc-b673-b171935fbb9e"
version = "0.1.7"

[[ImageBinarization]]
deps = ["HistogramThresholding", "ImageCore", "LinearAlgebra", "Polynomials", "Reexport", "Statistics"]
git-tree-sha1 = "f5356e7203c4a9954962e3757c08033f2efe578a"
uuid = "cbc4b850-ae4b-5111-9e64-df94c024a13d"
version = "0.3.0"

[[ImageContrastAdjustment]]
deps = ["ImageBase", "ImageCore", "ImageTransformations", "Parameters"]
git-tree-sha1 = "eb3d4365a10e3f3ecb3b115e9d12db131d28a386"
uuid = "f332f351-ec65-5f6a-b3d1-319c6670881a"
version = "0.3.12"

[[ImageCore]]
deps = ["ColorVectorSpace", "Colors", "FixedPointNumbers", "MappedArrays", "MosaicViews", "OffsetArrays", "PaddedViews", "PrecompileTools", "Reexport"]
git-tree-sha1 = "b2a7eaa169c13f5bcae8131a83bc30eff8f71be0"
uuid = "a09fc81d-aa75-5fe9-8630-4744c3626534"
version = "0.10.2"

[[ImageCorners]]
deps = ["ImageCore", "ImageFiltering", "PrecompileTools", "StaticArrays", "StatsBase"]
git-tree-sha1 = "24c52de051293745a9bad7d73497708954562b79"
uuid = "89d5987c-236e-4e32-acd0-25bd6bd87b70"
version = "0.1.3"

[[ImageDistances]]
deps = ["Distances", "ImageCore", "ImageMorphology", "LinearAlgebra", "Statistics"]
git-tree-sha1 = "08b0e6354b21ef5dd5e49026028e41831401aca8"
uuid = "51556ac3-7006-55f5-8cb3-34580c88182d"
version = "0.2.17"

[[ImageFiltering]]
deps = ["CatIndices", "ComputationalResources", "DataStructures", "FFTViews", "FFTW", "ImageBase", "ImageCore", "LinearAlgebra", "OffsetArrays", "PrecompileTools", "Reexport", "SparseArrays", "StaticArrays", "Statistics", "TiledIteration"]
git-tree-sha1 = "432ae2b430a18c58eb7eca9ef8d0f2db90bc749c"
uuid = "6a3955dd-da59-5b1f-98d4-e7296123deb5"
version = "0.7.8"

[[ImageIO]]
deps = ["FileIO", "IndirectArrays", "JpegTurbo", "LazyModules", "Netpbm", "OpenEXR", "PNGFiles", "QOI", "Sixel", "TiffImages", "UUIDs"]
git-tree-sha1 = "bca20b2f5d00c4fbc192c3212da8fa79f4688009"
uuid = "82e4d734-157c-48bb-816b-45c225c6df19"
version = "0.6.7"

[[ImageMagick]]
deps = ["FileIO", "ImageCore", "ImageMagick_jll", "InteractiveUtils"]
git-tree-sha1 = "8e2eae13d144d545ef829324f1f0a5a4fe4340f3"
uuid = "6218d12a-5da1-5696-b52f-db25d2ecc6d1"
version = "1.3.1"

[[ImageMagick_jll]]
deps = ["Artifacts", "Ghostscript_jll", "JLLWrappers", "JpegTurbo_jll", "Libdl", "Libtiff_jll", "OpenJpeg_jll", "Pkg", "Zlib_jll", "libpng_jll"]
git-tree-sha1 = "8d2e786fd090199a91ecbf4a66d03aedd0fb24d4"
uuid = "c73af94c-d91f-53ed-93a7-00f77d67a9d7"
version = "6.9.11+4"

[[ImageMetadata]]
deps = ["AxisArrays", "ImageAxes", "ImageBase", "ImageCore"]
git-tree-sha1 = "355e2b974f2e3212a75dfb60519de21361ad3cb7"
uuid = "bc367c6b-8a6b-528e-b4bd-a4b897500b49"
version = "0.9.9"

[[ImageMorphology]]
deps = ["DataStructures", "ImageCore", "LinearAlgebra", "LoopVectorization", "OffsetArrays", "Requires", "TiledIteration"]
git-tree-sha1 = "6f0a801136cb9c229aebea0df296cdcd471dbcd1"
uuid = "787d08f9-d448-5407-9aad-5290dd7ab264"
version = "0.4.5"

[[ImageQualityIndexes]]
deps = ["ImageContrastAdjustment", "ImageCore", "ImageDistances", "ImageFiltering", "LazyModules", "OffsetArrays", "PrecompileTools", "Statistics"]
git-tree-sha1 = "783b70725ed326340adf225be4889906c96b8fd1"
uuid = "2996bd0c-7a13-11e9-2da2-2f5ce47296a9"
version = "0.3.7"

[[ImageSegmentation]]
deps = ["Clustering", "DataStructures", "Distances", "Graphs", "ImageCore", "ImageFiltering", "ImageMorphology", "LinearAlgebra", "MetaGraphs", "RegionTrees", "SimpleWeightedGraphs", "StaticArrays", "Statistics"]
git-tree-sha1 = "3ff0ca203501c3eedde3c6fa7fd76b703c336b5f"
uuid = "80713f31-8817-5129-9cf8-209ff8fb23e1"
version = "1.8.2"

[[ImageShow]]
deps = ["Base64", "ColorSchemes", "FileIO", "ImageBase", "ImageCore", "OffsetArrays", "StackViews"]
git-tree-sha1 = "3b5344bcdbdc11ad58f3b1956709b5b9345355de"
uuid = "4e3cecfd-b093-5904-9786-8bbb286a6a31"
version = "0.3.8"

[[ImageTransformations]]
deps = ["AxisAlgorithms", "CoordinateTransformations", "ImageBase", "ImageCore", "Interpolations", "OffsetArrays", "Rotations", "StaticArrays"]
git-tree-sha1 = "e0884bdf01bbbb111aea77c348368a86fb4b5ab6"
uuid = "02fcd773-0e25-5acc-982a-7f6622650795"
version = "0.10.1"

[[Images]]
deps = ["Base64", "FileIO", "Graphics", "ImageAxes", "ImageBase", "ImageBinarization", "ImageContrastAdjustment", "ImageCore", "ImageCorners", "ImageDistances", "ImageFiltering", "ImageIO", "ImageMagick", "ImageMetadata", "ImageMorphology", "ImageQualityIndexes", "ImageSegmentation", "ImageShow", "ImageTransformations", "IndirectArrays", "IntegralArrays", "Random", "Reexport", "SparseArrays", "StaticArrays", "Statistics", "StatsBase", "TiledIteration"]
git-tree-sha1 = "12fdd617c7fe25dc4a6cc804d657cc4b2230302b"
uuid = "916415d5-f1e6-5110-898d-aaa5f9f070e0"
version = "0.26.1"

[[Imath_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "3d09a9f60edf77f8a4d99f9e015e8fbf9989605d"
uuid = "905a6f67-0a94-5f89-b386-d35d92009cd1"
version = "3.1.7+0"

[[IndexFunArrays]]
deps = ["ChainRulesCore", "LinearAlgebra"]
git-tree-sha1 = "6f78703c7a4ba06299cddd8694799c91de0157ac"
uuid = "613c443e-d742-454e-bfc6-1d7f8dd76566"
version = "0.2.7"

[[IndirectArrays]]
git-tree-sha1 = "012e604e1c7458645cb8b436f8fba789a51b257f"
uuid = "9b13fd28-a010-5f03-acff-a1bbcff69959"
version = "1.0.0"

[[Inflate]]
git-tree-sha1 = "ea8031dea4aff6bd41f1df8f2fdfb25b33626381"
uuid = "d25df0c9-e2be-5dd7-82c8-3ad0b3e990b9"
version = "0.1.4"

[[InitialValues]]
git-tree-sha1 = "4da0f88e9a39111c2fa3add390ab15f3a44f3ca3"
uuid = "22cec73e-a1b8-11e9-2c92-598750a2cf9c"
version = "0.3.1"

[[InlineStrings]]
deps = ["Parsers"]
git-tree-sha1 = "9cc2baf75c6d09f9da536ddf58eb2f29dedaf461"
uuid = "842dd82b-1e85-43dc-bf29-5d0ee9dffc48"
version = "1.4.0"

[[IntegralArrays]]
deps = ["ColorTypes", "FixedPointNumbers", "IntervalSets"]
git-tree-sha1 = "be8e690c3973443bec584db3346ddc904d4884eb"
uuid = "1d092043-8f09-5a30-832f-7509e371ab51"
version = "0.1.5"

[[IntelOpenMP_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "be50fe8df3acbffa0274a744f1a99d29c45a57f4"
uuid = "1d5cc7b8-4909-519e-a0f8-d0f5ad9712d0"
version = "2024.1.0+0"

[[InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"

[[Interpolations]]
deps = ["Adapt", "AxisAlgorithms", "ChainRulesCore", "LinearAlgebra", "OffsetArrays", "Random", "Ratios", "Requires", "SharedArrays", "SparseArrays", "StaticArrays", "WoodburyMatrices"]
git-tree-sha1 = "88a101217d7cb38a7b481ccd50d21876e1d1b0e0"
uuid = "a98d9a8b-a2ab-59e6-89dd-64a1c18fca59"
version = "0.15.1"
weakdeps = ["Unitful"]

    [Interpolations.extensions]
    InterpolationsUnitfulExt = "Unitful"

[[IntervalSets]]
git-tree-sha1 = "dba9ddf07f77f60450fe5d2e2beb9854d9a49bd0"
uuid = "8197267c-284f-5f27-9208-e0e47529a953"
version = "0.7.10"
weakdeps = ["Random", "RecipesBase", "Statistics"]

    [IntervalSets.extensions]
    IntervalSetsRandomExt = "Random"
    IntervalSetsRecipesBaseExt = "RecipesBase"
    IntervalSetsStatisticsExt = "Statistics"

[[Intervals]]
deps = ["Dates", "Printf", "RecipesBase", "Serialization", "TimeZones"]
git-tree-sha1 = "ac0aaa807ed5eaf13f67afe188ebc07e828ff640"
uuid = "d8418881-c3e1-53bb-8760-2df7ec849ed5"
version = "1.10.0"

[[IrrationalConstants]]
git-tree-sha1 = "630b497eafcc20001bba38a4651b327dcfc491d2"
uuid = "92d709cd-6900-40b7-9082-c6be49f344b6"
version = "0.2.2"

[[IterTools]]
git-tree-sha1 = "42d5f897009e7ff2cf88db414a389e5ed1bdd023"
uuid = "c8e1da08-722c-5040-9ed9-7db0dc04731e"
version = "1.10.0"

[[IteratorInterfaceExtensions]]
git-tree-sha1 = "a3f24677c21f5bbe9d2a714f95dcd58337fb2856"
uuid = "82899510-4779-5014-852e-03e436cf321d"
version = "1.0.0"

[[JLD2]]
deps = ["FileIO", "MacroTools", "Mmap", "OrderedCollections", "Pkg", "PrecompileTools", "Printf", "Reexport", "Requires", "TranscodingStreams", "UUIDs"]
git-tree-sha1 = "5ea6acdd53a51d897672edb694e3cc2912f3f8a7"
uuid = "033835bb-8acc-5ee8-8aae-3f567f8a3819"
version = "0.4.46"

[[JLFzf]]
deps = ["Pipe", "REPL", "Random", "fzf_jll"]
git-tree-sha1 = "a53ebe394b71470c7f97c2e7e170d51df21b17af"
uuid = "1019f520-868f-41f5-a6de-eb00f4b6a39c"
version = "0.1.7"

[[JLLWrappers]]
deps = ["Artifacts", "Preferences"]
git-tree-sha1 = "7e5d6779a1e09a36db2a7b6cff50942a0a7d0fca"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.5.0"

[[JSExpr]]
deps = ["JSON", "MacroTools", "Observables", "WebIO"]
git-tree-sha1 = "b413a73785b98474d8af24fd4c8a975e31df3658"
uuid = "97c1335a-c9c5-57fe-bc5d-ec35cebe8660"
version = "0.5.4"

[[JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "31e996f0a15c7b280ba9f76636b3ff9e2ae58c9a"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.4"

[[JpegTurbo]]
deps = ["CEnum", "FileIO", "ImageCore", "JpegTurbo_jll", "TOML"]
git-tree-sha1 = "fa6d0bcff8583bac20f1ffa708c3913ca605c611"
uuid = "b835a17e-a41a-41e7-81f0-2f016b05efe0"
version = "0.1.5"

[[JpegTurbo_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "3336abae9a713d2210bb57ab484b1e065edd7d23"
uuid = "aacddb02-875f-59d6-b918-886e6ef4fbf8"
version = "3.0.2+0"

[[JuliaInterpreter]]
deps = ["CodeTracking", "InteractiveUtils", "Random", "UUIDs"]
git-tree-sha1 = "e9648d90370e2d0317f9518c9c6e0841db54a90b"
uuid = "aa1ae85d-cabe-5617-a682-6adf51b2e16a"
version = "0.9.31"

[[JuliaVariables]]
deps = ["MLStyle", "NameResolution"]
git-tree-sha1 = "49fb3cb53362ddadb4415e9b73926d6b40709e70"
uuid = "b14d175d-62b4-44ba-8fb7-3064adc8c3ec"
version = "0.2.4"

[[Kaleido_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "43032da5832754f58d14a91ffbe86d5f176acda9"
uuid = "f7e6163d-2fa5-5f23-b69c-1db539e41963"
version = "0.2.1+0"

[[LAME_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "f6250b16881adf048549549fba48b1161acdac8c"
uuid = "c1c5ebd0-6772-5130-a774-d5fcae4a789d"
version = "3.100.1+0"

[[LERC_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "bf36f528eec6634efc60d7ec062008f171071434"
uuid = "88015f11-f218-50d7-93a8-a6af411a945d"
version = "3.0.0+1"

[[LLVMOpenMP_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "d986ce2d884d49126836ea94ed5bfb0f12679713"
uuid = "1d63c593-3942-5779-bab2-d838dc0a180e"
version = "15.0.7+0"

[[LZO_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "e5b909bcf985c5e2605737d2ce278ed791b89be6"
uuid = "dd4b983a-f0e5-5f8d-a1b7-129d4a5fb1ac"
version = "2.10.1+0"

[[LaTeXStrings]]
git-tree-sha1 = "50901ebc375ed41dbf8058da26f9de442febbbec"
uuid = "b964fa9f-0449-5b57-a5c2-d3ea65f4040f"
version = "1.3.1"

[[Latexify]]
deps = ["Format", "InteractiveUtils", "LaTeXStrings", "MacroTools", "Markdown", "OrderedCollections", "Requires"]
git-tree-sha1 = "e0b5cd21dc1b44ec6e64f351976f961e6f31d6c4"
uuid = "23fbe1c1-3f47-55db-b15f-69d7ec21a316"
version = "0.16.3"

    [Latexify.extensions]
    DataFramesExt = "DataFrames"
    SymEngineExt = "SymEngine"

    [Latexify.weakdeps]
    DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
    SymEngine = "123dc426-2d89-5057-bbad-38513e3affd8"

[[LayoutPointers]]
deps = ["ArrayInterface", "LinearAlgebra", "ManualMemory", "SIMDTypes", "Static"]
git-tree-sha1 = "9e72f9e890c46081dbc0ebeaf6ccaffe16e51626"
uuid = "10f19ff3-798f-405d-979b-55457f8fc047"
version = "0.1.8"

[[Lazy]]
deps = ["MacroTools"]
git-tree-sha1 = "1370f8202dac30758f3c345f9909b97f53d87d3f"
uuid = "50d2b5c4-7a5e-59d5-8109-a42b560f39c0"
version = "0.15.1"

[[LazyArtifacts]]
deps = ["Artifacts", "Pkg"]
uuid = "4af54fe1-eca0-43a8-85a7-787d91b784e3"

[[LazyGrids]]
deps = ["Statistics"]
git-tree-sha1 = "f43d10fea7e448a60e92976bbd8bfbca7a6e5d09"
uuid = "7031d0ef-c40d-4431-b2f8-61a8d2f650db"
version = "0.5.0"

[[LazyModules]]
git-tree-sha1 = "a560dd966b386ac9ae60bdd3a3d3a326062d3c3e"
uuid = "8cdb02fc-e678-4876-92c5-9defec4f444e"
version = "0.3.1"

[[LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"
version = "0.6.4"

[[LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"
version = "8.4.0+0"

[[LibGit2]]
deps = ["Base64", "LibGit2_jll", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"

[[LibGit2_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll"]
uuid = "e37daf67-58a4-590a-8e99-b0245dd2ffc5"
version = "1.6.4+0"

[[LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "MbedTLS_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"
version = "1.11.0+1"

[[Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"

[[Libffi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "0b4a5d71f3e5200a7dff793393e09dfc2d874290"
uuid = "e9f186c6-92d2-5b65-8a66-fee21dc1b490"
version = "3.2.2+1"

[[Libgcrypt_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libgpg_error_jll"]
git-tree-sha1 = "9fd170c4bbfd8b935fdc5f8b7aa33532c991a673"
uuid = "d4300ac3-e22c-5743-9152-c294e39db1e4"
version = "1.8.11+0"

[[Libglvnd_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll", "Xorg_libXext_jll"]
git-tree-sha1 = "6f73d1dd803986947b2c750138528a999a6c7733"
uuid = "7e76a0d4-f3c7-5321-8279-8d96eeed0f29"
version = "1.6.0+0"

[[Libgpg_error_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "c333716e46366857753e273ce6a69ee0945a6db9"
uuid = "7add5ba3-2f88-524e-9cd5-f83b8a55f7b8"
version = "1.42.0+0"

[[Libiconv_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "f9557a255370125b405568f9767d6d195822a175"
uuid = "94ce4f54-9a6c-5748-9c1c-f9c7231a4531"
version = "1.17.0+0"

[[Libmount_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "4b683b19157282f50bfd5dcaa2efe5295814ea22"
uuid = "4b2f31a3-9ecc-558c-b454-b3730dcb73e9"
version = "2.40.0+0"

[[Libtiff_jll]]
deps = ["Artifacts", "JLLWrappers", "JpegTurbo_jll", "LERC_jll", "Libdl", "Pkg", "Zlib_jll", "Zstd_jll"]
git-tree-sha1 = "3eb79b0ca5764d4799c06699573fd8f533259713"
uuid = "89763e89-9b03-5906-acba-b20f662cd828"
version = "4.4.0+0"

[[Libuuid_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "27fd5cc10be85658cacfe11bb81bee216af13eda"
uuid = "38a345b3-de98-5d2b-a5d3-14cd9215e700"
version = "2.40.0+0"

[[LinearAlgebra]]
deps = ["Libdl", "OpenBLAS_jll", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"

[[LittleCMS_jll]]
deps = ["Artifacts", "JLLWrappers", "JpegTurbo_jll", "Libdl", "Libtiff_jll", "Pkg"]
git-tree-sha1 = "110897e7db2d6836be22c18bffd9422218ee6284"
uuid = "d3a379c0-f9a3-5b72-a4c0-6bf4d2e8af0f"
version = "2.12.0+0"

[[LogExpFunctions]]
deps = ["DocStringExtensions", "IrrationalConstants", "LinearAlgebra"]
git-tree-sha1 = "18144f3e9cbe9b15b070288eef858f71b291ce37"
uuid = "2ab3a3ac-af41-5b50-aa03-7779005ae688"
version = "0.3.27"

    [LogExpFunctions.extensions]
    LogExpFunctionsChainRulesCoreExt = "ChainRulesCore"
    LogExpFunctionsChangesOfVariablesExt = "ChangesOfVariables"
    LogExpFunctionsInverseFunctionsExt = "InverseFunctions"

    [LogExpFunctions.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    ChangesOfVariables = "9e997f8a-9a97-42d5-a9f1-ce6bfc15e2c0"
    InverseFunctions = "3587e190-3f89-42d0-90ee-14403ec27112"

[[Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"

[[LoggingExtras]]
deps = ["Dates", "Logging"]
git-tree-sha1 = "c1dd6d7978c12545b4179fb6153b9250c96b0075"
uuid = "e6f89c97-d47a-5376-807f-9c37f3926c36"
version = "1.0.3"

[[LoopVectorization]]
deps = ["ArrayInterface", "CPUSummary", "CloseOpenIntervals", "DocStringExtensions", "HostCPUFeatures", "IfElse", "LayoutPointers", "LinearAlgebra", "OffsetArrays", "PolyesterWeave", "Requires", "SIMDDualNumbers", "SLEEFPirates", "Static", "ThreadingUtilities", "UnPack", "VectorizationBase"]
git-tree-sha1 = "9e10579c154f785b911d9ceb96c33fcc1a661171"
uuid = "bdcacae8-1622-11e9-2a5c-532679323890"
version = "0.12.99"

[[LoweredCodeUtils]]
deps = ["JuliaInterpreter"]
git-tree-sha1 = "31e27f0b0bf0df3e3e951bfcc43fe8c730a219f6"
uuid = "6f1432cf-f94c-5a45-995e-cdbf5db27b0b"
version = "2.4.5"

[[MIMEs]]
git-tree-sha1 = "65f28ad4b594aebe22157d6fac869786a255b7eb"
uuid = "6c6e2e6c-3030-632d-7369-2d6c69616d65"
version = "0.1.4"

[[MKL_jll]]
deps = ["Artifacts", "IntelOpenMP_jll", "JLLWrappers", "LazyArtifacts", "Libdl", "oneTBB_jll"]
git-tree-sha1 = "80b2833b56d466b3858d565adcd16a4a05f2089b"
uuid = "856f044c-d86e-5d09-b602-aeab76dc8ba7"
version = "2024.1.0+0"

[[MLStyle]]
git-tree-sha1 = "bc38dff0548128765760c79eb7388a4b37fae2c8"
uuid = "d8e11817-5142-5d16-987a-aa16d5891078"
version = "0.4.17"

[[MacroTools]]
deps = ["Markdown", "Random"]
git-tree-sha1 = "2fa9ee3e63fd3a4f7a9a4f4744a52f4856de82df"
uuid = "1914dd2f-81c6-5fcd-8719-6d5c9610ff09"
version = "0.5.13"

[[ManualMemory]]
git-tree-sha1 = "bcaef4fc7a0cfe2cba636d84cda54b5e4e4ca3cd"
uuid = "d125e4d3-2237-4719-b19c-fa641b8a4667"
version = "0.1.8"

[[MappedArrays]]
git-tree-sha1 = "2dab0221fe2b0f2cb6754eaa743cc266339f527e"
uuid = "dbb5928d-eab1-5f90-85c2-b9b0edb7c900"
version = "0.4.2"

[[Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"

[[MbedTLS]]
deps = ["Dates", "MbedTLS_jll", "MozillaCACerts_jll", "NetworkOptions", "Random", "Sockets"]
git-tree-sha1 = "c067a280ddc25f196b5e7df3877c6b226d390aaf"
uuid = "739be429-bea8-5141-9913-cc70e7f3736d"
version = "1.1.9"

[[MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"
version = "2.28.2+1"

[[Measures]]
git-tree-sha1 = "c13304c81eec1ed3af7fc20e75fb6b26092a1102"
uuid = "442fdcdd-2543-5da2-b0f3-8c86c306513e"
version = "0.3.2"

[[Memoize]]
deps = ["MacroTools"]
git-tree-sha1 = "2b1dfcba103de714d31c033b5dacc2e4a12c7caa"
uuid = "c03570c3-d221-55d1-a50c-7939bbd78826"
version = "0.4.4"

[[MetaGraphs]]
deps = ["Graphs", "JLD2", "Random"]
git-tree-sha1 = "1130dbe1d5276cb656f6e1094ce97466ed700e5a"
uuid = "626554b9-1ddb-594c-aa3c-2596fe9399a5"
version = "0.7.2"

[[MicroCollections]]
deps = ["BangBang", "InitialValues", "Setfield"]
git-tree-sha1 = "629afd7d10dbc6935ec59b32daeb33bc4460a42e"
uuid = "128add7d-3638-4c79-886c-908ea0c25c34"
version = "0.1.4"

[[Missings]]
deps = ["DataAPI"]
git-tree-sha1 = "ec4f7fbeab05d7747bdf98eb74d130a2a2ed298d"
uuid = "e1d29d7a-bbdc-5cf2-9ac0-f12de2c33e28"
version = "1.2.0"

[[Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"

[[Mocking]]
deps = ["Compat", "ExprTools"]
git-tree-sha1 = "bf17d9cb4f0d2882351dfad030598f64286e5936"
uuid = "78c3b35d-d492-501b-9361-3d52fe80e533"
version = "0.7.8"

[[MosaicViews]]
deps = ["MappedArrays", "OffsetArrays", "PaddedViews", "StackViews"]
git-tree-sha1 = "7b86a5d4d70a9f5cdf2dacb3cbe6d251d1a61dbe"
uuid = "e94cdb99-869f-56ef-bcf0-1ae2bcbe0389"
version = "0.3.4"

[[MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"
version = "2023.1.10"

[[Mustache]]
deps = ["Printf", "Tables"]
git-tree-sha1 = "a7cefa21a2ff993bff0456bf7521f46fc077ddf1"
uuid = "ffc61752-8dc7-55ee-8c37-f3e9cdd09e70"
version = "1.0.19"

[[Mux]]
deps = ["AssetRegistry", "Base64", "HTTP", "Hiccup", "MbedTLS", "Pkg", "Sockets"]
git-tree-sha1 = "7295d849103ac4fcbe3b2e439f229c5cc77b9b69"
uuid = "a975b10e-0019-58db-a62f-e48ff68538c9"
version = "1.0.2"

[[NDTools]]
deps = ["LinearAlgebra", "OffsetArrays", "PaddedViews", "Random", "Statistics"]
git-tree-sha1 = "3e87b9a00ad1d7b0322150b1acba91f7e48792b5"
uuid = "98581153-e998-4eef-8d0d-5ec2c052313d"
version = "0.6.0"

[[NFFT]]
deps = ["AbstractNFFTs", "BasicInterpolators", "Distributed", "FFTW", "FLoops", "LinearAlgebra", "Printf", "Random", "Reexport", "SnoopPrecompile", "SparseArrays", "SpecialFunctions"]
git-tree-sha1 = "93a5f32dd6cf09456b0b81afcb8fc29f06535ffd"
uuid = "efe261a4-0d2b-5849-be55-fc731d526b0d"
version = "0.13.3"

[[NaNMath]]
deps = ["OpenLibm_jll"]
git-tree-sha1 = "0877504529a3e5c3343c6f8b4c0381e57e4387e4"
uuid = "77ba4419-2d1f-58cd-9bb1-8ffee604a2e3"
version = "1.0.2"

[[NameResolution]]
deps = ["PrettyPrint"]
git-tree-sha1 = "1a0fa0e9613f46c9b8c11eee38ebb4f590013c5e"
uuid = "71a1bf82-56d0-4bbc-8a3c-48b961074391"
version = "0.1.5"

[[NearestNeighbors]]
deps = ["Distances", "StaticArrays"]
git-tree-sha1 = "ded64ff6d4fdd1cb68dfcbb818c69e144a5b2e4c"
uuid = "b8a86587-4115-5ab1-83bc-aa920d37bbce"
version = "0.4.16"

[[Netpbm]]
deps = ["FileIO", "ImageCore", "ImageMetadata"]
git-tree-sha1 = "d92b107dbb887293622df7697a2223f9f8176fcd"
uuid = "f09324ee-3d7c-5217-9330-fc30815ba969"
version = "1.1.1"

[[NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"
version = "1.2.0"

[[Observables]]
git-tree-sha1 = "7438a59546cf62428fc9d1bc94729146d37a7225"
uuid = "510215fc-4207-5dde-b226-833fc4488ee2"
version = "0.5.5"

[[OffsetArrays]]
git-tree-sha1 = "e64b4f5ea6b7389f6f046d13d4896a8f9c1ba71e"
uuid = "6fe1bfb0-de20-5000-8ca7-80f57d26f881"
version = "1.14.0"
weakdeps = ["Adapt"]

    [OffsetArrays.extensions]
    OffsetArraysAdaptExt = "Adapt"

[[Ogg_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "887579a3eb005446d514ab7aeac5d1d027658b8f"
uuid = "e7412a2a-1a6e-54c0-be00-318e2571c051"
version = "1.3.5+1"

[[OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"
version = "0.3.23+4"

[[OpenEXR]]
deps = ["Colors", "FileIO", "OpenEXR_jll"]
git-tree-sha1 = "327f53360fdb54df7ecd01e96ef1983536d1e633"
uuid = "52e1d378-f018-4a11-a4be-720524705ac7"
version = "0.3.2"

[[OpenEXR_jll]]
deps = ["Artifacts", "Imath_jll", "JLLWrappers", "Libdl", "Zlib_jll"]
git-tree-sha1 = "a4ca623df1ae99d09bc9868b008262d0c0ac1e4f"
uuid = "18a262bb-aa17-5467-a713-aee519bc75cb"
version = "3.1.4+0"

[[OpenJpeg_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libtiff_jll", "LittleCMS_jll", "Pkg", "libpng_jll"]
git-tree-sha1 = "76374b6e7f632c130e78100b166e5a48464256f8"
uuid = "643b3616-a352-519d-856d-80112ee9badc"
version = "2.4.0+0"

[[OpenLibm_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "05823500-19ac-5b8b-9628-191a04bc5112"
version = "0.8.1+2"

[[OpenSSL]]
deps = ["BitFlags", "Dates", "MozillaCACerts_jll", "OpenSSL_jll", "Sockets"]
git-tree-sha1 = "38cb508d080d21dc1128f7fb04f20387ed4c0af4"
uuid = "4d8831e6-92b7-49fb-bdf8-b643e874388c"
version = "1.4.3"

[[OpenSSL_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "a12e56c72edee3ce6b96667745e6cbbe5498f200"
uuid = "458c3c95-2e84-50aa-8efc-19380b2a3a95"
version = "1.1.23+0"

[[OpenSpecFun_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "13652491f6856acfd2db29360e1bbcd4565d04f1"
uuid = "efe28fd5-8261-553b-a9e1-b2916fc3738e"
version = "0.5.5+0"

[[Opus_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "51a08fb14ec28da2ec7a927c4337e4332c2a4720"
uuid = "91d4177d-7536-5919-b921-800302f37372"
version = "1.3.2+0"

[[OrderedCollections]]
git-tree-sha1 = "dfdf5519f235516220579f949664f1bf44e741c5"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "1.6.3"

[[PCRE2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "efcefdf7-47ab-520b-bdef-62a2eaa19f15"
version = "10.42.0+1"

[[PNGFiles]]
deps = ["Base64", "CEnum", "ImageCore", "IndirectArrays", "OffsetArrays", "libpng_jll"]
git-tree-sha1 = "67186a2bc9a90f9f85ff3cc8277868961fb57cbd"
uuid = "f57f5aa1-a3ce-4bc8-8ab9-96f992907883"
version = "0.4.3"

[[PaddedViews]]
deps = ["OffsetArrays"]
git-tree-sha1 = "0fac6313486baae819364c52b4f483450a9d793f"
uuid = "5432bcbf-9aad-5242-b902-cca2824c8663"
version = "0.5.12"

[[Parameters]]
deps = ["OrderedCollections", "UnPack"]
git-tree-sha1 = "34c0e9ad262e5f7fc75b10a9952ca7692cfc5fbe"
uuid = "d96e819e-fc66-5662-9728-84c9c7592b0a"
version = "0.12.3"

[[Parsers]]
deps = ["Dates", "PrecompileTools", "UUIDs"]
git-tree-sha1 = "8489905bcdbcfac64d1daa51ca07c0d8f0283821"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.8.1"

[[Pidfile]]
deps = ["FileWatching", "Test"]
git-tree-sha1 = "2d8aaf8ee10df53d0dfb9b8ee44ae7c04ced2b03"
uuid = "fa939f87-e72e-5be4-a000-7fc836dbe307"
version = "1.3.0"

[[Pipe]]
git-tree-sha1 = "6842804e7867b115ca9de748a0cf6b364523c16d"
uuid = "b98c9c47-44ae-5843-9183-064241ee97a0"
version = "1.3.0"

[[Pixman_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "LLVMOpenMP_jll", "Libdl"]
git-tree-sha1 = "64779bc4c9784fee475689a1752ef4d5747c5e87"
uuid = "30392449-352a-5448-841d-b1acce4e97dc"
version = "0.42.2+0"

[[Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "FileWatching", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "REPL", "Random", "SHA", "Serialization", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"
version = "1.10.0"

[[PkgVersion]]
deps = ["Pkg"]
git-tree-sha1 = "f9501cc0430a26bc3d156ae1b5b0c1b47af4d6da"
uuid = "eebad327-c553-4316-9ea0-9fa01ccd7688"
version = "0.3.3"

[[PlotThemes]]
deps = ["PlotUtils", "Statistics"]
git-tree-sha1 = "1f03a2d339f42dca4a4da149c7e15e9b896ad899"
uuid = "ccf2f8ad-2431-5c83-bf29-c5338b663b6a"
version = "3.1.0"

[[PlotUtils]]
deps = ["ColorSchemes", "Colors", "Dates", "PrecompileTools", "Printf", "Random", "Reexport", "Statistics"]
git-tree-sha1 = "7b1a9df27f072ac4c9c7cbe5efb198489258d1f5"
uuid = "995b91a9-d308-5afd-9ec6-746e21dbc043"
version = "1.4.1"

[[PlotlyBase]]
deps = ["ColorSchemes", "Dates", "DelimitedFiles", "DocStringExtensions", "JSON", "LaTeXStrings", "Logging", "Parameters", "Pkg", "REPL", "Requires", "Statistics", "UUIDs"]
git-tree-sha1 = "56baf69781fc5e61607c3e46227ab17f7040ffa2"
uuid = "a03496cd-edff-5a9b-9e67-9cda94a718b5"
version = "0.8.19"

[[PlotlyJS]]
deps = ["Base64", "Blink", "DelimitedFiles", "JSExpr", "JSON", "Kaleido_jll", "Markdown", "Pkg", "PlotlyBase", "PlotlyKaleido", "REPL", "Reexport", "Requires", "WebIO"]
git-tree-sha1 = "e62d886d33b81c371c9d4e2f70663c0637f19459"
uuid = "f0f68f2c-4968-5e81-91da-67840de0976a"
version = "0.18.13"

    [PlotlyJS.extensions]
    CSVExt = "CSV"
    DataFramesExt = ["DataFrames", "CSV"]
    IJuliaExt = "IJulia"
    JSON3Ext = "JSON3"

    [PlotlyJS.weakdeps]
    CSV = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
    DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
    IJulia = "7073ff75-c697-5162-941a-fcdaad2a7d2a"
    JSON3 = "0f8b85d8-7281-11e9-16c2-39a750bddbf1"

[[PlotlyKaleido]]
deps = ["Base64", "JSON", "Kaleido_jll"]
git-tree-sha1 = "2650cd8fb83f73394996d507b3411a7316f6f184"
uuid = "f2990250-8cf9-495f-b13a-cce12b45703c"
version = "2.2.4"

[[Plots]]
deps = ["Base64", "Contour", "Dates", "Downloads", "FFMPEG", "FixedPointNumbers", "GR", "JLFzf", "JSON", "LaTeXStrings", "Latexify", "LinearAlgebra", "Measures", "NaNMath", "Pkg", "PlotThemes", "PlotUtils", "PrecompileTools", "Printf", "REPL", "Random", "RecipesBase", "RecipesPipeline", "Reexport", "RelocatableFolders", "Requires", "Scratch", "Showoff", "SparseArrays", "Statistics", "StatsBase", "UUIDs", "UnicodeFun", "UnitfulLatexify", "Unzip"]
git-tree-sha1 = "442e1e7ac27dd5ff8825c3fa62fbd1e86397974b"
uuid = "91a5bcdd-55d7-5caf-9e0b-520d859cae80"
version = "1.40.4"

    [Plots.extensions]
    FileIOExt = "FileIO"
    GeometryBasicsExt = "GeometryBasics"
    IJuliaExt = "IJulia"
    ImageInTerminalExt = "ImageInTerminal"
    UnitfulExt = "Unitful"

    [Plots.weakdeps]
    FileIO = "5789e2e9-d7fb-5bc7-8068-2c6fae9b9549"
    GeometryBasics = "5c1252a2-5f33-56bf-86c9-59e7332b4326"
    IJulia = "7073ff75-c697-5162-941a-fcdaad2a7d2a"
    ImageInTerminal = "d8c32880-2388-543b-8c61-d9f865259254"
    Unitful = "1986cc42-f94f-5a68-af5c-568840ba703d"

[[PlutoHooks]]
deps = ["InteractiveUtils", "Markdown", "UUIDs"]
git-tree-sha1 = "072cdf20c9b0507fdd977d7d246d90030609674b"
uuid = "0ff47ea0-7a50-410d-8455-4348d5de0774"
version = "0.0.5"

[[PlutoLinks]]
deps = ["FileWatching", "InteractiveUtils", "Markdown", "PlutoHooks", "Revise", "UUIDs"]
git-tree-sha1 = "8f5fa7056e6dcfb23ac5211de38e6c03f6367794"
uuid = "0ff47ea0-7a50-410d-8455-4348d5de0420"
version = "0.1.6"

[[PlutoTeachingTools]]
deps = ["Downloads", "HypertextLiteral", "LaTeXStrings", "Latexify", "Markdown", "PlutoLinks", "PlutoUI", "Random"]
git-tree-sha1 = "5d9ab1a4faf25a62bb9d07ef0003396ac258ef1c"
uuid = "661c6b06-c737-4d37-b85c-46df65de6f69"
version = "0.2.15"

[[PlutoUI]]
deps = ["AbstractPlutoDingetjes", "Base64", "ColorTypes", "Dates", "FixedPointNumbers", "Hyperscript", "HypertextLiteral", "IOCapture", "InteractiveUtils", "JSON", "Logging", "MIMEs", "Markdown", "Random", "Reexport", "URIs", "UUIDs"]
git-tree-sha1 = "ab55ee1510ad2af0ff674dbcced5e94921f867a9"
uuid = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
version = "0.7.59"

[[PolyesterWeave]]
deps = ["BitTwiddlingConvenienceFunctions", "CPUSummary", "IfElse", "Static", "ThreadingUtilities"]
git-tree-sha1 = "43883d15c7cf16f340b9367c645cf88372f55641"
uuid = "1d0040c9-8b98-4ee7-8388-3f51789ca0ad"
version = "0.1.13"

[[Polynomials]]
deps = ["Intervals", "LinearAlgebra", "OffsetArrays", "RecipesBase"]
git-tree-sha1 = "0b15f3597b01eb76764dd03c3c23d6679a3c32c8"
uuid = "f27b6e38-b328-58d1-80ce-0feddd5e7a45"
version = "1.2.1"

[[PrecompileTools]]
deps = ["Preferences"]
git-tree-sha1 = "5aa36f7049a63a1528fe8f7c3f2113413ffd4e1f"
uuid = "aea7be01-6a6a-4083-8856-8a6e6704d82a"
version = "1.2.1"

[[Preferences]]
deps = ["TOML"]
git-tree-sha1 = "9306f6085165d270f7e3db02af26a400d580f5c6"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.4.3"

[[PrettyPrint]]
git-tree-sha1 = "632eb4abab3449ab30c5e1afaa874f0b98b586e4"
uuid = "8162dcfd-2161-5ef2-ae6c-7681170c5f98"
version = "0.2.0"

[[Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"

[[Profile]]
deps = ["Printf"]
uuid = "9abbd945-dff8-562f-b5e8-e1ebf5ef1b79"

[[ProgressLogging]]
deps = ["Logging", "SHA", "UUIDs"]
git-tree-sha1 = "80d919dee55b9c50e8d9e2da5eeafff3fe58b539"
uuid = "33c8b6b6-d38a-422a-b730-caa89a2f386c"
version = "0.1.4"

[[ProgressMeter]]
deps = ["Distributed", "Printf"]
git-tree-sha1 = "763a8ceb07833dd51bb9e3bbca372de32c0605ad"
uuid = "92933f4c-e287-5a05-a399-4b506db050ca"
version = "1.10.0"

[[QOI]]
deps = ["ColorTypes", "FileIO", "FixedPointNumbers"]
git-tree-sha1 = "18e8f4d1426e965c7b532ddd260599e1510d26ce"
uuid = "4b34888f-f399-49d4-9bb3-47ed5cae4e65"
version = "1.0.0"

[[Qt5Base_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Fontconfig_jll", "Glib_jll", "JLLWrappers", "Libdl", "Libglvnd_jll", "OpenSSL_jll", "Pkg", "Xorg_libXext_jll", "Xorg_libxcb_jll", "Xorg_xcb_util_image_jll", "Xorg_xcb_util_keysyms_jll", "Xorg_xcb_util_renderutil_jll", "Xorg_xcb_util_wm_jll", "Zlib_jll", "xkbcommon_jll"]
git-tree-sha1 = "0c03844e2231e12fda4d0086fd7cbe4098ee8dc5"
uuid = "ea2cea3b-5b76-57ae-a6ef-0a8af62496e1"
version = "5.15.3+2"

[[QuartzImageIO]]
deps = ["FileIO", "ImageCore", "Libdl"]
git-tree-sha1 = "b674d5959e6be88b40905bdc8c905986fc95d51d"
uuid = "dca85d43-d64c-5e67-8c65-017450d5d020"
version = "0.7.5"

[[Quaternions]]
deps = ["LinearAlgebra", "Random", "RealDot"]
git-tree-sha1 = "994cc27cdacca10e68feb291673ec3a76aa2fae9"
uuid = "94ee1d12-ae83-5a48-8b1c-48b8ff168ae0"
version = "0.7.6"

[[REPL]]
deps = ["InteractiveUtils", "Markdown", "Sockets", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"

[[Random]]
deps = ["SHA"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[[RangeArrays]]
git-tree-sha1 = "b9039e93773ddcfc828f12aadf7115b4b4d225f5"
uuid = "b3c3ace0-ae52-54e7-9d0b-2c1406fd6b9d"
version = "0.3.2"

[[Ratios]]
deps = ["Requires"]
git-tree-sha1 = "1342a47bf3260ee108163042310d26f2be5ec90b"
uuid = "c84ed2f1-dad5-54f0-aa8e-dbefe2724439"
version = "0.4.5"
weakdeps = ["FixedPointNumbers"]

    [Ratios.extensions]
    RatiosFixedPointNumbersExt = "FixedPointNumbers"

[[RealDot]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "9f0a1b71baaf7650f4fa8a1d168c7fb6ee41f0c9"
uuid = "c1ae055f-0cd5-4b69-90a6-9a35b1a98df9"
version = "0.1.0"

[[RecipesBase]]
deps = ["PrecompileTools"]
git-tree-sha1 = "5c3d09cc4f31f5fc6af001c250bf1278733100ff"
uuid = "3cdcf5f2-1ef4-517c-9805-6587b60abb01"
version = "1.3.4"

[[RecipesPipeline]]
deps = ["Dates", "NaNMath", "PlotUtils", "PrecompileTools", "RecipesBase"]
git-tree-sha1 = "45cf9fd0ca5839d06ef333c8201714e888486342"
uuid = "01d81517-befc-4cb6-b9ec-a95719d0359c"
version = "0.6.12"

[[Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[RegionTrees]]
deps = ["IterTools", "LinearAlgebra", "StaticArrays"]
git-tree-sha1 = "4618ed0da7a251c7f92e869ae1a19c74a7d2a7f9"
uuid = "dee08c22-ab7f-5625-9660-a9af2021b33f"
version = "0.3.2"

[[RelocatableFolders]]
deps = ["SHA", "Scratch"]
git-tree-sha1 = "ffdaf70d81cf6ff22c2b6e733c900c3321cab864"
uuid = "05181044-ff0b-4ac5-8273-598c1e38db00"
version = "1.0.1"

[[Requires]]
deps = ["UUIDs"]
git-tree-sha1 = "838a3a4188e2ded87a4f9f184b4b0d78a1e91cb7"
uuid = "ae029012-a4dd-5104-9daa-d747884805df"
version = "1.3.0"

[[Revise]]
deps = ["CodeTracking", "Distributed", "FileWatching", "JuliaInterpreter", "LibGit2", "LoweredCodeUtils", "OrderedCollections", "Pkg", "REPL", "Requires", "UUIDs", "Unicode"]
git-tree-sha1 = "12aa2d7593df490c407a3bbd8b86b8b515017f3e"
uuid = "295af30f-e4ad-537b-8983-00126c2a3abe"
version = "3.5.14"

[[Rotations]]
deps = ["LinearAlgebra", "Quaternions", "Random", "StaticArrays"]
git-tree-sha1 = "2a0a5d8569f481ff8840e3b7c84bbf188db6a3fe"
uuid = "6038ab10-8711-5258-84ad-4b1120ba62dc"
version = "1.7.0"
weakdeps = ["RecipesBase"]

    [Rotations.extensions]
    RotationsRecipesBaseExt = "RecipesBase"

[[SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"
version = "0.7.0"

[[SIMDDualNumbers]]
deps = ["ForwardDiff", "IfElse", "SLEEFPirates", "VectorizationBase"]
git-tree-sha1 = "dd4195d308df24f33fb10dde7c22103ba88887fa"
uuid = "3cdde19b-5bb0-4aaf-8931-af3e248e098b"
version = "0.1.1"

[[SIMDTypes]]
git-tree-sha1 = "330289636fb8107c5f32088d2741e9fd7a061a5c"
uuid = "94e857df-77ce-4151-89e5-788b33177be4"
version = "0.1.0"

[[SLEEFPirates]]
deps = ["IfElse", "Static", "VectorizationBase"]
git-tree-sha1 = "3aac6d68c5e57449f5b9b865c9ba50ac2970c4cf"
uuid = "476501e8-09a2-5ece-8869-fb82de89a1fa"
version = "0.6.42"

[[Scratch]]
deps = ["Dates"]
git-tree-sha1 = "3bac05bc7e74a75fd9cba4295cde4045d9fe2386"
uuid = "6c6a2e73-6563-6170-7368-637461726353"
version = "1.2.1"

[[Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[Setfield]]
deps = ["ConstructionBase", "Future", "MacroTools", "StaticArraysCore"]
git-tree-sha1 = "e2cc6d8c88613c05e1defb55170bf5ff211fbeac"
uuid = "efcf1570-3423-57d1-acb7-fd33fddbac46"
version = "1.1.1"

[[SharedArrays]]
deps = ["Distributed", "Mmap", "Random", "Serialization"]
uuid = "1a1011a3-84de-559e-8e89-a11a2f7dc383"

[[ShiftedArrays]]
git-tree-sha1 = "503688b59397b3307443af35cd953a13e8005c16"
uuid = "1277b4bf-5013-50f5-be3d-901d8477a67a"
version = "2.0.0"

[[Showoff]]
deps = ["Dates", "Grisu"]
git-tree-sha1 = "91eddf657aca81df9ae6ceb20b959ae5653ad1de"
uuid = "992d4aef-0814-514b-bc4d-f2e9a6c4116f"
version = "1.0.3"

[[SimpleBufferStream]]
git-tree-sha1 = "874e8867b33a00e784c8a7e4b60afe9e037b74e1"
uuid = "777ac1f9-54b0-4bf8-805c-2214025038e7"
version = "1.1.0"

[[SimpleTraits]]
deps = ["InteractiveUtils", "MacroTools"]
git-tree-sha1 = "5d7e3f4e11935503d3ecaf7186eac40602e7d231"
uuid = "699a6c99-e7fa-54fc-8d76-47d257e15c1d"
version = "0.9.4"

[[SimpleWeightedGraphs]]
deps = ["Graphs", "LinearAlgebra", "Markdown", "SparseArrays"]
git-tree-sha1 = "4b33e0e081a825dbfaf314decf58fa47e53d6acb"
uuid = "47aef6b3-ad0c-573a-a1e2-d07658019622"
version = "1.4.0"

[[Sixel]]
deps = ["Dates", "FileIO", "ImageCore", "IndirectArrays", "OffsetArrays", "REPL", "libsixel_jll"]
git-tree-sha1 = "2da10356e31327c7096832eb9cd86307a50b1eb6"
uuid = "45858cf5-a6b0-47a3-bbea-62219f50df47"
version = "0.1.3"

[[SnoopPrecompile]]
deps = ["Preferences"]
git-tree-sha1 = "e760a70afdcd461cf01a575947738d359234665c"
uuid = "66db9d55-30c0-4569-8b51-7e840670fc0c"
version = "1.0.3"

[[Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"

[[SortingAlgorithms]]
deps = ["DataStructures"]
git-tree-sha1 = "66e0a8e672a0bdfca2c3f5937efb8538b9ddc085"
uuid = "a2af1166-a08f-5f64-846c-94a0d3cef48c"
version = "1.2.1"

[[SparseArrays]]
deps = ["Libdl", "LinearAlgebra", "Random", "Serialization", "SuiteSparse_jll"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"
version = "1.10.0"

[[SpecialFunctions]]
deps = ["OpenSpecFun_jll"]
git-tree-sha1 = "d8d8b8a9f4119829410ecd706da4cc8594a1e020"
uuid = "276daf66-3868-5448-9aa4-cd146d93841b"
version = "0.10.3"

[[SplittablesBase]]
deps = ["Setfield", "Test"]
git-tree-sha1 = "e08a62abc517eb79667d0a29dc08a3b589516bb5"
uuid = "171d559e-b47b-412a-8079-5efa626c420e"
version = "0.1.15"

[[StackViews]]
deps = ["OffsetArrays"]
git-tree-sha1 = "46e589465204cd0c08b4bd97385e4fa79a0c770c"
uuid = "cae243ae-269e-4f55-b966-ac2d0dc13c15"
version = "0.1.1"

[[Static]]
deps = ["IfElse"]
git-tree-sha1 = "a8f30abc7c64a39d389680b74e749cf33f872a70"
uuid = "aedffcd0-7271-4cad-89d0-dc628f76c6d3"
version = "0.3.3"

[[StaticArrays]]
deps = ["LinearAlgebra", "PrecompileTools", "Random", "StaticArraysCore"]
git-tree-sha1 = "bf074c045d3d5ffd956fa0a461da38a44685d6b2"
uuid = "90137ffa-7385-5640-81b9-e52037218182"
version = "1.9.3"
weakdeps = ["ChainRulesCore", "Statistics"]

    [StaticArrays.extensions]
    StaticArraysChainRulesCoreExt = "ChainRulesCore"
    StaticArraysStatisticsExt = "Statistics"

[[StaticArraysCore]]
git-tree-sha1 = "36b3d696ce6366023a0ea192b4cd442268995a0d"
uuid = "1e83bf80-4336-4d27-bf5d-d5a4f845583c"
version = "1.4.2"

[[Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"
version = "1.10.0"

[[StatsAPI]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "1ff449ad350c9c4cbc756624d6f8a8c3ef56d3ed"
uuid = "82ae8749-77ed-4fe6-ae5f-f523153014b0"
version = "1.7.0"

[[StatsBase]]
deps = ["DataAPI", "DataStructures", "LinearAlgebra", "LogExpFunctions", "Missings", "Printf", "Random", "SortingAlgorithms", "SparseArrays", "Statistics", "StatsAPI"]
git-tree-sha1 = "5cf7606d6cef84b543b483848d4ae08ad9832b21"
uuid = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"
version = "0.34.3"

[[StringDistances]]
deps = ["Distances", "StatsAPI"]
git-tree-sha1 = "5b2ca70b099f91e54d98064d5caf5cc9b541ad06"
uuid = "88034a9c-02f8-509d-84a9-84ec65e18404"
version = "0.11.3"

[[SuiteSparse_jll]]
deps = ["Artifacts", "Libdl", "libblastrampoline_jll"]
uuid = "bea87d4a-7f5b-5778-9afe-8cc45184846c"
version = "7.2.1+1"

[[TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"
version = "1.0.3"

[[TZJData]]
deps = ["Artifacts"]
git-tree-sha1 = "1607ad46cf8d642aa779a1d45af1c8620dbf6915"
uuid = "dc5dba14-91b3-4cab-a142-028a31da12f7"
version = "1.2.0+2024a"

[[TableTraits]]
deps = ["IteratorInterfaceExtensions"]
git-tree-sha1 = "c06b2f539df1c6efa794486abfb6ed2022561a39"
uuid = "3783bdb8-4a98-5b6b-af9a-565f29a5fe9c"
version = "1.0.1"

[[Tables]]
deps = ["DataAPI", "DataValueInterfaces", "IteratorInterfaceExtensions", "LinearAlgebra", "OrderedCollections", "TableTraits"]
git-tree-sha1 = "cb76cf677714c095e535e3501ac7954732aeea2d"
uuid = "bd369af6-aec1-5ad0-b16a-f7cc5008161c"
version = "1.11.1"

[[Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"
version = "1.10.0"

[[TensorCore]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "1feb45f88d133a655e001435632f019a9a1bcdb6"
uuid = "62fd8b95-f654-4bbd-a8a5-9c27f68ccd50"
version = "0.1.1"

[[Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[TestImages]]
deps = ["AxisArrays", "ColorTypes", "FileIO", "ImageIO", "ImageMagick", "OffsetArrays", "Pkg", "StringDistances"]
git-tree-sha1 = "0567860ec35a94c087bd98f35de1dddf482d7c67"
uuid = "5e47fb64-e119-507b-a336-dd2b206d9990"
version = "1.8.0"

[[ThreadingUtilities]]
deps = ["ManualMemory"]
git-tree-sha1 = "884539ba8c4584a3a8173cb4ee7b61049955b79c"
uuid = "8290d209-cae3-49c0-8002-c8c24d57dab5"
version = "0.4.7"

[[TiffImages]]
deps = ["ColorTypes", "DataStructures", "DocStringExtensions", "FileIO", "FixedPointNumbers", "IndirectArrays", "Inflate", "Mmap", "OffsetArrays", "PkgVersion", "ProgressMeter", "UUIDs"]
git-tree-sha1 = "34cc045dd0aaa59b8bbe86c644679bc57f1d5bd0"
uuid = "731e570b-9d59-4bfa-96dc-6df516fadf69"
version = "0.6.8"

[[TiledIteration]]
deps = ["ArrayInterface", "OffsetArrays"]
git-tree-sha1 = "1bf2bb587a7fc99fefac2ff076b18b500128e9c0"
uuid = "06e1c1a7-607b-532d-9fad-de7d9aa2abac"
version = "0.4.2"

[[TimeZones]]
deps = ["Dates", "Downloads", "InlineStrings", "Mocking", "Printf", "Scratch", "TZJData", "Unicode", "p7zip_jll"]
git-tree-sha1 = "96793c9316d6c9f9be4641f2e5b1319a205e6f27"
uuid = "f269a46b-ccf7-5d73-abea-4c690281aa53"
version = "1.15.0"
weakdeps = ["RecipesBase"]

    [TimeZones.extensions]
    TimeZonesRecipesBaseExt = "RecipesBase"

[[TimerOutputs]]
deps = ["ExprTools", "Printf"]
git-tree-sha1 = "f548a9e9c490030e545f72074a41edfd0e5bcdd7"
uuid = "a759f4b9-e2f1-59dc-863e-4aeb61b1ea8f"
version = "0.5.23"

[[TranscodingStreams]]
git-tree-sha1 = "71509f04d045ec714c4748c785a59045c3736349"
uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
version = "0.10.7"
weakdeps = ["Random", "Test"]

    [TranscodingStreams.extensions]
    TestExt = ["Test", "Random"]

[[Transducers]]
deps = ["Adapt", "ArgCheck", "BangBang", "Baselet", "CompositionsBase", "ConstructionBase", "DefineSingletons", "Distributed", "InitialValues", "Logging", "Markdown", "MicroCollections", "Requires", "Setfield", "SplittablesBase", "Tables"]
git-tree-sha1 = "3064e780dbb8a9296ebb3af8f440f787bb5332af"
uuid = "28d57a85-8fef-5791-bfe6-a80928e7c999"
version = "0.4.80"

    [Transducers.extensions]
    TransducersBlockArraysExt = "BlockArrays"
    TransducersDataFramesExt = "DataFrames"
    TransducersLazyArraysExt = "LazyArrays"
    TransducersOnlineStatsBaseExt = "OnlineStatsBase"
    TransducersReferenceablesExt = "Referenceables"

    [Transducers.weakdeps]
    BlockArrays = "8e7c35d0-a365-5155-bbbb-fb81a777f24e"
    DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
    LazyArrays = "5078a376-72f3-5289-bfd5-ec5146d43c02"
    OnlineStatsBase = "925886fa-5bf2-5e8e-b522-a9147a512338"
    Referenceables = "42d2dcc6-99eb-4e98-b66c-637b7d73030e"

[[Tricks]]
git-tree-sha1 = "eae1bb484cd63b36999ee58be2de6c178105112f"
uuid = "410a4b4d-49e4-4fbc-ab6d-cb71b17b3775"
version = "0.1.8"

[[URIs]]
git-tree-sha1 = "67db6cc7b3821e19ebe75791a9dd19c9b1188f2b"
uuid = "5c2747f8-b7ea-4ff2-ba2e-563bfd36b1d4"
version = "1.5.1"

[[UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"

[[UnPack]]
git-tree-sha1 = "387c1f73762231e86e0c9c5443ce3b4a0a9a0c2b"
uuid = "3a884ed6-31ef-47d7-9d2a-63182c4928ed"
version = "1.0.2"

[[Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"

[[UnicodeFun]]
deps = ["REPL"]
git-tree-sha1 = "53915e50200959667e78a92a418594b428dffddf"
uuid = "1cfade01-22cf-5700-b092-accc4b62d6e1"
version = "0.4.1"

[[Unitful]]
deps = ["Dates", "LinearAlgebra", "Random"]
git-tree-sha1 = "3c793be6df9dd77a0cf49d80984ef9ff996948fa"
uuid = "1986cc42-f94f-5a68-af5c-568840ba703d"
version = "1.19.0"

    [Unitful.extensions]
    ConstructionBaseUnitfulExt = "ConstructionBase"
    InverseFunctionsUnitfulExt = "InverseFunctions"

    [Unitful.weakdeps]
    ConstructionBase = "187b0558-2788-49d3-abe0-74a17ed4e7c9"
    InverseFunctions = "3587e190-3f89-42d0-90ee-14403ec27112"

[[UnitfulLatexify]]
deps = ["LaTeXStrings", "Latexify", "Unitful"]
git-tree-sha1 = "e2d817cc500e960fdbafcf988ac8436ba3208bfd"
uuid = "45397f5d-5981-4c77-b2b3-fc36d6e9b728"
version = "1.6.3"

[[Unzip]]
git-tree-sha1 = "ca0969166a028236229f63514992fc073799bb78"
uuid = "41fe7b60-77ed-43a1-b4f0-825fd5a5650d"
version = "0.2.0"

[[VectorizationBase]]
deps = ["ArrayInterface", "CPUSummary", "HostCPUFeatures", "IfElse", "LayoutPointers", "Libdl", "LinearAlgebra", "SIMDTypes", "Static"]
git-tree-sha1 = "c95d242ade2d67c1510ce52d107cfca7a83e0b4e"
uuid = "3d5dd08c-fd9d-11e8-17fa-ed2836048c2f"
version = "0.21.33"

[[Wayland_jll]]
deps = ["Artifacts", "EpollShim_jll", "Expat_jll", "JLLWrappers", "Libdl", "Libffi_jll", "Pkg", "XML2_jll"]
git-tree-sha1 = "7558e29847e99bc3f04d6569e82d0f5c54460703"
uuid = "a2964d1f-97da-50d4-b82a-358c7fce9d89"
version = "1.21.0+1"

[[Wayland_protocols_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "93f43ab61b16ddfb2fd3bb13b3ce241cafb0e6c9"
uuid = "2381bf8a-dfd0-557d-9999-79630e7b1b91"
version = "1.31.0+0"

[[WebIO]]
deps = ["AssetRegistry", "Base64", "Distributed", "FunctionalCollections", "JSON", "Logging", "Observables", "Pkg", "Random", "Requires", "Sockets", "UUIDs", "WebSockets", "Widgets"]
git-tree-sha1 = "0eef0765186f7452e52236fa42ca8c9b3c11c6e3"
uuid = "0f1e0344-ec1d-5b48-a673-e5cf874b6c29"
version = "0.8.21"

[[WebSockets]]
deps = ["Base64", "Dates", "HTTP", "Logging", "Sockets"]
git-tree-sha1 = "4162e95e05e79922e44b9952ccbc262832e4ad07"
uuid = "104b5d7c-a370-577a-8038-80a2059c5097"
version = "1.6.0"

[[Widgets]]
deps = ["Colors", "Dates", "Observables", "OrderedCollections"]
git-tree-sha1 = "fcdae142c1cfc7d89de2d11e08721d0f2f86c98a"
uuid = "cc8bc4a8-27d6-5769-a93b-9d913e69aa62"
version = "0.6.6"

[[WoodburyMatrices]]
deps = ["LinearAlgebra", "SparseArrays"]
git-tree-sha1 = "c1a7aa6219628fcd757dede0ca95e245c5cd9511"
uuid = "efce3f68-66dc-5838-9240-27a6d6f5f9b6"
version = "1.0.0"

[[XML2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libiconv_jll", "Zlib_jll"]
git-tree-sha1 = "532e22cf7be8462035d092ff21fada7527e2c488"
uuid = "02c8fc9c-b97f-50b9-bbe4-9be30ff0a78a"
version = "2.12.6+0"

[[XSLT_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libgcrypt_jll", "Libgpg_error_jll", "Libiconv_jll", "Pkg", "XML2_jll", "Zlib_jll"]
git-tree-sha1 = "91844873c4085240b95e795f692c4cec4d805f8a"
uuid = "aed1982a-8fda-507f-9586-7b0439959a61"
version = "1.1.34+0"

[[Xorg_libX11_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Xorg_libxcb_jll", "Xorg_xtrans_jll"]
git-tree-sha1 = "afead5aba5aa507ad5a3bf01f58f82c8d1403495"
uuid = "4f6342f7-b3d2-589e-9d20-edeb45f2b2bc"
version = "1.8.6+0"

[[Xorg_libXau_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "6035850dcc70518ca32f012e46015b9beeda49d8"
uuid = "0c0b7dd1-d40b-584c-a123-a41640f87eec"
version = "1.0.11+0"

[[Xorg_libXcursor_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXfixes_jll", "Xorg_libXrender_jll"]
git-tree-sha1 = "12e0eb3bc634fa2080c1c37fccf56f7c22989afd"
uuid = "935fb764-8cf2-53bf-bb30-45bb1f8bf724"
version = "1.2.0+4"

[[Xorg_libXdmcp_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "34d526d318358a859d7de23da945578e8e8727b7"
uuid = "a3789734-cfe1-5b06-b2d0-1dd0d9d62d05"
version = "1.1.4+0"

[[Xorg_libXext_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "b7c0aa8c376b31e4852b360222848637f481f8c3"
uuid = "1082639a-0dae-5f34-9b06-72781eeb8cb3"
version = "1.3.4+4"

[[Xorg_libXfixes_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "0e0dc7431e7a0587559f9294aeec269471c991a4"
uuid = "d091e8ba-531a-589c-9de9-94069b037ed8"
version = "5.0.3+4"

[[Xorg_libXi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXext_jll", "Xorg_libXfixes_jll"]
git-tree-sha1 = "89b52bc2160aadc84d707093930ef0bffa641246"
uuid = "a51aa0fd-4e3c-5386-b890-e753decda492"
version = "1.7.10+4"

[[Xorg_libXinerama_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXext_jll"]
git-tree-sha1 = "26be8b1c342929259317d8b9f7b53bf2bb73b123"
uuid = "d1454406-59df-5ea1-beac-c340f2130bc3"
version = "1.1.4+4"

[[Xorg_libXrandr_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXext_jll", "Xorg_libXrender_jll"]
git-tree-sha1 = "34cea83cb726fb58f325887bf0612c6b3fb17631"
uuid = "ec84b674-ba8e-5d96-8ba1-2a689ba10484"
version = "1.5.2+4"

[[Xorg_libXrender_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "19560f30fd49f4d4efbe7002a1037f8c43d43b96"
uuid = "ea2f1a96-1ddc-540d-b46f-429655e07cfa"
version = "0.9.10+4"

[[Xorg_libpthread_stubs_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "8fdda4c692503d44d04a0603d9ac0982054635f9"
uuid = "14d82f49-176c-5ed1-bb49-ad3f5cbd8c74"
version = "0.1.1+0"

[[Xorg_libxcb_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "XSLT_jll", "Xorg_libXau_jll", "Xorg_libXdmcp_jll", "Xorg_libpthread_stubs_jll"]
git-tree-sha1 = "b4bfde5d5b652e22b9c790ad00af08b6d042b97d"
uuid = "c7cfdc94-dc32-55de-ac96-5a1b8d977c5b"
version = "1.15.0+0"

[[Xorg_libxkbfile_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Xorg_libX11_jll"]
git-tree-sha1 = "730eeca102434283c50ccf7d1ecdadf521a765a4"
uuid = "cc61e674-0454-545c-8b26-ed2c68acab7a"
version = "1.1.2+0"

[[Xorg_xcb_util_image_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "0fab0a40349ba1cba2c1da699243396ff8e94b97"
uuid = "12413925-8142-5f55-bb0e-6d7ca50bb09b"
version = "0.4.0+1"

[[Xorg_xcb_util_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libxcb_jll"]
git-tree-sha1 = "e7fd7b2881fa2eaa72717420894d3938177862d1"
uuid = "2def613f-5ad1-5310-b15b-b15d46f528f5"
version = "0.4.0+1"

[[Xorg_xcb_util_keysyms_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "d1151e2c45a544f32441a567d1690e701ec89b00"
uuid = "975044d2-76e6-5fbe-bf08-97ce7c6574c7"
version = "0.4.0+1"

[[Xorg_xcb_util_renderutil_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "dfd7a8f38d4613b6a575253b3174dd991ca6183e"
uuid = "0d47668e-0667-5a69-a72c-f761630bfb7e"
version = "0.3.9+1"

[[Xorg_xcb_util_wm_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "e78d10aab01a4a154142c5006ed44fd9e8e31b67"
uuid = "c22f9ab0-d5fe-5066-847c-f4bb1cd4e361"
version = "0.4.1+1"

[[Xorg_xkbcomp_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Xorg_libxkbfile_jll"]
git-tree-sha1 = "330f955bc41bb8f5270a369c473fc4a5a4e4d3cb"
uuid = "35661453-b289-5fab-8a00-3d9160c6a3a4"
version = "1.4.6+0"

[[Xorg_xkeyboard_config_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Xorg_xkbcomp_jll"]
git-tree-sha1 = "691634e5453ad362044e2ad653e79f3ee3bb98c3"
uuid = "33bec58e-1273-512f-9401-5d533626f822"
version = "2.39.0+0"

[[Xorg_xtrans_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "e92a1a012a10506618f10b7047e478403a046c77"
uuid = "c5fb5394-a638-5e4d-96e5-b29de1b5cf10"
version = "1.5.0+0"

[[Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"
version = "1.2.13+1"

[[Zstd_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "e678132f07ddb5bfa46857f0d7620fb9be675d3b"
uuid = "3161d3a3-bdf6-5164-811a-617609db77b4"
version = "1.5.6+0"

[[fzf_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "a68c9655fbe6dfcab3d972808f1aafec151ce3f8"
uuid = "214eeab7-80f7-51ab-84ad-2988db7cef09"
version = "0.43.0+0"

[[libaom_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "3a2ea60308f0996d26f1e5354e10c24e9ef905d4"
uuid = "a4ae2306-e953-59d6-aa16-d00cac43593b"
version = "3.4.0+0"

[[libass_jll]]
deps = ["Artifacts", "Bzip2_jll", "FreeType2_jll", "FriBidi_jll", "HarfBuzz_jll", "JLLWrappers", "Libdl", "Pkg", "Zlib_jll"]
git-tree-sha1 = "5982a94fcba20f02f42ace44b9894ee2b140fe47"
uuid = "0ac62f75-1d6f-5e53-bd7c-93b484bb37c0"
version = "0.15.1+0"

[[libblastrampoline_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"
version = "5.8.0+1"

[[libfdk_aac_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "daacc84a041563f965be61859a36e17c4e4fcd55"
uuid = "f638f0a6-7fb0-5443-88ba-1cc74229b280"
version = "2.0.2+0"

[[libpng_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Zlib_jll"]
git-tree-sha1 = "d7015d2e18a5fd9a4f47de711837e980519781a4"
uuid = "b53b4c65-9356-5827-b1ea-8c7a1a84506f"
version = "1.6.43+1"

[[libsixel_jll]]
deps = ["Artifacts", "JLLWrappers", "JpegTurbo_jll", "Libdl", "Pkg", "libpng_jll"]
git-tree-sha1 = "d4f63314c8aa1e48cd22aa0c17ed76cd1ae48c3c"
uuid = "075b6546-f08a-558a-be8f-8157d0f608a5"
version = "1.10.3+0"

[[libvorbis_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Ogg_jll", "Pkg"]
git-tree-sha1 = "b910cb81ef3fe6e78bf6acee440bda86fd6ae00c"
uuid = "f27f6e37-5d2b-51aa-960f-b287f2bc3b7a"
version = "1.3.7+1"

[[nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"
version = "1.52.0+1"

[[oneTBB_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "7d0ea0f4895ef2f5cb83645fa689e52cb55cf493"
uuid = "1317d2d5-d96f-522e-a858-c73665f53c3e"
version = "2021.12.0+0"

[[p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"
version = "17.4.0+2"

[[x264_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4fea590b89e6ec504593146bf8b988b2c00922b2"
uuid = "1270edf5-f2f9-52d2-97e9-ab00b5d0237a"
version = "2021.5.5+0"

[[x265_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "ee567a171cce03570d77ad3a43e90218e38937a9"
uuid = "dfaa095f-4041-5dcd-9319-2fabd8486b76"
version = "3.5.0+0"

[[xkbcommon_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Wayland_jll", "Wayland_protocols_jll", "Xorg_libxcb_jll", "Xorg_xkeyboard_config_jll"]
git-tree-sha1 = "9c304562909ab2bab0262639bd4f444d7bc2be37"
uuid = "d8fb68d0-12a3-5cfd-a85a-d49703b185fd"
version = "1.4.1+1"
"""

# ╔═╡ Cell order:
# ╟─9a8d10f7-e387-46c0-aaa4-df825d7fd143
# ╟─af5d6dcd-2663-419a-90ab-a4e3b7b567eb
# ╟─640c5c2e-a463-4041-a6a5-867cf9a4dd1c
# ╟─f47f01a1-cb57-43c7-b323-73a63858c532
# ╟─69e56aef-0ceb-4cb2-bdec-e6f23e145b5b
# ╟─92b03dd1-0466-48ec-84e5-f3c05251ae8f
# ╟─328bd3ac-b559-43f6-b4f6-ddcf33ee06eb
# ╠═351cfd74-e7fb-4ad7-ba54-3c64eb9134c1
# ╠═556b65ee-f79d-402f-a48c-8e0ce65cc499
# ╠═bc2fa5a2-82e5-4602-9a68-3248662ed917
# ╠═829e9956-f198-46db-b98f-cdb9e0e57536
# ╠═b8cdde01-ebc8-4a84-96aa-8bad2264a5ab
# ╠═9e994b57-876a-43da-b479-519737dda20b
# ╟─4f761eb7-0428-4ace-bd52-c1e30f169e5a
# ╠═a3eeaff1-1f98-4b9e-ace9-2d3a5c0110bf
# ╟─e2482eb4-2bbd-4fef-9572-16287f0d11de
# ╠═35cbfad7-825d-4961-b24d-56f8cb70a513
# ╠═57e9ca9d-9427-40bd-8945-3c9f64dd600a
# ╠═2f5afb7c-8b1c-4592-bf2a-4259030a1009
# ╠═54e4d041-0476-48d6-974d-7b0820a6f1ed
# ╟─36127489-a94e-4ca8-afd1-4db7575a0b81
# ╟─70ad1a78-ddf2-41bb-b488-e64c6acc5e5d
# ╟─e44a420c-7355-46a9-a87b-754bb15c6483
# ╟─95e08cb9-bda6-4ac9-8c30-65f3228efa2c
# ╟─98b5c944-20fd-481f-a945-fc8cd997e9aa
# ╟─b1987990-4097-11eb-0b47-a5a4066542c3
# ╠═81c811fa-77d6-11eb-317b-654187ffcd48
# ╟─74904e50-a788-4710-87d3-53e7f53972e6
# ╟─6274213d-915c-433b-99ea-9388b6286ea1
# ╟─0f21175d-d4d8-418a-a038-91a4cd6fab39
# ╠═fae6711e-650c-48e9-86cd-8444b4adcde9
# ╠═5c00adf5-7148-4a31-b667-28ce74105cb1
# ╠═b6dfbf4a-148f-43d6-96b8-52da7802b4af
# ╠═344b90cf-2eac-4c98-b3c3-7d72b743fb29
# ╠═fa530546-233a-42fc-a8c2-7d41a2ceff89
# ╠═ec6f05d6-cef8-449b-8020-40a9621b0b89
# ╠═8c98fed2-7f04-4ded-95cd-4f957deb8581
# ╠═431fff7c-8a82-4197-8e7d-11a74fd271f8
# ╠═3c9e67b8-a232-4d47-a04c-57a76f4b2afb
# ╠═d5c4a808-06be-4992-9ad2-d7480c6898e3
# ╠═f54518c6-f215-4438-a1e6-81c93e9cca4f
# ╟─81f6131a-84f5-42b9-af6a-5eb35e459efe
# ╠═ef1c75f7-f833-406b-84f1-672276b9f282
# ╠═f4527ccf-ffcc-402f-b22d-542e2efdb75a
# ╟─d5719963-e960-499a-bc36-d258d829ada0
# ╟─11725909-3a35-485b-8295-098917ef4c92
# ╟─bc55d354-8ee0-4fe1-92b7-967cdb51dc2e
# ╟─59abdc6e-eff9-490d-be7a-1808a6a8c808
# ╟─16253161-0e9c-4b5d-bf81-0dd2a35812a8
# ╟─3207f15d-aaf6-4f57-b8a0-c8f7c83293a3
# ╟─75870b96-527b-49c7-9b11-05f12be34a56
# ╟─abb11bb2-876a-49b3-866c-4b3b9e8fc7f5
# ╟─51a7dbdc-af5a-4c6e-a406-cd98fb96d464
# ╟─a0230cb0-3536-4d9e-beb9-9dcf5e38700a
# ╟─53031cc2-5191-4457-b28f-a7133d0bdafd
# ╟─9820b76a-4b42-41cb-b9f1-eebcc8b6f507
# ╟─5b7e57a6-3f27-464b-8781-64134aa6a1ca
# ╟─64c5375b-0bab-45c9-bdaf-223a7b77ede2
# ╟─0cf2d97d-9ad0-40a8-8807-8e3cccaa25db
# ╟─79bdf5b6-76dd-40ea-a713-ac394ca53b4c
# ╟─2bf78920-2e25-4b42-823c-2874a4d8c3cb
# ╟─5f80f6de-6041-456d-a2a6-7ce741779691
# ╟─01a1aeb2-b136-49de-a48f-fc7a7a3b143a
# ╟─121dae3d-6731-4207-bb51-e9e79f0d93f8
# ╟─173bbd6a-16eb-473a-8aaa-5efb92150124
# ╟─0ce01c4b-fe97-4208-995a-beb2f8e98e23
# ╟─b034e3e2-4b52-4655-ac7c-756c0f45da12
# ╟─4d071a23-a75b-4415-8903-77ee4bec3dd0
# ╠═34028967-3c01-49f2-877e-7d557873689c
# ╟─0c72b231-1bbe-4066-bd64-5f5d963d1d98
# ╟─069947d4-c67f-4039-95d7-6049aa415847
# ╟─5adb649d-0165-4503-bc51-1f876573a1a4
# ╟─35d55d37-559d-4606-bb8a-209a29798ce2
# ╟─9e296c81-2438-4c84-9be3-7c64ea1634b1
# ╟─93b85f08-36c1-480f-9057-0f1ca65d99c4
# ╟─6e9b127b-7bcd-43b7-9571-2e4a52600c66
# ╠═06d42379-e45e-4082-9b9e-2386c224a313
# ╟─f8e8cdf3-3b8b-48c6-9476-84acb3cfb808
# ╟─edcaf4f8-77f5-4ceb-8370-6490c2b825f3
# ╟─52debc73-6c49-4eb8-b83a-1c643ee48bb4
# ╟─d9b4bf70-c032-4fea-9f8f-a0716cf04767
# ╟─9a6f26c4-35f9-4627-aee2-3f7641ba2138
# ╟─12bd7c0d-063a-4d1a-925e-868e625123a4
# ╟─7b8609ac-8198-48f9-8b43-79f577668527
# ╟─0379641b-62e7-4118-be6d-4af457481a90
# ╟─c864f046-3f0b-11eb-3973-4f53d2419f30
# ╠═a5816c6c-3fc4-11eb-3356-e19b884ebb0d
# ╟─bb9a52ae-8929-4656-a985-15bad69216f8
# ╟─73918b6a-60bd-4c57-8963-d9a6da3c2d38
# ╟─f41607f8-cd04-4937-8c59-c952221f9112
# ╟─5ac55af9-b174-44e8-a9fa-8790c20bd0be
# ╟─20f5da3a-6180-4412-b746-61273c77587e
# ╠═60218002-f04c-4b35-8d72-7228338a665a
# ╠═75b66ef5-972b-412b-aee5-d63791de9b7f
# ╠═bc851704-6b05-4398-8152-2955fed0a704
# ╠═bf6b94ea-4caa-419f-a166-ffeb9d311a9e
# ╠═6c42ea7c-d1ed-445c-bb6c-0c23f1a63dab
# ╠═449a1328-e17d-4d1a-9a85-384d4fe801b4
# ╠═81d2d4d8-489f-4cb3-8bbf-387e9a577148
# ╠═8bc690fa-409a-11eb-0f03-cf55800897bb
# ╠═a9c30e06-a931-4dfe-90ab-bacd5d532159
# ╟─6ca9a99a-8f25-47ec-bce5-3f847570879c
# ╟─7e003a22-ed86-4e13-8a52-66609a7e8c15
# ╠═7628b409-86e2-41d6-ab82-62175eabaf49
# ╟─47dde459-4cb4-4bf5-a4df-6c54b545d07c
# ╟─5992a716-65e6-4d55-981e-efbe88ccf8ba
# ╟─91c66b4d-029d-45d9-a992-1a05db6ae0ac
# ╟─a72c6eba-4c1e-44f0-b9c2-c9bfabd43106
# ╟─3c68a8ec-4ffd-47fc-a9dc-3f2af9b89d07
# ╠═dc401f46-4f9b-4679-84eb-860c3c11b82c
# ╠═c6932382-5ac5-4d5a-af59-3c22141ac2ea
# ╠═bf8befeb-0a82-4722-b76a-f912cead0e7d
# ╠═b6b10e8e-059f-4e20-927e-f9ffcacd5516
# ╠═d13dc80d-7c2f-4642-9569-8ada8e3c769d
# ╠═026fb497-dbed-4dec-9e9d-4f8dc7f88409
# ╠═1a8c1acc-eeac-42ce-a933-2d50d89804bd
# ╠═0d617142-237e-47be-852e-fe7fab7eeed0
# ╠═3413c40e-d3dc-478b-bd08-40accb34e86e
# ╠═2ed6f4cd-5062-47a7-a429-8fb976bac7a4
# ╠═4e5d95e5-e895-484c-8def-51d4f38b3103
# ╟─51cdbd12-38ea-44ff-a5cd-12f88b664a13
# ╠═deca9332-8df0-4cf3-bb22-9db514a364a8
# ╠═ff04ec0b-4ba4-4b14-9f31-e753c9456a45
# ╠═0de3996e-1604-44bc-b16f-ebf638b1250b
# ╠═7004ea3e-7e0b-47fa-b5d1-e004b72919ec
# ╠═ee501cd2-5994-4c21-b2f6-7f5ae5085cf6
# ╠═df92f9a8-3296-4613-8ec8-aa83894c41c3
# ╠═7789a11d-8e19-4988-962c-a273a12c916b
# ╠═b5dfef37-0aaf-4fd1-8c4e-f629216a6f27
# ╠═7f37b5d1-ae65-41e3-b9de-9bacf73005d3
# ╠═005d09bd-5f61-4b3c-8531-0080d92661ca
# ╟─34227e32-ca2d-4099-8f52-f7842491c0a5
# ╠═9dfa5cf9-ce6e-4578-8a8c-df6bdeaafe0f
# ╟─34dfa9e2-528a-443e-80d5-39ee2050089a
# ╠═9f7c161f-185d-4c10-88a5-e781ef06ba05
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
