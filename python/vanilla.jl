using HTTP
using HTTP.WebSockets
using Sockets
using Images
using Random
using JSON
using Base64
using FileIO

function generate_image(brightness, contrast, gamma; width=16, height=12)
    img = rand(Gray, height, width)
    # img = adjust_gamma(img, gamma)
    # img = adjust_contrast(img, contrast)
    # img = adjust_brightness(img, brightness)
    return img
end

function image_to_binary(img; quality=nothing)
    img_io = IOBuffer()
    if quality != nothing
        save(Stream{format"JPEG"}(img_io), img, quality=quality)
    else
        save(Stream{format"PNG"}(img_io), img)
    end
    return img_io.data
end

function image_to_string(img; quality::Int=nothing)
	img_io = IOBuffer()
	if quality != nothing
		save(Stream{format"JPEG"}(img_io), img, quality=quality)
		str = "data:image/jpeg;base64," * base64encode(img_io.data)
	else
		save(Stream{format"PNG"}(img_io), img)
		str = "data:image/png;base64," * base64encode(img_io.data)
	end
	return str
end

const use_jpeg = Ref(true)
const quality = Ref(75)

function send_image(ws; height=12, width=16, quality=quality[])
    img = generate_image(brightness, contrast, gamma, height=height, width=width)
    img_bin = image_to_binary(img, quality=quality)

    # Send JSON message first
    msg = JSON.json(Dict("image_response" => Dict("image" => "next")))
    send(ws, msg)

    # Then send binary data
    send(ws, img_bin)
end

brightness, contrast, gamma = 0.5, 0.5, 1.0
img_height = Ref(1200)
img_width = Ref(1600)

connected = Set()

function handle_message(ws::WebSockets.WebSocket, data::String)
    message = JSON.parse(data)
    control_change = get(message, "control_change", Dict())
    image_request = get(message, "image_request", Dict())

    global brightness, contrast, gamma
    brightness = parse(Float64, get(control_change, "brightness", get(image_request, "brightness", string(brightness))))
    contrast = parse(Float64, get(control_change, "contrast", get(image_request, "contrast", string(contrast))))
    gamma = parse(Float64, get(control_change, "gamma", get(image_request, "gamma", string(gamma))))

	send_image(ws, height=img_height[], width=img_width[])
end

function start_server()
    return HTTP.listen!(Sockets.localhost, 8000; verbose=true) do http::HTTP.Streams.Stream
        req = http.message
		# @info req
        if req.target=="/ws" || HTTP.header(req, "Upgrade") == "websocket"
			# @info "upgrading to websocket"
            WebSockets.upgrade(http) do ws
				try
					push!(connected, ws)
					for msg in ws
						# @info "got message $msg"
						handle_message(ws, msg)
					end
				finally
					delete!(connected, ws)
				end
            end
        else
			# @info req.target
            if req.target == "/"
				# @info "responding with 200 vanilla.html"
				status = 200
				body = read("vanilla.html")
            else
                # @info "responding with 404"
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
