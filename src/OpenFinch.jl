module OpenFinch

# Write your package code here.

# using VideoIO
# using Distributed

# finch_worker() = first(addprocs(["finch.local", 1], exename="julia", dir="/home/rehmi/finch"))

# export finch_worker

include("CameraControl.jl")
using .CameraControl
include("Dashboard.jl")
using .Dashboard
include("RPYC.jl")
using .RPYC
include("SLM.jl")
using .SLM

# export RPYC.remotePython
export RPYC, SLM
export RemotePython

end # module
