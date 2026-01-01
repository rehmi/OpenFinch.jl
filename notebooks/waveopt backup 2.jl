### A Pluto.jl notebook ###
# v0.20.4

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    #! format: off
    quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
    #! format: on
end

# ╔═╡ e9ebc395-2d85-4319-82fe-1362e279dc3b
using TimerOutputs; to = TimerOutput();

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
	import Unitful
	using Unitful: nm, µm, mm, cm, m
	using Unitful: uconvert, upreferred, ustrip, @u_str, Quantity
	# using DynamicQuantities
	# const U = DynamicQuantities.Units
	# const C = DynamicQuantities.Constants
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

	using FourierTools: resample  # override DSP.resample
	using DSP: conv
	
	using LinearAlgebra: BLAS

	THREADS = Threads.nthreads()
	FFTW.set_num_threads(THREADS)
	BLAS.set_num_threads(THREADS)
	
	# Not sure why this is necessary, but it mitigates type errors
	# that occur when a {Complex} type reaches plan_fft()
	FFTW.fft(x::Matrix{Complex}) = fft(ComplexF32.(x))
	# FourierTools.resample(m::Matrix{Complex}, args...) = resample(ComplexF32.(m), args...)

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
	Enable Table of Contents $(@bind enable_TOC CheckBox(true)) 
	
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

# ╔═╡ 75530dd1-c7e4-4d1f-92c5-3f016201643f
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

# ╔═╡ 351cfd74-e7fb-4ad7-ba54-3c64eb9134c1
begin
	
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

# ╔═╡ b7076e05-da65-47a1-b893-dc4acb5973d4
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
clock; begin
	function pull_msgs(conn)
		msg = take!(conn)
			if msg isa Array
				return msg
			else
				return pull_msgs(conn)
			end
	end
	msg = pull_msgs(openfinch)
end
  ╠═╡ =#

# ╔═╡ 0a372f1f-13d3-4cba-a631-9933acef094b
#=╠═╡
decode_image(msg)
  ╠═╡ =#

# ╔═╡ 7e8d972c-d5c0-4442-bae5-d957afebfa1b
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
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
  ╠═╡ =#

# ╔═╡ 829e9956-f198-46db-b98f-cdb9e0e57536
@bind clock Clock(1)

# ╔═╡ b8cdde01-ebc8-4a84-96aa-8bad2264a5ab
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
send_controls(openfinch, Dict("LED_TIME" => 0, "LED_WIDTH" => 100))
  ╠═╡ =#

# ╔═╡ 9e994b57-876a-43da-b479-519737dda20b
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
put!(openfinch, Dict(
	"use_base64_encoding"=>Dict("value"=>false),
	"send_fps_updates"=>Dict("value"=>false),
	"stream_frames"=>Dict("value"=>true),
))
  ╠═╡ =#

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

# ╔═╡ 35cbfad7-825d-4961-b24d-56f8cb70a513
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
send_controls(openfinch, Dict(
	"LED_TIME" => LED_TIME,
	"LED_WIDTH" => LED_WIDTH,
	"ColourGains" => [red_gain, blue_gain],
	"AnalogueGain" => analog_gain,
	"ScalerCrop" => [3, 0, 1456, 1088] # [384, 0, 1024, 768]
));
  ╠═╡ =#

# ╔═╡ 57e9ca9d-9427-40bd-8945-3c9f64dd600a
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
send_image(openfinch, imresize(testimage("resolution_test_512"), ratio=image_scale));
  ╠═╡ =#

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

# ╔═╡ 2bb0d5cd-70aa-4707-9636-fdd226987571
md"""
## Generate and send interferograms
"""

# ╔═╡ 91a97369-e493-4ef7-9b84-f55b02fe084e
# ╠═╡ disabled = true
#=╠═╡
@bind f Slider(0.1:0.1:100, default=10, show_value=true)
  ╠═╡ =#

# ╔═╡ 95e08cb9-bda6-4ac9-8c30-65f3228efa2c
md"""
## Test wave optics model
"""

# ╔═╡ 51a7dbdc-af5a-4c6e-a406-cd98fb96d464
md"""
## Simulation parameters
"""

# ╔═╡ a0230cb0-3536-4d9e-beb9-9dcf5e38700a
md"Use impulse as point source for PSF calculation: $(@bind PSF_source_impulse CheckBox())"

