using HTTP
using HTTP.WebSockets
using JSON
using FileIO

global img
global times

HTTP.WebSockets.open("ws://finch.local:8000/ws") do ws
	req = JSON.json(Dict("image_request" => Dict(
		"brightness"=>"1.0", "contrast"=>"1.0", "gamma"=>"1.0"
	)))

	global times = [ @elapsed begin
		send(ws, req)
		msg = JSON.parse(receive(ws))
		if haskey(msg, "image_response")
			img_bin = receive(ws)
			@Threads.spawn begin
				# global img
				# img = load(Stream{format"JPEG"}(IOBuffer(img_bin)))
				# display(img)
			end
		end
	end for i in 1:100 ]
end
