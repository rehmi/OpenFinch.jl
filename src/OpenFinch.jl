module OpenFinch

# Write your package code here.

# using VideoIO
# using Distributed

# finch_worker() = first(addprocs(["finch.local", 1], exename="julia", dir="/home/rehmi/finch"))

# export finch_worker

include("CameraControl.jl")
using .CameraControl
export CameraControl
export PiGPIOScript, stop, start_pigpio, start_pig
export storeScript, runScript, stopScript, deleteScript
export ScriptStatus
export scriptStatus, scriptHalted, scriptIniting, scriptRunning

include("Dashboard.jl")
using .Dashboard

include("RPYC.jl")
using .RPYC
export RPYC
export RemotePython

include("SLM.jl")
using .SLM
export SLM

end # module
