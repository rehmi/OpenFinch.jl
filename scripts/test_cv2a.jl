using OpenFinch
# using PythonCall
using PyCall
using TestImages, Images, Colors

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

disp = SLM.SLMDisplay("finch.local")
np = pyimport("numpy")
npr = disp.rpy.modules.numpy
cv2 = disp.rpy.modules.cv2
screeninfo = disp.rpy.modules.screeninfo

SLM.setDISPLAY(disp)

screen = screeninfo.get_monitors()[-1]
print(screen)
width, height = pyconvert(Any, (screen.width, screen.height))

img_orig = testimage("mandrill")
h,w = size(img_orig)

img = img_orig; # imresize(img_orig, (height, width))

img_split = collect(rawview(channelview(img)))

cvt = np.ndarray(shape=(w, h, 3), buffer=pybytes(img_split), dtype=np.uint8)
cvtr = npr.ndarray(shape=(w, h, 3), buffer=pybytes(img_split), dtype=npr.uint8)
# cvi = RGB2cv(img_orig)

window_name = "SLM"
cv2.namedWindow(window_name, cv2.WND_PROP_FULLSCREEN)
cv2.moveWindow(window_name, screen.x - 1, screen.y - 1)
cv2.setWindowProperty(window_name, cv2.WND_PROP_FULLSCREEN,
cv2.WINDOW_FULLSCREEN)
cv2.imshow(window_name, cvtr)
cv2.waitKey()
cv2.destroyAllWindows()


if false
	"""
is_color = True

if is_color:
	img = np.ones((height, width, 3), dtype=np.uint8)
	img[:10, :10] = 0 # black at top-left corner
	img[height - 10:, :10] = [1, 0, 0] # blue at bottom-left
	img[:10, width - 10:] = [0, 1, 0] # green at top-right
	img[height - 10:, width - 10:] = [0, 0, 1] # red at bottom-right
	img = img*255
else:
	img = np.ones((height, width), dtype=np.float32)
	img[0, 0] = 0 # top-left corner
	img[height - 2, 0] = 0 # bottom-left
	img[0, width - 2] = 0 # top-right
	img[height - 2, width - 2] = 0 # bottom-right

window_name = 'projector'
cv2.namedWindow(window_name, cv2.WND_PROP_FULLSCREEN)
cv2.moveWindow(window_name, screen.x - 1, screen.y - 1)
cv2.setWindowProperty(window_name, cv2.WND_PROP_FULLSCREEN,
cv2.WINDOW_FULLSCREEN)
cv2.imshow(window_name, img)
cv2.waitKey()
cv2.destroyAllWindows()
"""

##
