using HTTP
using HTTP.WebSockets
using JSON

"""
    OpenFinchClient

A mutable structure to represent a client for communicating with an OpenFinch device.
It holds the URI for connection and the WebSocket client instance.
"""
mutable struct OpenFinchClient
    uri::String
    websocket::Union{Nothing, WebSocket}

    """
        OpenFinchClient(uri::String)

    Construct a new OpenFinchClient with the provided URI and a `nothing` WebSocket.
    """
    function OpenFinchClient(uri::String)
        return new(uri, nothing)
    end
end

"""
    connect(client::OpenFinchClient)

Establish a WebSocket connection to the OpenFinch client's stored URI.
"""
function connect(client::OpenFinchClient)
    client.websocket = WebSocket(client.uri)
end

"""
    close(client::OpenFinchClient)

Close the WebSocket connection for the given OpenFinch client instance if it's open.
"""
function close(client::OpenFinchClient)
    if !isnothing(client.websocket)
        close(client.websocket)
        client.websocket = nothing
    end
end

"""
    send_control_command(client::OpenFinchClient, command::String, value::Any)

Send a control command over the WebSocket connection in the JSON format.
"""
function send_control_command(client::OpenFinchClient, command::String, value::Any)
    message = JSON.json(Dict(command => Dict("value" => value)))
    write(client.websocket, message)
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
    write(client.websocket, request)
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

    write(client.websocket, JSON.json(Dict("SLM_image" => "next")))
    write(client.websocket, img_byte_arr)
end

"""
    listen(client::OpenFinchClient)

Continuously listen for messages on the OpenFinch client's WebSocket connection and print them.
This function blocks and runs indefinitely until an EOFError occurs, signalling the connection was closed.
"""
function listen(client::OpenFinchClient)
    while true
        try
            message = String(readavailable(client.websocket))
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
