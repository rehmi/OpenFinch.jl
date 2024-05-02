using PortMidi
Pm_Initialize()
stream = Ref{Ptr{PortMidi.PortMidiStream}}(C_NULL)
id = 0
Pm_OpenInput(stream, id, C_NULL, 16, C_NULL, C_NULL)


mutable struct PmEventM
    message::UInt32
    timestamp::UInt32
end
# msg = PmEventM(0,0)

function Pm_ReadM(stream, buffer, length)
    ccall((:Pm_Read, PortMidi.libportmidi), Cint, (Ptr{PortMidi.PortMidiStream}, Ptr{PmEventM}, Cint), stream, buffer, length)
end

##

# buf = Vector{PmEventM}(PmEventM(0,0), 16)
buf = Array{UInt32,2}(undef, 2, 16)

buf .= 0

bufp = pointer(buf)

sizeof(buf)

Pm_Read(stream[], bufp, 8)

buf
