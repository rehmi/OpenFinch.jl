using HTTP
using HTTP.WebSockets
using Sockets
using Images
using Random
using JSON
using Base64
using FileIO

function generate_image(brightness, contrast, gamma; width=16, height=12)
    img = rand(RGB, height, width)
    # img = adjust_gamma(img, gamma)
    # img = adjust_contrast(img, contrast)
    # img = adjust_brightness(img, brightness)
	return img
end

function image_to_string(img)
    img_io = IOBuffer()
    save(Stream{format"JPEG"}(img_io), img)
    img_base64 = base64encode(img_io.data)
    return "data:image/jpeg;base64," * img_base64
end

brightness, contrast, gamma = 0.5, 0.5, 1.0
img_height, img_width = 12, 16

connected = Set()

function handle_message(ws::WebSockets.WebSocket, data::String)
    message = JSON.parse(data)
    control_change = get(message, "control_change", Dict())
    image_request = get(message, "image_request", Dict())
    global brightness, contrast, gamma

    brightness = parse(Float64, get(control_change, "brightness", get(image_request, "brightness", string(brightness))))
    contrast = parse(Float64, get(control_change, "contrast", get(image_request, "contrast", string(contrast))))
    gamma = parse(Float64, get(control_change, "gamma", get(image_request, "gamma", string(gamma))))

	@info "in handle_message: brightness=$brightness, contrast=$contrast, gamma=$gamma"

	img = generate_image(brightness, contrast, gamma, height=img_height, width=img_width)
	img_str = image_to_string(img)

	msg = JSON.json(Dict("image_response" => Dict("image" => img_str)))

	# @info "sending message $msg"
    send(ws, msg)
end

function start_server()
    return HTTP.listen!(Sockets.localhost, 8000; verbose=true) do http::HTTP.Streams.Stream
        req = http.message
		@info req
        if HTTP.header(req, "Upgrade") == "websocket"
			@info "upgrading to websocket"
            WebSockets.upgrade(http) do ws
				try
					push!(connected, ws)
					for msg in ws
						@info "got message $msg"
						handle_message(ws, msg)
					end
				finally
					delete!(connected, ws)
				end
            end
        else
			@info req.target
            if req.target == "/"
				@info "responding with 200 vanilla.html"
				status = 200
				body = read("vanilla.html")
            else
                @info "responding with 404"
				status = 404
				body = ""
            end

			HTTP.setstatus(http, status)
			HTTP.setheader(http, "Content-Type" => "text/html")
			startwrite(http)
			write(http, body)
			return
        end
    end
end

function send_images()
    while true
        img_str = generate_image(brightness, contrast, gamma, height=img_height, width=img_width)
        if !isempty(connected)
            for ws in connected
                send(ws, JSON.json(Dict("image_response" => Dict("image" => img_str))))
            end
        end
        sleep(1)
    end
end

global server=nothing
global image_sender=nothing

function start()
	global server, image_sender
	server = start_server()
	# image_sender = @Threads.spawn send_images()
	@info "started" server
end

function stop()
	close(server)
end
