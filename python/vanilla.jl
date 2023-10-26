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

	@info "in handle_message: brightnes=$brightness, contrast=$contrast, gamma=$gamma"

	img = generate_image(brightness, contrast, gamma, height=img_height, width=img_width)
	img_str = image_to_string(img)

	msg = JSON.json(Dict("image_response" => Dict("image" => img_str)))

	# @info "sending message $msg"
    send(ws, msg)
end

function start_ws_server()
    return WebSockets.listen!(Sockets.localhost, 8001, verbose=true) do ws
        for msg in ws
			@info "got message $msg"
            handle_message(ws, msg)
        end
    end
end

function start_http_server()
    return HTTP.serve!(Sockets.localhost, 8000; verbose=true) do req::HTTP.Request
        if req.target == "/"
            return HTTP.Response(200, read("vanilla.html"))
        else
            return HTTP.Response(404)
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

global ws_server=nothing
global http_server=nothing
global image_sender=nothing

function start()
	global ws_server, http_server, image_sender
	ws_server = start_ws_server()
	http_server = start_http_server()
	# image_sender = @Threads.spawn send_images()
	@info "starting:" ws_server http_server image_sender
end

function stop()
	@warn "stopping the server is not yet implemented"
end
