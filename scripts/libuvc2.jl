using Libdl

# Load Library
libuvc = dlopen("libuvc.so")

# Structures
mutable struct uvc_context
    usb_ctx::Ptr{Cvoid}
    own_usb_ctx::Cint
    open_devices::Ptr{Cvoid}
end

mutable struct uvc_device
    ctx::Ptr{uvc_context}
    ref::Cint
    bus_number::Cint
    device_address::Cint
    device::Ptr{Cvoid}
end

mutable struct uvc_stream_ctrl
    bmHint::Cushort
    bFormatIndex::Cuchar
    bFrameIndex::Cuchar
    dwFrameInterval::Cuint
    wKeyFrameRate::Cushort
    wPFrameRate::Cushort
    wCompQuality::Cushort
    wCompWindowSize::Cushort
    wDelay::Cushort
    dwMaxVideoFrameSize::Cuint
    dwMaxPayloadTransferSize::Cuint
    dwClockFrequency::Cuint
    bmFramingInfo::Cuchar
    bPreferredVersion::Cuchar
    bMinVersion::Cuchar
    bMaxVersion::Cuchar
    bInterfaceNumber::Cuchar
end

# Functions
function uvc_init()
    ctx = Ptr{uvc_context}(C_NULL)
    result = @ccall libuvc.uvc_init(:libuvc, :Cint, [Ref{Ptr{uvc_context}}], ctx)
    return ctx
end

function uvc_open(dev::Ptr{uvc_device})
    handle = Ptr{uvc_device_handle}(C_NULL)
    result = @ccall libuvc.uvc_open(:libuvc, :Cint, [Ref{Ptr{uvc_device}}, Ref{Ptr{uvc_device_handle}}], dev, handle)
    return handle
end

function uvc_stream_open_ctrl(devh::Ptr{uvc_device_handle}, ctrl::Ptr{uvc_stream_ctrl})
    strmh = Ptr{uvc_stream_handle}(C_NULL)
    result = @ccall libuvc.uvc_stream_open_ctrl(:libuvc, :Cint, [Ref{Ptr{uvc_device_handle}}, Ref{Ptr{uvc_stream_handle}}, Ref{uvc_stream_ctrl}], devh, strmh, ctrl)
    return strmh
end

function uvc_start_streaming(devh::Ptr{uvc_device_handle}, ctrl::Ptr{uvc_stream_ctrl}, callback::Ptr{Cvoid}, userdata::Ptr{Cvoid}, flags::Cuchar)
    result = @ccall libuvc.uvc_start_streaming(:libuvc, :Cint, [Ref{Ptr{uvc_device_handle}}, Ref{uvc_stream_ctrl}, Ptr{Cvoid}, Ptr{Cvoid}, Cuchar], devh, ctrl, callback, userdata, flags)
    return result
end
