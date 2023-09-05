module OpenFinch

# Write your package code here.

# using VideoIO
# using Distributed

# finch_worker() = first(addprocs(["finch.local", 1], exename="julia", dir="/home/rehmi/finch"))

# export finch_worker

using Reexport

include("CameraControl.jl")
@reexport using .CameraControl

include("Dashboard.jl")
@reexport using .Dashboard

include("RPYC.jl")
@reexport using .RPYC
# export RPYC
# export RemotePython

include("SLM.jl")
@reexport using .SLM
# export SLM

end # module
