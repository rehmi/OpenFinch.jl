using MiniFB
using Images
using TestImages
using ImageShow


function mfb_image(image)
    HEIGHT,WIDTH = size(image)

	function populate_buffer!(buffer, img)
        HEIGHT, WIDTH = size(img)

		buffer[:] = zeros(UInt32, HEIGHT*WIDTH)
		h, w = size(img)
		ratio = min(1, HEIGHT/h, WIDTH/w)
		nimg = imresize(img, ratio=ratio)
		nh, nw = size(nimg)
		oh = (HEIGHT-nh) ÷ 2
		ow = (WIDTH-nw) ÷ 2
		for i in 1:nh
			for j in 1:nw
				buffer[(oh+i-1)*WIDTH + ow+j] = mfb_rgb(nimg[i,j])
			end
		end
	end

    function onclick(window, button, mod, isPressed)::Cvoid
		@info "mouse" button, mod, isPressed
        return nothing
    end

    function onkey(window, button, mod, isPressed)::Cvoid
        @info "keyboard" button, mod, isPressed
		if (button == MiniFB.KB_KEY_ESCAPE) && isPressed
			mfb_close(window)
		end
        return nothing
    end
    
	buffer = zeros(UInt32, WIDTH * HEIGHT)
	
	mfb_set_target_fps(10)
    window = mfb_open_ex("Image Viewer", WIDTH, HEIGHT, 0)
    mfb_set_mouse_button_callback(window, onclick)
	mfb_set_keyboard_callback(window, onkey)

	# MiniFB.mfb_window_flags

	populate_buffer!(buffer, image)
    
	mfb_update(window, buffer)

	while mfb_wait_sync(window)
        state = mfb_update_events(window)
        if state != MiniFB.STATE_OK
            break
        end
    end

	mfb_close(window)
end

mfb_image(testimage("lighthouse"))



##

using Distributed

# finch = first(addprocs(["finch.local", 1], exename="julia", dir="/home/rehmi/finch"))

finch = addprocs(1)

# @everywhere using MiniFB

@everywhere function glorch()
    @eval begin
        ENV["DISPLAY"] = ":0"
        using MiniFB
    end
end

@everywhere finch glorch()



##

WIDTH = 1280
HEIGHT = 720

@everywhere finch w = mfb_open("MiniFB SLM", $WIDTH, $HEIGHT) # MiniFB. WF_FULLSCREEN)

m = testimage("resolution_test_512")
mr = imresize(m, WIDTH, HEIGHT)

@everywhere finch begin
	mfb_wait_sync(w)
	mfb_update(w, $(mfb_rgb.(mr)))
	while mfb_wait_sync(w)
		sleep(0.01)
	end
end

##

function finch_display(image)
	img = imresize(image, WIDTH, HEIGHT)
	@everywhere finch begin
		mfb_wait_sync(w)
		mfb_update(w, $(mfb_rgb.(img)))
		mfb_wait_sync(w)
	end
end

function finch_bitmap(image)
	img = imresize(image, WIDTH, HEIGHT)
	bmp = BitMatrix(Gray.(img) .> 0.5)
	@everywhere finch begin
		mfb_wait_sync(w)
		mfb_update(w, 0x00ffffff * $bmp)
		mfb_wait_sync(w)
	end
end

finch_display(Gray.(rand(Bool, WIDTH, HEIGHT)))

@everywhere finch mfb_set_target_fps(60)

using BenchmarkTools

@benchmark finch_display(Gray.(rand(Bool, WIDTH, HEIGHT)))

@benchmark finch_bitmap(Gray.(rand(WIDTH, HEIGHT)))

##

@everywhere  function noise()
	WIDTH = 800
	HEIGHT = 600
	g_buffer = zeros(UInt32, WIDTH * HEIGHT)
	noise = carry = seed = 0xbeef
	window = mfb_open_ex("Noise Test", WIDTH, HEIGHT, MiniFB.WF_RESIZABLE);
	while mfb_wait_sync(window)
		for i in 1:WIDTH * HEIGHT
			noise = seed;
			noise = noise >> 3;
			noise = noise ^ seed;
			carry = noise & 1;
			noise = noise >> 1;
			seed = seed >> 1;
			seed = seed | (carry << 30);
			noise = noise & 0xFF;
			g_buffer[i] = mfb_rgb(noise, noise, noise);
		end
		state = mfb_update(window, g_buffer);
		if state != MiniFB.STATE_OK
			break;
		end
	end
	mfb_close(window)
end


"""
This function displays a time-varying mix of colors on screen. Demonstrates how to create a buffer and render it to a window.
"""

