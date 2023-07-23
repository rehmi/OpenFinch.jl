module SLM

using PythonCall
using ..RPYC

# const rpyc = Ref{Py}()
# const plumbum = Ref{Py}()
# const zerodeploy = Ref{Py}()


function __init__()
    # rpyc[] = pyimport("rpyc")
    # plumbum[] = pyimport("plumbum")
    # zerodeploy[] = pyimport("rpyc.utils.zerodeploy")
end

struct SLMDisplay
	rpy
	
	function SLMDisplay(host::AbstractString, user::AbstractString="")
		new(RPYC.RemotePython(host, user))
	end
end


using PythonCall

using ..RPYC

function setDISPLAY(disp::SLMDisplay, ds=":0")
	try
		disp.rpy.modules.os.environ["DISPLAY"]
	catch
		disp.rpy.modules.os.environ["DISPLAY"] = ":0"
	end
end

get_monitors(disp::SLMDisplay) = disp.rpy.modules.screeninfo.get_monitors()

function testdisplay(disp::SLMDisplay)
    np = disp.rpy.modules.numpy
    cv2 = disp.rpy.modules.cv2
	screen = get_monitors(disp)[1]
    width = screen.width
	height = screen.height

	is_color = true

	if is_color
		image = np.ones((height, width, 3), dtype=np.uint8)
		image[1:10, 1:10] .= 0 # black at top-left corner
		image[height - 10:end, 1:10] .= [1, 0, 0] # blue at bottom-left
		image[1:10, width - 10:end] .= [0, 1, 0] # green at top-right
		image[height - 10:end, width - 10:end] = [0, 0, 1] # red at bottom-right
		image = image*255
	else
		image = np.ones((height, width), dtype=np.float32)
		image[0, 0] = 0 # top-left corner
		image[height - 2, 0] = 0 # bottom-left
		image[0, width - 2] = 0 # top-right
		image[height - 2, width - 2] = 0 # bottom-right
	end

	window_name = "projector"
	cv2.namedWindow(window_name, cv2.WND_PROP_FULLSCREEN)
	cv2.moveWindow(window_name, screen.x - 1, screen.y - 1)
	cv2.setWindowProperty(window_name, cv2.WND_PROP_FULLSCREEN,
	cv2.WINDOW_FULLSCREEN)
	cv2.imshow(window_name, image)
	cv2.waitKey()
	cv2.destroyAllWindows()
end

using TestImages, Images, Colors

function testpygame(disp::SLMDisplay)
	rpy = disp.rpy
	pygame = rpy.modules.pygame

	pygame.display.init()
	# imgSurf = pygame.image.load(joinpath(homedir(), "finch", "USAF512.png"))
	imgSurf = pygame.image.load(joinpath("/home", "rehmi", "finch", "USAF512.png"))
	screen = pygame.display.set_mode((1280, 720), pygame.FULLSCREEN | pygame.NOFRAME )
	# screen = pygame.display.set_mode(imgSurf.get_size())
	screen.blit(imgSurf, (0, 0))

	pygame.display.flip()
    pygame.mouse.set_visible(0)
	
	sleep(10)
	# raw_input()
	pygame.quit()
end


function testdisp(disp::SLMDisplay)
    np = pyimport("numpy")
    npr = disp.rpy.modules.numpy
    cv2 = disp.rpy.modules.cv2
    screeninfo = disp.rpy.modules.screeninfo

    SLM.setDISPLAY(disp)

    screen = screeninfo.get_monitors()[-1]
    print(screen)
    width, height = pyconvert(Any, (screen.width, screen.height))

    img_orig = testimage("mandrill")
    h, w = size(img_orig)

    img = img_orig # imresize(img_orig, (height, width))

    img_split = collect(rawview(channelview(img)))

    cvt = np.ndarray(shape=(w, h, 3), buffer=pybytes(img_split), dtype=np.uint8)
    cvtr = npr.ndarray(shape=(w, h, 3), buffer=pybytes(img_split), dtype=npr.uint8)

    window_name = "SLM"
    cv2.namedWindow(window_name, cv2.WND_PROP_FULLSCREEN)
    cv2.moveWindow(window_name, screen.x - 1, screen.y - 1)
    cv2.setWindowProperty(window_name, cv2.WND_PROP_FULLSCREEN,
        cv2.WINDOW_FULLSCREEN)
    cv2.imshow(window_name, cvtr)
    cv2.waitKey()
    cv2.destroyAllWindows()
end

##

# r.execute("""
# import subprocess
# import sys

# def install(package):
# 	subprocess.check_call([sys.executable, "-m", "pip", "install", package])
# """)

# r.execute("install('screeninfo')")
# r.execute("install('numpy')")
# r.execute("install('opencv-python')")

##

# from screeninfo import get_monitors
# import numpy as np
# import cv2

# screen = get_monitors()[1]
# print(screen)
# width, height = screen.width, screen.height

# is_color = True

# if is_color:
# 	image = np.ones((height, width, 3), dtype=np.uint8)
# 	image[:10, :10] = 0 # black at top-left corner
# 	image[height - 10:, :10] = [1, 0, 0] # blue at bottom-left
# 	image[:10, width - 10:] = [0, 1, 0] # green at top-right
# 	image[height - 10:, width - 10:] = [0, 0, 1] # red at bottom-right
# 	image = image*255
# else:
# 	image = np.ones((height, width), dtype=np.float32)
# 	image[0, 0] = 0 # top-left corner
# 	image[height - 2, 0] = 0 # bottom-left
# 	image[0, width - 2] = 0 # top-right
# 	image[height - 2, width - 2] = 0 # bottom-right

# window_name = 'projector'
# cv2.namedWindow(window_name, cv2.WND_PROP_FULLSCREEN)
# cv2.moveWindow(window_name, screen.x - 1, screen.y - 1)
# cv2.setWindowProperty(window_name, cv2.WND_PROP_FULLSCREEN,
# cv2.WINDOW_FULLSCREEN)
# cv2.imshow(window_name, image)
# cv2.waitKey()
# cv2.destroyAllWindows()


end