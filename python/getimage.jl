using HTTP
using HTTP.WebSockets
using JSON
using FileIO

global times
global msgs

HTTP.WebSockets.open("ws://finch.local:8000/ws") do ws
	req = JSON.json(Dict("image_request" => "now"))
	global msgs = []

	global times = [ @elapsed begin
		WebSockets.send(ws, req)
		msg = JSON.parse(WebSockets.receive(ws))
		if haskey(msg, "image_response")
			img_bin = WebSockets.receive(ws)
			@Threads.spawn begin
				global img
				img = load(Stream{format"JPEG"}(IOBuffer(img_bin)))
				display(img)
				push!(msgs, img)
			end
		else
			push!(msgs, msg)
		end
	end for i in 1:100 ]
end

using BenchmarkTools

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