# ╔═╡ 53031cc2-5191-4457-b28f-a7133d0bdafd
md"""Source wavelengths for PSF calculation: $(@bind PSF_source_RGB Select(["RGB", "R", "G", "B"]))"""

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

# ╔═╡ 9820b76a-4b42-41cb-b9f1-eebcc8b6f507
md"Simulation resolution: N=$(@bind N_sim Select(repr.([256, 512, 1024, 1280, 1536, 2048, 2560, 3072, 3584, 4096, 6144, 8192, 10240, 12288, 16384])))"

# ╔═╡ 5b7e57a6-3f27-464b-8781-64134aa6a1ca
md"""
Propagator type: $(@bind propstring Select([
	"PropFresnel"	=> "Fresnel kernel convolution",
	"PropTF"		=> "Transfer function propagator [Voelz]",
	"PropIR"		=> "Impulse response propagator [Voelz]",
]))
"""

# ╔═╡ 6274213d-915c-433b-99ea-9388b6286ea1
md"""
Diffraction slice side length: $(@bind propL Slider(0.1:0.1:5.0, default=1, show_value=true)) mm

Propagation distance: $(@bind propdist Slider(0.0:0.1:1000.0, default=10.0, show_value=true)) mm
"""

# ╔═╡ 06d42379-e45e-4082-9b9e-2386c224a313
to

# ╔═╡ ec4ca41e-d56a-4178-978d-bab10430eaff
# ╠═╡ disabled = true
#=╠═╡
	# difference = normalize(backward) - normalize(initial)
	# abs2(normalize(initial)) - abs2(normalize(backward))
	normalize(initial.ϕ[1] ./ backward.ϕ[1])
	
	# ComplexF32.([initial forward; backward difference])
	# ComplexToHSV.(normalize(initial))
  ╠═╡ =#

# ╔═╡ 5581eaba-7639-4717-8ded-2313e2383275
# ╠═╡ disabled = true
#=╠═╡
Gray.(normalize(abs.(forward.ϕ[1])))
  ╠═╡ =#

# ╔═╡ b9c1c4a5-d7be-40ca-a78d-b6741ad37b20
# ╠═╡ disabled = true
#=╠═╡
begin
	md"""
	| Initial light field | Forward to $(dist) | Backward to 0 mm |
	| :-: | :-: | :-: |
	| $(abs2(initial)) | $(abs2(forward)) | $(abs2(backward)) |
	| | pixel pitch: $(uconvert(u"µm", propL*1mm/N)) | |
	"""
end
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

# ╔═╡ 6ca9a99a-8f25-47ec-bce5-3f847570879c
md"""
## Mapping wavelengths to XYZ colorspace
"""

# ╔═╡ d5719963-e960-499a-bc36-d258d829ada0
md"""
# Calculate PSF for given mask
"""

# ╔═╡ 64c5375b-0bab-45c9-bdaf-223a7b77ede2
#=╠═╡
md"""
| ``~~~~~~~~~~~~~~~~`` | `object` | `psf_amplitude` | `psf` |  |
| --: | :-: | :-: | :-: | :-: |
| | $(object) | $(psf_amplitude) | $(abs2(ϕ_image)^0.2) | |
"""
  ╠═╡ =#

# ╔═╡ 0cf2d97d-9ad0-40a8-8807-8e3cccaa25db
#=╠═╡
md"""
| ``~~~~~~~~~~~~~~~~`` | in | modulation | out |
| --: | :-: | :-: | :-: |
| mask | $((ϕ_into_mask)) | $((mask)) | $((ϕ_outof_mask)) |
"""
  ╠═╡ =#

# ╔═╡ 79bdf5b6-76dd-40ea-a713-ac394ca53b4c
#=╠═╡
md"""
| ``~~~~~~~~~~~~~~~~`` | in | modulation | out |
| --: | :-: | :-: | :-: |
| lens | $((ϕ_into_lens)) | $((ϕ_lens)) | $((ϕ_outof_lens)) |
"""
  ╠═╡ =#

