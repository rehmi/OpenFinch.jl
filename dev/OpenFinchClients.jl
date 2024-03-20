module OpenFinchClients

export OpenFinchClient
export connect, send, receive
export send_control, set_camera_mode, send_image_request, send_image_update, listen

using HTTP
using HTTP.WebSockets
using JSON
using FileIO


"""
	OpenFinchClient

A mutable structure to represent a client for communicating with an OpenFinch device.
It holds the URI for connection and the WebSocket client instance.
"""
mutable struct OpenFinchClient
	uri::String
	ws::Union{Nothing,WebSocket}
	send_channel::Channel
	recv_channel::Channel
	ws_task::Union{Task,Nothing}
	send_task::Union{Task,Nothing}
	recv_task::Union{Task,Nothing}

	"""
		OpenFinchClient(uri::String)

	Construct a new OpenFinchClient with the provided URI and a `nothing` WebSocket.
	"""
	function OpenFinchClient(uri::String="ws://localhost:8000/ws")
		return new(uri, nothing, Channel{Any}(10), Channel{Any}(10), nothing, nothing, nothing)
	end
end


# The following commented code is an example of how to use a WebSocket
# created by HTTP.WebSockets. Note that all use of the WebSocket ws
# takes place in the body of the anonymous function passed to
# HTTP.WebSockets.open() by the `do` form.
#
using BenchmarkTools

function test_finch()
	@benchmark HTTP.WebSockets.open("ws://finch.local:8000/ws") do ws
		req = JSON.json(Dict("image_request" => Dict(
			"brightness" => "1.0", "contrast" => "1.0", "gamma" => "1.0"
		)))
		send(ws, req)
		msg = JSON.parse(receive(ws))
		if haskey(msg, "image_response")
			img_bin = receive(ws)
		end
	end
end

# 
# The code below doesn't work this way.

"""
	connect(client::OpenFinchClient)

Establish a WebSocket connection to the OpenFinch client's stored URI.
"""
function connect(client::OpenFinchClient)
	client.ws_task = @async HTTP.WebSockets.open(client.uri) do ws
		client.ws = ws

		client.recv_task = @async while isopen(ws)
			data = receive(ws)
			try
				put!(client.recv_channel, String(data))
			catch err
				println("recv_task: $err")
				sleep(1)
			end
		end

		client.send_task = @async while isopen(ws)
			if isready(client.send_channel)
				try
					message = take!(client.send_channel)
					send(ws, message)
				catch err
					println("send_task: $err")
					sleep(1)
				end
			end
		end
	end
end

function send(client::OpenFinchClient, message::String)
	put!(client.send_channel, message)
end

function receive(client::OpenFinchClient)
	return take!(client.recv_channel)
end


"""
	close(client::OpenFinchClient)

Close the WebSocket connection for the given OpenFinch client instance if it's open.
"""
function Base.close(client::OpenFinchClient)
	if !isnothing(client.ws)
		close(client.ws)
		client.ws = nothing
	end
end

"""
	send_control_command(client::OpenFinchClient, command::String, value::Any)

Send a control setting over the WebSocket connection in the JSON format.
"""
function send_control(client::OpenFinchClient, control::String, value::Any)
	message = JSON.json(Dict(control => Dict("value" => value)))
	write(client.ws, message)
end

"""
	set_camera_mode(client::OpenFinchClient, mode::Bool)

Set the camera mode for the OpenFinch client based on the provided boolean value:
'True' triggers "triggered" mode, 'False' triggers "freerunning" mode.
"""
function set_camera_mode(client::OpenFinchClient, mode::Bool)
	mode_value = mode ? "triggered" : "freerunning"
	send_control_command(client, "camera_mode", mode_value)
end

"""
	send_image_request(client::OpenFinchClient, brightness::String="1.0", contrast::String="1.0", gamma::String="1.0")

Send an image request with specified `brightness`, `contrast`, and `gamma` values over WebSocket.
Defaults are provided for each value.
"""
function send_image_request(client::OpenFinchClient, brightness::String="1.0", contrast::String="1.0", gamma::String="1.0")
	request = JSON.json(Dict("image_request" => Dict("brightness" => brightness, "contrast" => contrast, "gamma" => gamma)))
	write(client.ws, request)
end

"""
	send_image_update(client::OpenFinchClient, img_url_or_file::String)

Send an image update to the OpenFinch client. If `img_url_or_file` starts with "http://"
or "https://", it's treated as a URL and fetched; otherwise, it's assumed to be a local file path.
"""
function send_image_update(client::OpenFinchClient, img_url_or_file::String)
	if startswith(img_url_or_file, "http://") || startswith(img_url_or_file, "https://")
		response = HTTP.get(img_url_or_file)
		img_byte_arr = response.body
	else
		img = open(img_url_or_file) do f
			read(f)
		end
		img_byte_arr = img
	end

	write(client.ws, JSON.json(Dict("SLM_image" => "next")))
	write(client.ws, img_byte_arr)
end

"""
	listen(client::OpenFinchClient)

Continuously listen for messages on the OpenFinch client's WebSocket connection and print them.
This function blocks and runs indefinitely until an EOFError occurs, signalling the connection was closed.
"""
function listen(client::OpenFinchClient)
	while true
		try
			message = String(readavailable(client.ws))
			println("Received message: ", length(message) > 80 ? message[1:77] * "..." : message)
		catch e
			if isa(e, EOFError)
				println("Connection closed.")
				break
			else
				println("Error: ", e)
			end
		end
	end
end


end

# global img
# global times

# HTTP.WebSockets.open("ws://finch.local:8000/ws") do ws
# 	req = JSON.json(Dict("image_request" => Dict(
# 		"brightness"=>"1.0", "contrast"=>"1.0", "gamma"=>"1.0"
# 	)))

# 	global times = [ @elapsed begin
# 		send(ws, req)
# 		msg = JSON.parse(receive(ws))
# 		if haskey(msg, "image_response")
# 			img_bin = receive(ws)
# 			@Threads.spawn begin
# 				# global img
# 				# img = load(Stream{format"JPEG"}(IOBuffer(img_bin)))
# 				# display(img)
# 			end
# 		end
# 	end for i in 1:100 ]
# end

# using BenchmarkTools

# @benchmark HTTP.WebSockets.open("ws://finch.local:8000/ws") do ws
#     req = JSON.json(Dict("image_request" => Dict(
#         "brightness" => "1.0", "contrast" => "1.0", "gamma" => "1.0"
#     )))
#     send(ws, req)
#     msg = JSON.parse(receive(ws))
#     if haskey(msg, "image_response")
#         img_bin = receive(ws)
#     end
# end
