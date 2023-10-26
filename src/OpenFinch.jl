module OpenFinch

using Reexport

include("CameraControl.jl")
@reexport using .CameraControl

include("RPYC.jl")
@reexport using .RPYC

include("SLM.jl")
@reexport using .SLM

include("Dashboard.jl")
@reexport using .Dashboard

end # module
