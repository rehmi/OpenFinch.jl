using OpenFinch
using Test

# using Distributed

@testset "OpenFinch.jl" begin
    # Write your tests here.

    # @everywhere function framegrab()
    #     cam = VideoIO.opencamera()
    #     VideoIO.drop_frames!(cam)
    #     img = read(cam)
    #     img = read(cam)
    #     close(cam)
    #     img
    # end

	# worker = finch_worker()
	
	# for i ∈ 1:10
	# 	display(fetch(@spawnat worker framegrab()))
	# 	sleep(1)
	# end
	
end
