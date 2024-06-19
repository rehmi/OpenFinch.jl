using JLD2
using VideoIO
using Images

BA = jldopen("BACGH.jld2", "r")

cgh = BA["cgh"]

frames = [
	RGB.(Gray.(cgh[k]))[1:720, :]
	for k in keys(cgh)
]

frames[1684]

encoder_options = (crf=23, preset="medium")
VideoIO.save("BA_CGH_1200mm_527nm.mp4",frames, framerate=30)