# ╔═╡ 2bf78920-2e25-4b42-823c-2874a4d8c3cb
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
# convolve with spherical kernel to propagate distance z₁
# sphericalkernelG = acc_spherical_wavefront(xA, yA, z₁, kG)
# ϕ_into_lens = acc_convsame(obj.ϕ[1], sphericalkernelG)
ϕ_into_mask = propagate(object, dₒₘ, L1, prop=propfn);
  ╠═╡ =#

# ╔═╡ 5f80f6de-6041-456d-a2a6-7ce741779691
#=╠═╡
# modulate by mask transfer function
ϕ_outof_mask = ϕ_into_mask * mask;
  ╠═╡ =#

# ╔═╡ 01a1aeb2-b136-49de-a48f-fc7a7a3b143a
#=╠═╡
# ϕ_into_lens = ϕ_outof_mask;
ϕ_into_lens = propagate(ϕ_outof_mask, dₘₗ, L1, prop=propfn);
  ╠═╡ =#

# ╔═╡ 173bbd6a-16eb-473a-8aaa-5efb92150124
#=╠═╡
# modulate by lens transfer function
ϕ_outof_lens = ϕ_into_lens * PhasorField(ϕ_lens);
  ╠═╡ =#

# ╔═╡ 0ce01c4b-fe97-4208-995a-beb2f8e98e23
#=╠═╡
# propagate distance L to image place
ϕ_image = propagate(ϕ_outof_lens, dₗₛ, L1, prop=propfn);
  ╠═╡ =#

# ╔═╡ b034e3e2-4b52-4655-ac7c-756c0f45da12
#=╠═╡
# LightField([λG], [ϕ_image.ϕ])
psf_amplitude = ϕ_image;
  ╠═╡ =#

# ╔═╡ 4d071a23-a75b-4415-8903-77ee4bec3dd0
#=╠═╡
begin
	psf = (abs2.(psf_amplitude.ϕ[1]));
	psf /= sum(psf);
end;
  ╠═╡ =#

# ╔═╡ 34028967-3c01-49f2-877e-7d557873689c
@bind psf_prop_dist Slider(0.0:0.01:2.0, default=1.0, show_value=true)

# ╔═╡ 0c72b231-1bbe-4066-bd64-5f5d963d1d98
#=╠═╡
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
  ╠═╡ =#

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

# ╔═╡ a2c111b5-1505-4dff-9b05-60ac0738bc4f
md"""
## Photon sampling
"""

# ╔═╡ fae6711e-650c-48e9-86cd-8444b4adcde9
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
vγ = mosaicview(RGB.(γ_cshots[(1:Int(floor(sqrt(length(cshots))))).^2]), ncol=4, rowmajor=true)
  ╠═╡ =#

# ╔═╡ 5c00adf5-7148-4a31-b667-28ce74105cb1
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
ganim
  ╠═╡ =#

# ╔═╡ b6dfbf4a-148f-43d6-96b8-52da7802b4af
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
begin
	# p = plot([])
	anim = @animate for i ∈ 1:length(cshots)
		plot([HSV(γ_cshots[i]) HSV(cshots[i])], legend=false, xaxis=false, yaxis=false, xticks=false, yticks=false, size=(2N,N))
		annotate!((0,0, (repr(i), :white, :top, :left)))
		# HSV(cshots[i])
	end
	ganim = gif(anim)
end;
  ╠═╡ =#

# ╔═╡ 344b90cf-2eac-4c98-b3c3-7d72b743fb29
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
plot([HSV(cshots[end]) HSV(γ_cshots[end])], size=(2N, N))
  ╠═╡ =#

# ╔═╡ fa530546-233a-42fc-a8c2-7d41a2ceff89
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
cshots = cumsum(abs2.(shots))
  ╠═╡ =#

# ╔═╡ ec6f05d6-cef8-449b-8020-40a9621b0b89
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
γ_cshots = cumsum(γ_shots)
  ╠═╡ =#

# ╔═╡ 8c98fed2-7f04-4ded-95cd-4f957deb8581
#=╠═╡
[ cshots[end] γ_cshots[end] ]
  ╠═╡ =#

# ╔═╡ 431fff7c-8a82-4197-8e7d-11a74fd271f8
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
γ_shots = γ_sample.(shots)
  ╠═╡ =#

# ╔═╡ 3c9e67b8-a232-4d47-a04c-57a76f4b2afb
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
γ_sample(shots[1])
  ╠═╡ =#