@everywhere function plasma()
	pallete = zeros(UInt32, 512)
	WIDTH = 320
	HEIGHT = 240
	inc = 90 / 64;
	for c in 1:64
		col = round(Int, ((255 * sin( (c-1) * inc * π / 180)) + 0.5));
		pallete[64*0 + c] = mfb_rgb(col,     0,       0);
		pallete[64*1 + c] = mfb_rgb(255,     col,     0);
		pallete[64*2 + c] = mfb_rgb(255-col, 255,     0);
		pallete[64*3 + c] = mfb_rgb(0,       255,     col);
		pallete[64*4 + c] = mfb_rgb(0,       255-col, 255);
		pallete[64*5 + c] = mfb_rgb(col,     0,       255);
		pallete[64*6 + c] = mfb_rgb(255,     0,       255-col);
		pallete[64*7 + c] = mfb_rgb(255-col, 0,       0);
	end
	window = mfb_open_ex("Plasma Test", WIDTH, HEIGHT, MiniFB.WF_RESIZABLE);
	g_buffer = zeros(UInt32, WIDTH * HEIGHT)
	mfb_set_target_fps(10);
	time=0
	while mfb_wait_sync(window)
		time_x = sin(time * π / 180);
		time_y = cos(time * π / 180);
		i = 1;
		for y in 1:HEIGHT
			dy = cos((y * time_y) * π / 180); 
			for x in 1:WIDTH
				dx = sin((x * time_x) * π / 180); 
				idx = round(Int, ((2 + dx + dy) * 0.25 * 511) + 1)
				g_buffer[i] = pallete[idx];
				i += 1
			end
		end
		time += 1
		state = mfb_update(window, g_buffer);
		if state != MiniFB.STATE_OK
			break;
		end
	end
	mfb_close(window)
end

@everywhere finch plasma()

##

nothing

#

#= 
# Image viewer using MiniFB

# This example displays the PNG files in a directory, rotating through the available images on each mouse click.

# This code needs Images.jl and ImageTransformations.jl. Add those packages to your environment before proceeding

using Images
using ImageTransformations
using MiniFB

# Set the size of the window

global const WIDTH = 600
global const HEIGHT = 400

# Global state

global ni = 1
global num_images = 1

# A function that will be called when a mouse button is clicked. It simply rotates the current image by storing a global integer.

function onclick(window, button, mod, isPressed)::Cvoid
    global ni, num_images
    if Bool(isPressed)
        if ni < num_images
            ni = ni+1
        else
            ni = 1
        end
    end
    return nothing
end

# Populate a MiniFB buffer from the image data. First, resize the image to the window dimensions. Calculate it's position so that it is centered in the window. Finally, inside the loop, convert each pixel to the 32 bit MiniFB buffer format.

function populate_buffer!(buffer, img)
    global WIDTH, HEIGHT
    buffer[:] = zeros(UInt32, HEIGHT*WIDTH)
    h, w = size(img)
    ratio = min(1, HEIGHT/h, WIDTH/w)
    nimg = imresize(img, ratio=ratio)
    nh, nw = size(nimg)
    oh = (HEIGHT-nh) ÷ 2
    ow = (WIDTH-nw) ÷ 2
    for i in 1:nh
        for j in 1:nw
            buffer[(oh+i-1)*WIDTH + ow+j] = mfb_rgb(nimg[i,j])
        end
    end
end

# This is the main function. It takes a directory, calls loadfiles to get the image data. Creates the windows, and sets up the callback. Then, inside the while loop, renders the buffer into the window. The mfb_update not only renders the buffer, but also flushes the input event queue. The buffer is changed only when the state changes. The mfb_wait_sync method enforces the required frame rate.

function imageview(dir::String=".")
    global ni, num_images
    images = loadfiles(dir)
    num_images = length(images)
    buffer = zeros(UInt32, HEIGHT*WIDTH)
    mfb_set_target_fps(10)
    window = mfb_open_ex("Image Viewer", WIDTH, HEIGHT, MiniFB.WF_RESIZABLE);
    mfb_set_mouse_button_callback(window, onclick);
    old_ni=0
    while mfb_wait_sync(window)
        if ni != old_ni
            populate_buffer!(buffer, images[ni])
            old_ni = ni
        end
        state = mfb_update(window, buffer);
        if state != MiniFB.STATE_OK
            break;
        end
    end
    mfb_close(window)
end

# Load the files from disk. Select all png files, and then use ImageIO to load them into memory.

function loadfiles(dir::String=".")
    files = readdir(dir)
    filter!(x->occursin(r"\.png"i, x), files)
    [load(joinpath(dir,x)) for x in files]
end

# Finally, call the main method to display the application

imageview(joinpath(dirname(pathof(MiniFB)),"..", "example"))

=#
