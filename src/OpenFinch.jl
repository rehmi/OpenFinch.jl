module OpenFinch

using Reexport

if Sys.islinux()
    include("CameraControl.jl")
    @reexport using .CameraControl
end

include("RPYC.jl")
@reexport using .RPYC

include("SLM.jl")
@reexport using .SLM

include("Dashboard.jl")
@reexport using .Dashboard

include("WaveOptics.jl")
@reexport using .WaveOptics

end # module