# ╔═╡ 2c706b58-e88e-4fb6-85d6-7c0763f93b1c
@benchmark sync(af_conv(a, k)) setup=(a=rand(AFArray{ComplexF32}, 4096, 4096); k=rand(AFArray{ComplexF32}, 4096, 4096))

# ╔═╡ 8de2bd97-85c9-4073-a2f8-241ca41224af
@benchmark sync(af_conv($(rand(AFArray{ComplexF32}, 4096, 4096)), $(rand(AFArray{ComplexF32}, 4096, 4096))))

# ╔═╡ 0c5e8fea-5ef4-4b25-bcd2-d1e55abf939a


# ╔═╡ c864f046-3f0b-11eb-3973-4f53d2419f30
md"""
---
# Definitions
"""

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

# ╔═╡ 0040ae65-fd55-447d-bc18-83eeec1c9492
begin
	dx = 4.25u"µm"

	Nx, Ny = 1280, 720
	Lx, Ly = dx.* (Nx, Ny)

	X = range(-Lx/2, Lx/2, Nx)
	Y = range(-Ly/2, Ly/2, Ny)

	X, Y = meshgrid(X, Y)
end

# ╔═╡ ef1c75f7-f833-406b-84f1-672276b9f282
begin
	randomizephase(A::Matrix) = cis.(2π*rand(Float32, size(A))) .* A
	randomizephase(lf::LightField) = LightField(lf.λ, randomizephase.(lf.ϕ))
	randomizephase(pf::PhasorField) = PhasorField(randomizephase.(pf.ϕ))
end

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

# ╔═╡ 9e296c81-2438-4c84-9be3-7c64ea1634b1
begin
	Base.real(lf::LightField) =
		LightField(lf.λ, [complex(real.(ϕ)) for ϕ ∈ lf.ϕ])

	Base.imag(lf::LightField) =
		LightField(lf.λ, [complex(imag.(ϕ)) for ϕ ∈ lf.ϕ])
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

# ╔═╡ d5c4a808-06be-4992-9ad2-d7480c6898e3
begin
	γ_sample(A::Matrix) = complex(real.(unitaryscale(abs2.(A))) .> rand(size(A)...))
	γ_sample(pf::PhasorField) = PhasorField(γ_sample(pf.ϕ))
	γ_sample(lf::LightField) = LightField(lf.λ, γ_sample(ϕ) for ϕ ∈ lf.ϕ)
end

# ╔═╡ d040afd4-05f7-4dc2-8ae9-9cd0ef05cee9
(N -> (2(N+1)^2 * 2log2(N+1)) / (N^2 * 2log2(N))).(2 .^(2:20))

# ╔═╡ 16f08d1c-7794-444e-94ae-e8892edf556a
let
	m = 2:16
	N = 2 .^ m
	f(n) = 2n*log2(n)
	bar(m, f.(N), xlims=(0,16))
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

# ╔═╡ 0796152d-e8b2-4d44-b239-1ee9a6afb8f7
afstat()

# ╔═╡ 6e9b127b-7bcd-43b7-9571-2e4a52600c66
function propFresnel(ϕ::Matrix, λ::Number, dist::Number, L1::Number)
	function af_spherical_wavefront(x, y, d, k)
		k1 = ComplexF32(ustrip(upreferred(1im*k)))
		xf = AFArray(Float32.(ustrip(upreferred.(x))))
		yf = AFArray(Float32.(ustrip(upreferred.(y))))
		rf = xf.*xf + yf.*yf + Float32(ustrip(upreferred(d^2)))
		sf = sqrt(rf)
		w = exp(k1*sf)
		# @timeit to "AFArray->Array" v = Array(w)
		# return v
	end

	function af_thin_lens(x, y, f, k)
		k1 = ComplexF32(ustrip(upreferred(1im*k)))
		xf = AFArray(Float32.(ustrip(upreferred.(x))))
		yf = AFArray(Float32.(ustrip(upreferred.(y))))
		f1 = Float32(ustrip(upreferred(f)))
		rf = xf.*xf + yf.*yf + f1^2
		sf = f1 .- sqrt(rf)
		l = exp(k1*sf)
		# @timeit to "AFArray->Array" v = Array(l)
	end
	
	function af_fresnel_kernel(x,y,d,k)
		c1 = ComplexF32(ustrip(upreferred(1im*(k/(2*d)))))
		xf = AFArray(Float32.(ustrip(upreferred.(x))))
		yf = AFArray(Float32.(ustrip(upreferred.(y))))
		k = exp(c1 * (xf.*xf + yf.*yf))
		# @timeit to "AFArray->Array" v = Array(k)
		# return v
	end

	function af_convsame(A,K)
		c = af_conv(A, K, expand=false, inplace=true)
	end

	@timeit to "propFresnel" begin
		@timeit_debug to "setup" begin
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
		aϕ = AFArray{ComplexF32}(ComplexF32.(ϕ))
		@timeit to "af_convsame$N" ϕ_out = sync(af_convsame(aϕ, K))
		@timeit to "AFArray->Array$N" Array(ϕ_out)
	end
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

