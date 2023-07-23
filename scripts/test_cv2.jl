using OpenFinch
# using PythonCall
using PyCall
using TestImages, Images, Colors

# Hue(x::HSV{T} where T) = x.h
# Sat(x::HSV{T} where T) = x.s
# Val(x::HSV{T} where T) = x.v

# MxNx3(x::Array{RGB{T},2} where T) = cat(red.(x), green.(x), blue.(x), dims=3)
# MxNx3(x::Array{HSV{T},2} where T) = cat(Hue.(x), Sat.(x), Val.(x), dims=3)
# MxNx3(x::Array{Lab{T},2} where T) = cat(getfield.(x, :l), getfield.(x, :a), getfield.(x, :b), dims=3)
# MxNx3(x::Array{YIQ{T},2} where T) = cat(getfield.(x, :y), getfield.(x, :i), getfield.(x, :q), dims=3)

# RGB(x::Array{T,3} where T) = RGB.(x[:,:,1], x[:,:,2], x[:,:,3])
# BGR2RGB(x::Array{T,3} where T) = RGB.(x[:,:,3], x[:,:,2], x[:,:,1])
# HSV(x::Array{T,3} where T) = HSV.(x[:,:,1], x[:,:,2], x[:,:,3])
# Lab(x::Array{T,3} where T) = Lab.(x[:,:,1], x[:,:,2], x[:,:,3])
# YIQ(x::Array{T,3} where T) = YIQ.(x[:,:,1], x[:,:,2], x[:,:,3])

# cv2RGB(x::Array{T,3} where T) = RGB.(x[:,:,3]/255, x[:,:,2]/255, x[:,:,1]/255)
RGB2cv(x::Array{RGB{T},2} where T) = UInt8.(clamp.(round.(cat(blue.(x),green.(x),red.(x), dims=3)*255), 0, 255))

host = "localhost"
window_name = "SLM"

if host=="localhost"
    np = pyimport("numpy")
    cv2 = pyimport("cv2")
    screeninfo = pyimport("screeninfo")

    screen = screeninfo.get_monitors()[-1]
    print(screen)
    width, height = pyconvert(Any, (screen.width, screen.height))
    cv2.namedWindow(window_name)
else
	disp = SLM.SLMDisplay(host)
	np = pyimport("numpy")
	npr = disp.rpy.modules.numpy
	cv2 = disp.rpy.modules.cv2
	screeninfo = disp.rpy.modules.screeninfo

	SLM.setDISPLAY(disp)

	screen = screeninfo.get_monitors()[-1]
	print(screen)
	width, height = pyconvert(Any, (screen.width, screen.height))
    cv2.namedWindow(window_name, cv2.WND_PROP_FULLSCREEN)
    cv2.moveWindow(window_name, screen.x - 1, screen.y - 1)
	cv2.setWindowProperty(window_name, cv2.WND_PROP_FULLSCREEN, cv2.WINDOW_FULLSCREEN)
end

##

cv2.waitKey(100)

##

img_orig = testimage("mandrill")
h,w = size(img_orig)

img = img_orig; # imresize(img_orig, (height, width))

# img_split = collect(rawview(channelview(img)))
# img_split = permutedims(img_split, (2, 3, 1))
# cvt = np.ndarray(shape=(w, h, 3), buffer=pybytes(img_split), dtype=np.uint8)
# cvtr = npr.ndarray(shape=(w, h, 3), buffer=pybytes(img_split), dtype=npr.uint8)

img = testimage("mandrill")
img_cv_color = npr.ndarray(shape=(w, h, 3), buffer=pybytes(RGB2cv(img)), dtype=npr.uint8)

cv2.imshow(window_name, img_cv_color)
cv2.waitKey(100)

##

img_cv_gray = cv2.cvtColor(img_cv_color, cv2.COLOR_BGR2GRAY)
cv2.imshow(window_name, img_cv_gray)
cv2.waitKey(100)

##

ret, img_cv_1bit = cv2.threshold(img_cv_gray, 128, 255, 0)

cv2.imshow(window_name, img_cv_1bit)
cv2.waitKey(100)

##

cv2.destroyAllWindows()