# ╔═╡ 9cf9e1f0-54c6-48df-a397-0df955e4dd35
afstat()

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
		# λG = (λR + λB)/2
		
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
	
	# test_lf = LightField([λR, λG, λB], [test_color[:,:,i] for i ∈ 1:3])
	test_lf = LightField([λG], [test_color[:,:,2]])
	
	md"""
	| `test_lf` | `abs2(test_lf)` |
	| :-: | :-: |
	| $(test_lf) | $(abs2(test_lf)) |
	"""
end

# ╔═╡ 5fc5a119-3363-4ba5-a5c0-2a6ef4ddc2ee
begin
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
	nothing
end

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
@benchmark Array(fg())
  ╠═╡ =#

# ╔═╡ 005d09bd-5f61-4b3c-8531-0080d92661ca
# ╠═╡ skip_as_script = true
#=╠═╡
fc()
  ╠═╡ =#

# ╔═╡ 9dfa5cf9-ce6e-4578-8a8c-df6bdeaafe0f
# ╠═╡ skip_as_script = true
#=╠═╡
Array(fg())
  ╠═╡ =#

# ╔═╡ 504dcc12-6fb2-42cb-80a4-0005d122e17e
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
ws = rawws(URI)
  ╠═╡ =#

# ╔═╡ 6b682160-48d0-433c-9e5a-4e16bb6ee464
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
WebSockets.send(ws, JSON.json(Dict(
	"use_base64_encoding"=>Dict("value"=>false),
	"send_fps_updates"=>Dict("value"=>false),
	"stream_frames"=>Dict("value"=>false),
)))
  ╠═╡ =#

# ╔═╡ 55ceb925-8b2d-4ee9-94a9-ce4f6d8569b1
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
ws
  ╠═╡ =#

# ╔═╡ 171f099e-8fd1-4eb6-8572-a27e1b001b5a
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
send(ws, JSON.json(Dict("image_request"=>true)))
  ╠═╡ =#

# ╔═╡ Cell order:
# ╟─9a8d10f7-e387-46c0-aaa4-df825d7fd143
# ╟─af5d6dcd-2663-419a-90ab-a4e3b7b567eb
# ╟─640c5c2e-a463-4041-a6a5-867cf9a4dd1c
# ╟─f47f01a1-cb57-43c7-b323-73a63858c532
# ╟─69e56aef-0ceb-4cb2-bdec-e6f23e145b5b
# ╟─92b03dd1-0466-48ec-84e5-f3c05251ae8f
# ╟─75530dd1-c7e4-4d1f-92c5-3f016201643f
# ╟─328bd3ac-b559-43f6-b4f6-ddcf33ee06eb
# ╟─351cfd74-e7fb-4ad7-ba54-3c64eb9134c1
# ╠═556b65ee-f79d-402f-a48c-8e0ce65cc499
# ╠═bc2fa5a2-82e5-4602-9a68-3248662ed917
# ╠═b7076e05-da65-47a1-b893-dc4acb5973d4
# ╠═0a372f1f-13d3-4cba-a631-9933acef094b
# ╟─7e8d972c-d5c0-4442-bae5-d957afebfa1b
# ╠═829e9956-f198-46db-b98f-cdb9e0e57536
# ╠═b8cdde01-ebc8-4a84-96aa-8bad2264a5ab
# ╠═9e994b57-876a-43da-b479-519737dda20b
# ╟─e2482eb4-2bbd-4fef-9572-16287f0d11de
# ╟─4f761eb7-0428-4ace-bd52-c1e30f169e5a
# ╟─a3eeaff1-1f98-4b9e-ace9-2d3a5c0110bf
# ╠═35cbfad7-825d-4961-b24d-56f8cb70a513
# ╠═57e9ca9d-9427-40bd-8945-3c9f64dd600a
# ╠═2f5afb7c-8b1c-4592-bf2a-4259030a1009
# ╠═54e4d041-0476-48d6-974d-7b0820a6f1ed
# ╟─36127489-a94e-4ca8-afd1-4db7575a0b81
# ╟─70ad1a78-ddf2-41bb-b488-e64c6acc5e5d
# ╟─e44a420c-7355-46a9-a87b-754bb15c6483
# ╟─2bb0d5cd-70aa-4707-9636-fdd226987571
# ╠═91a97369-e493-4ef7-9b84-f55b02fe084e
# ╠═0040ae65-fd55-447d-bc18-83eeec1c9492
# ╟─95e08cb9-bda6-4ac9-8c30-65f3228efa2c
# ╟─abb11bb2-876a-49b3-866c-4b3b9e8fc7f5
# ╟─51a7dbdc-af5a-4c6e-a406-cd98fb96d464
# ╟─a0230cb0-3536-4d9e-beb9-9dcf5e38700a
# ╟─53031cc2-5191-4457-b28f-a7133d0bdafd
# ╟─98b5c944-20fd-481f-a945-fc8cd997e9aa
# ╟─b1987990-4097-11eb-0b47-a5a4066542c3
# ╠═81c811fa-77d6-11eb-317b-654187ffcd48
# ╟─74904e50-a788-4710-87d3-53e7f53972e6
# ╟─9820b76a-4b42-41cb-b9f1-eebcc8b6f507
# ╟─5b7e57a6-3f27-464b-8781-64134aa6a1ca
# ╟─6274213d-915c-433b-99ea-9388b6286ea1
# ╠═0796152d-e8b2-4d44-b239-1ee9a6afb8f7
# ╠═e9ebc395-2d85-4319-82fe-1362e279dc3b
# ╠═06d42379-e45e-4082-9b9e-2386c224a313
# ╠═5fc5a119-3363-4ba5-a5c0-2a6ef4ddc2ee
# ╠═6e9b127b-7bcd-43b7-9571-2e4a52600c66
# ╠═ec4ca41e-d56a-4178-978d-bab10430eaff
# ╠═5581eaba-7639-4717-8ded-2313e2383275
# ╠═b9c1c4a5-d7be-40ca-a78d-b6741ad37b20
# ╠═9cf9e1f0-54c6-48df-a397-0df955e4dd35
# ╠═f54518c6-f215-4438-a1e6-81c93e9cca4f
# ╟─81f6131a-84f5-42b9-af6a-5eb35e459efe
# ╟─ef1c75f7-f833-406b-84f1-672276b9f282
# ╟─f4527ccf-ffcc-402f-b22d-542e2efdb75a
# ╟─7e003a22-ed86-4e13-8a52-66609a7e8c15
# ╟─6ca9a99a-8f25-47ec-bce5-3f847570879c
# ╠═7628b409-86e2-41d6-ab82-62175eabaf49
# ╟─47dde459-4cb4-4bf5-a4df-6c54b545d07c
# ╟─d5719963-e960-499a-bc36-d258d829ada0
# ╠═11725909-3a35-485b-8295-098917ef4c92
# ╠═bc55d354-8ee0-4fe1-92b7-967cdb51dc2e
# ╠═16253161-0e9c-4b5d-bf81-0dd2a35812a8
# ╠═3207f15d-aaf6-4f57-b8a0-c8f7c83293a3
# ╠═75870b96-527b-49c7-9b11-05f12be34a56
# ╟─64c5375b-0bab-45c9-bdaf-223a7b77ede2
# ╟─0cf2d97d-9ad0-40a8-8807-8e3cccaa25db
# ╟─79bdf5b6-76dd-40ea-a713-ac394ca53b4c
# ╠═2bf78920-2e25-4b42-823c-2874a4d8c3cb
# ╠═5f80f6de-6041-456d-a2a6-7ce741779691
# ╠═01a1aeb2-b136-49de-a48f-fc7a7a3b143a
# ╠═121dae3d-6731-4207-bb51-e9e79f0d93f8
# ╠═173bbd6a-16eb-473a-8aaa-5efb92150124
# ╠═0ce01c4b-fe97-4208-995a-beb2f8e98e23
# ╠═b034e3e2-4b52-4655-ac7c-756c0f45da12
# ╠═4d071a23-a75b-4415-8903-77ee4bec3dd0
# ╠═34028967-3c01-49f2-877e-7d557873689c
# ╠═0c72b231-1bbe-4066-bd64-5f5d963d1d98
# ╠═069947d4-c67f-4039-95d7-6049aa415847
# ╠═5adb649d-0165-4503-bc51-1f876573a1a4
# ╠═35d55d37-559d-4606-bb8a-209a29798ce2
# ╠═9e296c81-2438-4c84-9be3-7c64ea1634b1
# ╠═93b85f08-36c1-480f-9057-0f1ca65d99c4
# ╠═f8e8cdf3-3b8b-48c6-9476-84acb3cfb808
# ╟─edcaf4f8-77f5-4ceb-8370-6490c2b825f3
# ╠═52debc73-6c49-4eb8-b83a-1c643ee48bb4
# ╠═d9b4bf70-c032-4fea-9f8f-a0716cf04767
# ╠═9a6f26c4-35f9-4627-aee2-3f7641ba2138
# ╠═12bd7c0d-063a-4d1a-925e-868e625123a4
# ╠═7b8609ac-8198-48f9-8b43-79f577668527
# ╠═0379641b-62e7-4118-be6d-4af457481a90
# ╟─a2c111b5-1505-4dff-9b05-60ac0738bc4f
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
# ╠═2c706b58-e88e-4fb6-85d6-7c0763f93b1c
# ╠═8de2bd97-85c9-4073-a2f8-241ca41224af
# ╠═0c5e8fea-5ef4-4b25-bcd2-d1e55abf939a
# ╠═d040afd4-05f7-4dc2-8ae9-9cd0ef05cee9
# ╠═16f08d1c-7794-444e-94ae-e8892edf556a
# ╟─c864f046-3f0b-11eb-3973-4f53d2419f30
# ╠═a5816c6c-3fc4-11eb-3356-e19b884ebb0d
# ╠═60218002-f04c-4b35-8d72-7228338a665a
# ╠═75b66ef5-972b-412b-aee5-d63791de9b7f
# ╠═bc851704-6b05-4398-8152-2955fed0a704
# ╠═bf6b94ea-4caa-419f-a166-ffeb9d311a9e
# ╟─6c42ea7c-d1ed-445c-bb6c-0c23f1a63dab
# ╟─449a1328-e17d-4d1a-9a85-384d4fe801b4
# ╠═81d2d4d8-489f-4cb3-8bbf-387e9a577148
# ╠═8bc690fa-409a-11eb-0f03-cf55800897bb
# ╠═a9c30e06-a931-4dfe-90ab-bacd5d532159
# ╟─5992a716-65e6-4d55-981e-efbe88ccf8ba
# ╟─91c66b4d-029d-45d9-a992-1a05db6ae0ac
# ╟─a72c6eba-4c1e-44f0-b9c2-c9bfabd43106
# ╟─3c68a8ec-4ffd-47fc-a9dc-3f2af9b89d07
# ╠═dc401f46-4f9b-4679-84eb-860c3c11b82c
# ╠═c6932382-5ac5-4d5a-af59-3c22141ac2ea
# ╠═bf8befeb-0a82-4722-b76a-f912cead0e7d
# ╟─b6b10e8e-059f-4e20-927e-f9ffcacd5516
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
# ╠═b5dfef37-0aaf-4fd1-8c4e-f629216a6f27
# ╠═7f37b5d1-ae65-41e3-b9de-9bacf73005d3
# ╠═005d09bd-5f61-4b3c-8531-0080d92661ca
# ╠═9dfa5cf9-ce6e-4578-8a8c-df6bdeaafe0f
# ╠═504dcc12-6fb2-42cb-80a4-0005d122e17e
# ╠═6b682160-48d0-433c-9e5a-4e16bb6ee464
# ╠═55ceb925-8b2d-4ee9-94a9-ce4f6d8569b1
# ╠═171f099e-8fd1-4eb6-8572-a27e1b001b5a
