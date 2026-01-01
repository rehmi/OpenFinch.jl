### A Pluto.jl notebook ###
# v0.20.4

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    #! format: off
    quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
    #! format: on
end

# ╔═╡ c10f6c81-bda1-443a-942c-6c0bcdab3c80
begin
	ENV["AF_JIT_KERNEL_TRACE"] = joinpath(homedir(), "tmp")
	# ENV["AF_JIT_KERNEL_TRACE"] = "stdout"
	ENV["AF_PRINT_ERRORS"] = "1"
	ENV["AF_DISABLE_GRAPHICS"] = "1"
	# ENV["AF_MEM_DEBUG"] = "1"
	# ENV["AF_TRACE"] = "jit,platform"
	# all: All trace outputs
	# jit: Logs kernel fetch & respective compile options and any errors.
	# mem: Memory management allocation, free and garbage collection information
	# platform: Device management information
	# unified: Unified backend dynamic loading information
	# ENV["AF_CUDA_MAX_JIT_LEN"] = "100"
	# ENV["AF_OPENCL_MAX_JIT_LEN"] = "50"
	# ENV["AF_SYNCHRONOUS_CALLS"] = "0"

	using Libdl
	# ((x,y)->x∈y||push!(y,x))("/opt/arrayfire/lib", Libdl.DL_LOAD_PATH)
	((x,y)->x∈y||push!(y,x))("/opt/homebrew/lib", Libdl.DL_LOAD_PATH)

	# using WaveOptics
	# using WaveOptics.ArrayFire
	using ArrayFire
	# ArrayFire.set_backend(UInt32(0))
	using ArrayFire: dim_t, af_lib, af_array, af_conv_mode, af_border_type
	using ArrayFire: _error, RefValue, af_type

	# does the GPU support double floats?
	if ArrayFire.get_dbl_support(0)
		WOFloat = Float32
		WOArray = AFArray
	else
		WOFloat = Float32
		WOArray = AFArray
	end

	# XXX workaround for bug in homebrew-installed ArrayFire 3.9.0 on Apple Silicon
	function ArrayFire._error(err::af_err, gc = true)
	    if err == 0
	        if gc
	            ArrayFire._afgc()
	        end
	    elseif err == AF_ERR_NO_MEM
	        error("GPU is out of memory, to avoid this in the future you can:
	  setafgcthreshold(threshold) # lower garbage collect threshold (default 4Gb)
	  finalize(array)             # manually free GPU memory")
	    else
	        str = err_to_string(err)
	        error("ArrayFire Error ($err) : $str")
	        # str2 = get_last_error()
	        # error("ArrayFire Error ($err) : $str\n$str2")
	    end
	end
	
	# ArrayFire.AFArray(a::Array{Float64}) = AFArray(Float32.(a))
	# ArrayFire.AFArray(a::Array{ComplexF64}) = AFArray(ComplexF32.(a))

	allowslow(AFArray, false)
	

	using PlutoUI
	using PlutoTeachingTools
	using DSP, FFTW, Plots, Images, TestImages
	# using QuartzImageIO
	using Colors
	using Statistics
	# using LazyGrids
	import StatsBase
	# import PlotlyJS
	import Unitful
	using Unitful: nm, µm, mm, cm, m
	using Unitful: upreferred, ustrip, @u_str
	# using DynamicQuantities
	# const U = DynamicQuantities.Units
	# const C = DynamicQuantities.Constants
	using BenchmarkTools
	using HypertextLiteral
	using FourierTools
	using ProgressLogging
	using HTTP
	using HTTP.WebSockets
	using JSON
	using Base64
	using FileIO
	using ImageIO
	using JpegTurbo
	using ImageShow
	using MosaicViews
	using Random
	using VideoIO
	using Primes

	using FourierTools: resample  # override DSP.resample
	using DSP: conv
	
	using LinearAlgebra: BLAS

	using TimerOutputs

	THREADS = Threads.nthreads()
	FFTW.set_num_threads(THREADS)
	BLAS.set_num_threads(THREADS)
	
	# Not sure why this is necessary, but it mitigates type errors
	# that occur when a {Complex} type reaches plan_fft()
	FFTW.fft(x::Matrix{Complex}) = fft(ComplexF32.(x))
	# FourierTools.resample(m::Matrix{Complex}, args...) = resample(ComplexF32.(m), args...)

	# setup TimerOutput for benchmarking
	to = TimerOutput()

	# meshgrid(y, x) = (ndgrid(x, y)[[2, 1]]...,)
	
	# XXX there's probably a better way to get rid of the "Premature end..." warning message
	# import JpegTurbo
	function JpegTurbo._jpeg_check_bytes(data::Vector{UInt8})
		length(data) > 623 || throw(ArgumentError("Invalid number of bytes."))
		data[1:2] == [0xff, 0xd8] || throw(ArgumentError("Invalid JPEG byte sequence."))
		# data[end-1:end] == [0xff, 0xd9] || @warn "Premature end of JPEG byte sequence."
		return true
	end

	function afstat()
		alloc_bytes, alloc_buffers, lock_bytes, lock_buffers =  device_mem_info()
		println("alloc: $(alloc_bytes÷(1024*1024))M, $alloc_buffers bufs; locked: $(lock_bytes÷(1024*1024))M, $lock_buffers bufs")
	end
	
	function af_pad(A::AFArray{T,N}, bdims::Vector{dim_t}, edims::Vector{dim_t},
					type::af_border_type=AF_PAD_ZERO) where {T,N}
		out = RefValue{af_array}(0)
		_error(@ccall af_lib.af_pad(out::Ptr{af_array},
									A.arr::af_array,
									length(bdims)::UInt32,
									bdims::Ptr{Vector{dim_t}},
									length(edims)::UInt32,
									edims::Ptr{Vector{dim_t}},
									type::af_border_type
		)::af_err)
		n = max(N, length(bdims), length(edims))	# XXX might not be strictly correct
		return AFArray{T, n}(out[])
	end
	
	af_pad(A::AFArray{T, N}, bdims::Tuple, edims::Tuple, type::af_border_type=AF_PAD_ZERO) where {T, N} = af_pad(A, [bdims...], [edims...], type)

	function af_conv(signal::AFArray{Ts,N}, filter::AFArray{Tf,N}; expand=false, inplace=true)::AFArray where {Ts<:Union{Complex,Real}, Tf<:Union{Complex,Real}, N}
		cT = AFArray{ComplexF32}
		S = cT(signal)
		F = cT(filter)
		sdims = size(S)
		fdims = size(F)
		odims = sdims .+ fdims .- 1
		pdims = nextpow.(2, odims)

		# pad beginning of signal by 1/2 width of filter
		# line up beginning of signal with center of filter in padded arrays
		Sbpad = fdims .÷ 2
		# pad end of signal by (nextpow2 size) - (size of (pad + signal))
		Sepad = pdims .- (Sbpad .+ sdims)

		# don't pad beginning of filter
		Fbpad = fdims .* 0
		# pad end of filter to nextpow2 size
		Fepad = pdims .- fdims

		if expand == true
			from = fdims .* 0 .+ 1
			to = odims
		elseif expand == :padded
			from = fdims .* 0 .+ 1
			to = pdims
		elseif expand==false
			from = fdims.÷2 .+ 1
			to = from .+ sdims .- 1
		else
			error("Cannot interpret value for keyword expand: $expand")
		end
		index  = tuple([a:b for (a,b) in zip(from, to)]...)

		pS = af_pad(S, Sbpad, Sepad, AF_PAD_ZERO)
		pF = af_pad(F, Fbpad, Fepad, AF_PAD_ZERO)
		shifts = -[(fdims.÷2)... [0 for i ∈ length(fdims):3]...]
		pF = ArrayFire.shift(pF, shifts...)

		# @info "data:" size(S) size(F)
		# @info "padded data:" size(pS) size(pF)
		# @info "fc2() calculations:" cT sdims fdims odims pdims index
		# @info "index calculation" expand from to index

		if inplace
			fft!(pS)
			fft!(pF)
			pS = pS .* pF
			ifft!(pS)
			SF = pS
		else
			fS = fft(pS)
			fF = fft(pF)
			fSF = fS .* fF
			SF = ifft(fSF)
		end

		if eltype(signal) <: Real && eltype(filter) <: Real
			out = allowslow(AFArray) do; real.(SF[index...]); end
		else
			out = allowslow(AFArray) do; (SF[index...]); end
		end

		return out
	end

	if !ArrayFire.get_dbl_support(0)
		# __precompile__(false)
		
		(::Type{AFArray})(a::Array{Float64,N} where N) = AFArray(Float32.(a))
		(::Type{AFArray})(a::Array{ComplexF64,N} where N) = AFArray(ComplexF32.(a))
		# Base.:*(c::Float64, a::AFArray) = Float32(c)*a
		# Base.:*(c::ComplexF64, a::AFArray) = ComplexF32(c)*a
		# Base.:*(c::Complex{Int64}, a::AFArray) = ComplexF32(c)*a
		# (::Type{AFArray})(a::Array{Quantity{T,D,U},N}) where {T,D,U,N} = AFArray(T.(ustrip(upreferred.(a))))
		
		# ArrayBool = AFArray{Bool, N} where N
		# ArrayReal = AFArray{Float32, N} where N
		# ArrayComplex = AFArray{ComplexF32, N} where N
		
		# (::Type{ArrayBool})(x) = convert(ArrayBool, x)
		# (::Type{ArrayReal})(x) = convert(ArrayReal, x)
		# (::Type{ArrayComplex})(x) = convert(ArrayComplex, x)
		
		# Base.convert(::Type{ArrayBool}, x) = AFArray(Array{Bool}(x))
		# Base.convert(::Type{ArrayComplex}, x) = AFArray(Array{ComplexF32}(x))
		# Base.convert(::Type{ArrayReal}, x) = AFArray(Array{Float32}(x))
		
		Base.:*(a::AFArray, b::Float64) = a * Float32(b)
		Base.:*(a::Float64, b::AFArray) = Float32(a) * b
		Base.:/(a::AFArray, b::Float64) = a / Float32(b)
		Base.:/(a::Float64, b::AFArray) = Float32(a) / b
		Base.:+(a::AFArray, b::Float64) = a + Float32(b)
		Base.:+(a::Float64, b::AFArray) = Float32(a) + b
		Base.:-(a::AFArray, b::Float64) = a - Float32(b)
		Base.:-(a::Float64, b::AFArray) = Float32(a) - b
		
		Base.:*(a::AFArray, b::ComplexF64) = a * ComplexF32(b)
		Base.:*(a::ComplexF64, b::AFArray) = ComplexF32(a) * b
		Base.:/(a::AFArray, b::ComplexF64) = a / ComplexF32(b)
		Base.:/(a::ComplexF64, b::AFArray) = ComplexF32(a) / b
		Base.:+(a::AFArray, b::ComplexF64) = a + ComplexF32(b)
		Base.:+(a::ComplexF64, b::AFArray) = ComplexF32(a) + b
		Base.:-(a::AFArray, b::ComplexF64) = a - ComplexF32(b)
		Base.:-(a::ComplexF64, b::AFArray) = ComplexF32(a) - b
		
		# for broadcast operations, perform op in AF space and convert to
		# type of left argument upon return
		
		#=
		Base.Broadcast.broadcasted(*, A::Array, B::AFArray) = (AFArray(A).*B)
		Base.Broadcast.broadcasted(/, A::Array, B::AFArray) = (AFArray(A)./B)
		Base.Broadcast.broadcasted(+, A::Array, B::AFArray) = (AFArray(A).+B)
		Base.Broadcast.broadcasted(-, A::Array, B::AFArray) = (AFArray(A).-B)
		
		Base.Broadcast.broadcasted(*, A::AFArray, B::Array) = A.*AFArray(B)
		Base.Broadcast.broadcasted(/, A::AFArray, B::Array) = A./AFArray(B)
		Base.Broadcast.broadcasted(+, A::AFArray, B::Array) = A.+AFArray(B)
		Base.Broadcast.broadcasted(-, A::AFArray, B::Array) = A.-AFArray(B)
		=#
	end

	md"## Initialize execution environment"
end

# ╔═╡ 86a65396-30db-4ace-b863-84f250a3ac4c
md"""
# Accelerated CGH by incoherent photon sampling
"""

# ╔═╡ 32f9cb5e-3c8d-4d40-b43b-f14a3cb255f2
begin
	md"""
	Enable Table of Contents $(@bind enable_TOC CheckBox(false)) 

	Show figures $(@bind enable_figs CheckBox(false))
	
	$(ChooseDisplayMode())
	"""
end

# ╔═╡ ffcbbfe2-a8a0-474f-a1c8-b419bacc90e2
enable_TOC ? TableOfContents() : nothing

# ╔═╡ 5c459507-67eb-41fd-9ce6-3cd489601064
begin
	host = "winch.local"
	port = 8000
	URI = "ws://$host:$port/ws"
end

# ╔═╡ 3111a73e-c846-4153-97e2-3cae83b3e8cf
let
	function my_fft!(x::Vector{Complex{T}}) where {T<:Real}
		n = length(x)
		n <= 1 && return x
		
		bit_reverse_copy!(x)
		
		for s in 1:log2(n)
			m = 2^s
			ωm = exp(-2π * im / m)
			for k in 0:m:n-1
				ω = 1.0 + 0.0im
				for j in 0:m÷2-1
					u = x[k + j + 1]
					t = ω * x[k + j + m÷2 + 1]
					x[k + j + 1] = u + t
					x[k + j + m÷2 + 1] = u - t
					ω *= ωm
				end
			end
		end
		return x
	end
	
	function bit_reverse_copy!(x::Vector{Complex{T}}) where {T<:Real}
		n = length(x)
		for i in 1:n
			j = reverse_bits(i-1, n) + 1
			if i < j
				x[i], x[j] = x[j], x[i]
			end
		end
	end
	
	function reverse_bits(i::Int, n::Int)
		rev = 0
		for _ in 1:log2(n)
			rev = (rev << 1) | (i & 1)
			i >>= 1
		end
		return rev
	end
	
	function ifft!(x::Vector{Complex{T}}) where {T<:Real}
		x .= conj.(fft!(conj.(x))) / length(x)
		return x
	end
	
	nothing
end

# ╔═╡ 3d8c0ba4-5145-4e61-821f-3bbd251f98c6
begin
    MetersF32(x) = Float32(ustrip(u"m", x))
    YO(args...) = printstyled(stderr, "*** ", args..., "\n", reverse=true)
end

# ╔═╡ 03eef203-2754-4bf2-a0b0-5de16b938498
# Cell 10: Define convolution function
# function myconv(s::AFArray, k::AFArray)
#     sdims = size(s)
#     kdims = size(k)
#     pdims = Tuple(max(a,b) for (a,b) in zip(sdims, kdims))
#     YO("sdims=$sdims, kdims=$kdims, pdims=$pdims")
#     sp = af_pad_centered(s, pdims)
#     kp = af_pad_centered(k, pdims)
#     YO("size(sp)=$(size(sp)), size(kp)=$(size(kp))")
#     out = ifft(fft(sp) .* fft(kp))
# end

# ╔═╡ 1af812f7-41eb-48b6-bd4f-a68ad28d20f3
begin
	fft_supported(n::Integer) = isempty(setdiff(factor(Set, n), Set([2, 3, 5, 7, 11, 13])))
	fft_supported(t::Tuple) = all(fft_supported.(t))

	function fft_first_supported_size(n::Integer)
	    while !fft_supported(n)
   	    	n += 1
    	end
 	   return n
	end
end

# ╔═╡ e123e7de-7bd9-4b4a-880f-1f26c6c19e62
@bind threshold Slider(-1.0:0.01:1.0, default=0, show_value=true)

# ╔═╡ d1fa707e-3ab8-4aed-bca6-7f75c95145ad
begin
	W_λR   = @bind λR Slider(600:1:700, default=638, show_value=true);
	W_λG   = @bind λG Slider(500:1:600, default=527, show_value=true);
	W_λB   = @bind λB Slider(400:1:500, default=477, show_value=true);

	W_rg   = @bind red_gain Slider(0.0:0.1:4.0, default=1, show_value=true)
	W_bg   = @bind blue_gain Slider(0.0:0.1:4.0, default=1.5, show_value=true)
	W_ag   = @bind analog_gain Slider(1.0:0.1:100.0, default=2, show_value=true)

	W_LW   = @bind LED_WIDTH Slider(0:1:2560, default=1280, show_value=true)
	W_LT   = @bind LED_TIME Slider(0:1:8333, default=0, show_value=true)
	
	W_brt  = @bind brightness Slider(-1:0.1:1, default=0, show_value=true)
	W_con  = @bind contrast Slider(0:0.1:32, default=1, show_value=true)
	W_sat  = @bind saturation Slider(0:0.1:32, default=1, show_value=true)
	W_nrm  = @bind nrmode Slider(0:1:4, default=0, show_value=true)
	W_shp  = @bind sharpness Slider(0:0.1:16, default=1, show_value=true)
end;

# ╔═╡ 1dcbea3d-11b9-4395-9e7c-5d5a1c658b28
begin
	W_f    = @bind f Slider(0:10:2500, default=600, show_value=true)
	W_df   = @bind df Slider(-5:0.1:5, default=0, show_value=true)
	W_xoff = @bind xoff Slider(-100:1:100, default=0, show_value=true)
	W_yoff = @bind yoff Slider(-100:1:100, default=-25, show_value=true)
	W_ls   = @bind lens_scale Slider(1024:1024:16384, default=1024, show_value=true)

	W_is   = @bind image_scale Slider(0.1:0.1:16, default=2, show_value=true)
	W_ui   = @bind use_image CheckBox(true)
	W_uc   = @bind use_chart CheckBox(true)
end;

# ╔═╡ a9d3b06b-2ee0-4694-b028-c4f6663d1a6c
# Cell 4: Calculate basic parameters
begin
    xo, yo = MetersF32.((xoff, yoff) .* u"mm")
    dx = MetersF32(4.25u"µm")
    λr = MetersF32(λR*u"nm")
    λg = MetersF32(λG*u"nm")
    λb = MetersF32(λB*u"nm")
    Nx, Ny = (1,1) .* lens_scale
    Lx, Ly = (Nx, Ny) .* dx
    Z = MetersF32((f+df)*u"mm")
    YO("dx=$dx, λG=$λG, Nx=$Nx, Lx=$Lx, Z=$Z, offset=($xoff, $yoff)")
end

# ╔═╡ b183ede1-7d1a-41d8-866e-ca1c826aca08
lens_scales = [ 256, 384, 512, 768, 1024, 1536, 2048,
				3072, 4096, 6144, 8192, 12288, 16384
]

# ╔═╡ 266fc634-1a9d-45f8-9f20-2d79e477f0fa
W_Go = @bind G_only CheckBox(true);

# ╔═╡ 9e0052e2-c13c-42a3-971c-d7482044c25f
md"""
| control | value | control | value | control | value |
| --: | :-- | --: | :-- | --: | :-- |
| $\lambda_R$ | $W_λR | $\lambda_G$ | $W_λG | $\lambda_B$ | $W_λB |
| red gain | $W_rg | blue gain | $W_bg | analog gain | $W_ag |
| Noise reduction mode | $W_nrm | Sharpness | $W_shp | |
| Brightness | $W_brt | Contrast | $W_con | Saturation | $W_sat |
| LED width | $W_LW | LED time | $W_LT |
| Focal length | $W_f | Fine focus | $W_df |
| Lens scale | $W_ls | X offset | $W_xoff | Y offset | $W_yoff |
| Use image  | $W_ui  | Image scaling factor | $W_is | Use chart | $W_uc |
| Use G only | $W_Go |
"""

# ╔═╡ b3441c7d-a097-435d-b1da-46869b9d2193
md"""
## Generate and send interferograms
"""

# ╔═╡ a58c5e86-b282-43a7-b74a-7dc8f1e49976
begin
	color_chart = load("../data/color_reschart02.png");
	usaf_chart = load("../data/USAF512.png")
	mono_chart = testimage("resolution_test_512");
	cameraman = testimage("cameraman");
	mandrill = testimage("mandrill");
	nothing
end

# ╔═╡ a4b4901b-6a6f-440d-867b-47e02796ebab
source_img = usaf_chart;
# options: mono_chart, usaf_chart, color_chart, cameraman, mandrill, ba;

# ╔═╡ 2b2dd536-a71a-4364-910c-9106628a094b
img = reverse(imresize(source_img, ratio=image_scale), dims=1);

# ╔═╡ 8ebb273b-b87d-4cef-8a0c-f6e66d747b19
img

# ╔═╡ 7a62814e-d46e-431b-91d1-18c95450351a
ArrayFire.device_gc()

# ╔═╡ 5e75df4c-f952-4d80-9280-7c010bd26b9a
ArrayFire.setafgcthreshold(4*1024^3)

# ╔═╡ 21d8f8ad-9280-44be-8b66-ec8526640c5f
afstat()

# ╔═╡ a7226d4a-0de6-4683-ac66-a679e5e4b83a
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
W_sf = @bind sharpening_factor Slider(0:0.1:20, default=0, show_value=true)
  ╠═╡ =#

# ╔═╡ 1ec2f842-9bba-4478-a159-35932d28e315
chart = usaf_chart

# ╔═╡ d7b8aa39-8965-48c0-a095-74fa2ff5257c
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
begin
	# using ImageFiltering
	laplacian_kernel =
		[ 0  1  0;
		 1 -4  1;
		 0  1  0];
	sobol_kernel = 
		[ -1 -1 -1;
		  -1  9 -1;
		  -1 -1 -1];
end;
  ╠═╡ =#

# ╔═╡ c0270980-f1d0-4ce3-8e48-ba8d720315f8
md"""
## Test ArrayFire performance
"""

# ╔═╡ d4953849-16cb-4f3f-befe-57f1fc327735
md"""
---
# Definitions
"""

# ╔═╡ b4fc462c-a529-4970-a0c0-c4b39cb8a51d
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
@benchmark ArrayFire.sync(af_conv(a, b)) setup=(a=rand(AFArray{ComplexF32}, 8192, 8192); b=rand(AFArray{ComplexF32}, 8192, 8192))
  ╠═╡ =#

# ╔═╡ 8d230e31-8b13-4c59-ac4d-1efc102a5623
# ╠═╡ show_logs = false
BA = load("../data/Touhou - Bad Apple.mp4");

# ╔═╡ d57b63e3-6cc9-4f40-bb27-107b68efc909
@bind frame Slider(1:length(BA), default=1684, show_value=true)

# ╔═╡ a21ae10f-c99b-49e9-b4dd-09d3932f289c
# ba = BA[frame] + imfilter(BA[frame], sharpening_factor*laplacian_kernel)
ba = BA[frame]

# ╔═╡ 5236f897-79ed-46f2-8b51-4aa5a0d78dec
begin
	ColorTypes.red(x::Gray) = x
	ColorTypes.green(x::Gray) = x
	ColorTypes.blue(x::Gray) = x
end

# ╔═╡ c9013e4d-890d-445a-a596-91374a1da046
begin
	ArrayFire.AFArray(a::Array{T,N} where {T<:AbstractGray, N}) =
    AFArray(Float32.(a))
ArrayFire.AFArray(a::Array{T,N} where {T<:AbstractRGB, N}) = 
    AFArray(Float32.(cat(red.(a), green.(a), blue.(a), dims=3)))
end

# ╔═╡ a7982c0e-b0a4-44e4-a9b8-f3482d096d1e
# Cell 5: Create coordinate grids
begin
    x = AFArray(collect(range(-Lx/2, Lx/2, Nx) .- xo))'
    y = AFArray(collect(range(-Ly/2, Ly/2, Ny) .- yo))
    X2 = 1*x.*x .+ 0*y
    Y2 = 0*x .+ 1*y.*y
    R = sqrt.(X2 .+ Y2 .+ Z^2)
end;

# ╔═╡ 05af9998-418c-4643-97fa-7581b23ffa52
# Cell 8: Define lens function
flens(λ) = exp.(2f0π * 1im * R / λ)

# ╔═╡ 745a43ac-aec6-44bc-8efa-77ede026d4b8
# ╠═╡ disabled = true
#=╠═╡
# Cell 9: Calculate lens phases
begin
	aϕlensG = flens(λg)
	aϕlensR = G_only ? aϕlensG : flens(λr)
	aϕlensB = G_only ? aϕlensG : flens(λb)
	# sync(aϕlensG), sync(aϕlensR), sync(aϕlensB)
end;
  ╠═╡ =#

# ╔═╡ 7c493e65-f49d-4663-979d-5f5c28e63454
# Cell 6: Generate random phase
aϕ_rand = [exp.(2f0π * im * rand(AFArray{Float32}, size(img)...)) for i in 1:3];

# ╔═╡ 54fc8894-8759-4ded-bc1a-c31661c44f5e
# Cell 7: Prepare input images with random phase
begin
    iR = AFArray(Float32.(red.(img))) .* aϕ_rand[1]
    iG = AFArray(Float32.(green.(img))) .* aϕ_rand[2]
    iB = AFArray(Float32.(blue.(img))) .* aϕ_rand[3]
end;

# ╔═╡ 81460640-0d9e-4bb6-a97b-6d94e533a8cf
function imconv(s::Array{T, N} where {T<:AbstractGray, N},
				k::Array{T, N} where {T<:Number, N})
    sdims = size(s)
    kdims = size(k)
    mdims = Tuple(max(a,b) for (a,b) in zip(sdims, kdims))
    mdims = fft_first_supported_size.(mdims)
    fft_supported(mdims) || error("ArrayFire FFT does not support dims $mdims")
    oshift = (sdims .+ kdims) .÷ -2
    sa = AFArray(s)
    ka = AFArray(k)
    fsa = fft2(sa, 1.0, mdims[1], mdims[2])
    fka = fft2(ka, 1.0, mdims[1], mdims[2])
    pa = shift(ifft2!(fsa .* fka), oshift[1], oshift[2], 0, 0)
    return Gray.(Array(real.(pa)))
end

# ╔═╡ cebdacb1-cc42-4698-9e11-5c2d81fb684c
fftshift(A::AFArray) = ArrayFire.shift(A, (size(A).÷2)..., 0, 0)

# ╔═╡ 0d53b881-03f5-4f03-92a4-60a89c0fee73
#=╠═╡
# Cell 11: Calculate final phases
begin
	ϕG =               use_image ? myconv(iG, fftshift(aϕlensG)) : aϕlensG
	ϕR = G_only ? ϕG : use_image ? myconv(iR, fftshift(aϕlensR)) : aϕlensR
	ϕB = G_only ? ϕG : use_image ? myconv(iB, fftshift(aϕlensB)) : aϕlensB
	# sync(ϕG), sync(ϕR), sync(ϕB)
end;
  ╠═╡ =#

# ╔═╡ 1e87f77c-e04e-40c0-a20c-e074a99682aa
# ╠═╡ disabled = true
#=╠═╡
ϕ = [ ϕR, ϕG, ϕB ];
  ╠═╡ =#

# ╔═╡ c7ff7d64-9302-410f-b601-ba94a742e652
ArrayFire.allowslow(AFArray, false)

# ╔═╡ 86c329a2-8e41-47f3-8d24-81c6acb94881
function af_pad_centered(A::AFArray, final::Tuple)
	extra = final .- size(A)
	bdims = Int.(floor.(extra ./ 2))
	edims = Int.(ceil.(extra ./ 2))
	return af_pad(A, bdims, edims)
end

# ╔═╡ 59df8948-694a-4c57-a3bc-3d5af5719cfe
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
aiG = AFArray(iG)
  ╠═╡ =#

# ╔═╡ 5d598fe0-9bbf-46be-8088-c0113842d99e
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
(Array(ArrayFire.sync(aiG)))
  ╠═╡ =#

# ╔═╡ ddb31ca4-cae8-4ba1-acf3-543f54783b6b
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
alensG = AFArray(ϕlensG)
  ╠═╡ =#

# ╔═╡ 4f5f2c11-144f-49a7-87d1-1e426f90593f
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
af_conv(a::Array, b::Array) = Array(ArrayFire.sync(af_conv(AFArray(a), AFArray(b))))
  ╠═╡ =#

# ╔═╡ 05db845c-6dba-4583-8c62-871f63126fad
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
aG = af_conv(iG, ϕlensG)
  ╠═╡ =#

# ╔═╡ 51fcfd36-6404-4c33-9832-61c7b61bfec5
let
	W, H = 4096, 4096
	Nf = 3
	Ns = 1
	
	image = rand(AFArray{ComplexF32}, W, H)
	kernel = rand(AFArray{ComplexF32}, W, H)
	bench_single = @benchmark sync(fft_convolve2($image, $kernel, $AF_CONV_DEFAULT))
	
	images = rand(AFArray{ComplexF32}, W, H, Ns, 1)
	kernels = rand(AFArray{ComplexF32}, W, H, 1, Nf)
	bench_multi = @benchmark sync(fft_convolve2($images, $kernels, $AF_CONV_DEFAULT))
	
	ts = minimum(bench_single.times)/1e6
	tm = minimum(bench_multi.times)/1e6
	N = Nf*Ns
	
	println("single=$ts ms, multi=$(tm/N) ms, speedup=$(ts/(tm/N))")
end

# ╔═╡ a1f83541-411d-4efb-b3e1-c91aed316bf6
function extract_central(matrix::AbstractArray, dims::Tuple{Int, Int}; offset::Tuple{Int, Int}=(0, 0))
  rows, cols = size(matrix)
  target_rows, target_cols = dims
  row_offset, col_offset = offset

  # Handle cases where dimensions are too large, considering the offset
  target_rows = min(target_rows, rows - abs(row_offset))
  target_cols = min(target_cols, cols - abs(col_offset))

  # Calculate the central starting position
  start_row = (rows - target_rows) ÷ 2 + 1 
  start_col = (cols - target_cols) ÷ 2 + 1

  # Apply the offset
  start_row += row_offset 
  start_col += col_offset

  # Calculate the ending positions
  end_row = start_row + target_rows - 1
  end_col = start_col + target_cols - 1

  # Ensure the extracted region stays within the matrix bounds
  start_row = max(start_row, 1)
  end_row = min(end_row, rows)
  start_col = max(start_col, 1)
  end_col = min(end_col, cols)

  return matrix[start_row:end_row, start_col:end_col]
end

# ╔═╡ 7f1b4f21-d822-4860-94f4-4cb610a34e39
begin
	
    mutable struct OpenFinchConnection
        send_channel::Channel
        receive_channel::Channel
        send_task::Task
        receive_task::Ref

		function OpenFinchConnection(URI)
		    send_channel = Channel(4)  # Channel for sending messages
		    receive_channel = Channel(4)  # Channel for received messages
			receive_task = Ref{Any}(nothing)
		    # Start task to handle sending and receiving messages asynchronously
		    send_task = @async begin
		        try
		            HTTP.WebSockets.open(URI) do ws
		                # Create a separate task for receiving messages
		                receive_task[] = @async begin
		                    while isopen(receive_channel)
		                        try
		                            received_msg = HTTP.WebSockets.receive(ws)
		                            message = try
										# @debug "trying to JSON parse message"
		                                JSON.parse(received_msg)
                                    catch e
										# @debug "JSON parsing failed"
                                        received_msg
                                    end
									# lock(receive_channel) do
                                    	if isfull(receive_channel)
											take!(receive_channel)
										end
										put!(receive_channel, message)
									# end
		                        catch e
		                            # @debug "WebSocket has been closed."
		                            break
		                        end
		                        sleep(0.01)  # Prevent tight loop from consuming too much CPU
		                    end
		                end
		
		                while isopen(send_channel)
		                    if isready(send_channel)  # Continue as long as there are messages to send
		                        message = take!(send_channel)
								if message isa Dict
		                        	jsmessage = JSON.json(message)
		                        	HTTP.WebSockets.send(ws, jsmessage)
								else
									HTTP.WebSockets.send(ws, message)
								end
		                    end
		                    sleep(0.01)  # Prevent tight loop from consuming too much CPU
		                end
		            end
		        catch e
		            @warn "Error in send/receive tasks: $e"
		        finally
		            close(send_channel)
		            close(receive_channel)
		        end
		    end
		
		    conn = new(send_channel, receive_channel, send_task, receive_task)
		    finalizer(close, conn)  # Register the finalizer
		    return conn
		end
	end

	function Base.close(conn::OpenFinchConnection)
	    close(conn.send_channel)
	    close(conn.receive_channel)
	    # wait(conn.send_task)
	    # wait(conn.receive_task)
	end

	function Base.put!(conn::OpenFinchConnection, obj)
		put!(conn.send_channel, obj)
	end

	function Base.take!(conn::OpenFinchConnection)
		conn.receive_channel.n_avail_items > 0 ? take!(conn.receive_channel) : nothing
	end

	isfull(ch) = !(ch.n_avail_items < ch.sz_max)
	
	OpenFinchConnection
end

# ╔═╡ 2537ce03-ddb0-4aab-a441-1531a5e6996d
openfinch = OpenFinchConnection(URI)

# ╔═╡ 98869068-79fb-42ee-9d21-d0c7f5a8ce1e
put!(openfinch, Dict(
	"use_base64_encoding"=>Dict("value"=>false),
	"send_fps_updates"=>Dict("value"=>false),
	"stream_frames"=>Dict("value"=>false),
))

# ╔═╡ 34fb3f29-eba3-4347-957a-c5d15199b3be
begin
	function send_controls(channel, controls::Dict)
	    put!(channel, Dict("set_control" => controls))  # Non-blocking put to the channel
	end

	function encode_image_file_to_base64(image_path::String)
	    open(image_path, "r") do file
	        return base64encode(file)
	    end
	end

	function encode_image(image::Array{<:Colorant}, fmt)
		io = IOBuffer()
		save(Stream{fmt}(io), image)  # Save the image as fmt to the IOBuffer
		seekstart(io)  # Reset the buffer's position to the beginning
		return io
	end
	
	function image_to_base64(image::Array{<:Colorant}; lossless=true)
		fmt = lossless ? format"GIF" : format"JPEG"
		return base64encode(encode_image(image, fmt))  # Encode the buffer's content to base64
	end

	function base64_to_image(buf)
		imbuf = Base64.base64decode(buf)
		return load(IOBuffer(imbuf))
	end

	function send_image(channel, image::Array{<:Colorant}; lossless=true)
		encoded_image = image_to_base64(image, lossless=lossless)
		put!(channel, Dict("slm_image" => encoded_image))
	end

	md"""
	## API for OpenFinch server
	"""
end

# ╔═╡ 8b76b762-aac2-43fe-9a54-b040f4342a1f
send_controls(openfinch, Dict("ILLUMINATION_MODE" => "421"));

# ╔═╡ 8a02142d-dd14-4ba8-9ad8-0bede5e16a5b
send_controls(openfinch, Dict(
	"ILLUMINATION_MODE" => G_only ? "222" : "421"
))

# ╔═╡ 697746d9-8baf-45a2-9eef-8c63857984b1
send_controls(openfinch, Dict(
	"LED_TIME" => LED_TIME,
	"LED_WIDTH" => LED_WIDTH,
	"ColourGains" => [red_gain, blue_gain],
	"AnalogueGain" => analog_gain,
	# "WAVE_DURATION" => round(Int, 8333*3.5),
	# "ScalerCrop" => [3, 0, 1456, 1088]
	# "ScalerCrop" => [0, 0, 64, 16]
	"NoiseReductionMode" => nrmode,
	"Brightness" => brightness,
	"Saturation" => saturation,
	"Contrast" => contrast,
	"Sharpness" => sharpness
));

# ╔═╡ cc316130-cf9e-4dd6-97ef-a114831644ad
begin
	Hue(x::HSV{T} where T) = x.h
	Sat(x::HSV{T} where T) = x.s
	Val(x::HSV{T} where T) = x.v

	MxNx3(x::Array{RGB{T},2} where T) = cat(red.(x), green.(x), blue.(x), dims=3)
	MxNx3(x::Array{HSV{T},2} where T) = cat(Hue.(x), Sat.(x), Val.(x), dims=3)
	MxNx3(x::Array{Lab{T},2} where T) = cat(getfield.(x, :l), getfield.(x, :a), getfield.(x, :b), dims=3)
	MxNx3(x::Array{YIQ{T},2} where T) = cat(getfield.(x, :y), getfield.(x, :i), getfield.(x, :q), dims=3)

	RGB(x::Array{T,3} where T) = RGB.(x[:,:,1], x[:,:,2], x[:,:,3])
	BGR2RGB(x::Array{T,3} where T) = RGB.(x[:,:,3], x[:,:,2], x[:,:,1])
	HSV(x::Array{T,3} where T) = HSV.(x[:,:,1], x[:,:,2], x[:,:,3])
	Lab(x::Array{T,3} where T) = Lab.(x[:,:,1], x[:,:,2], x[:,:,3])
	YIQ(x::Array{T,3} where T) = YIQ.(x[:,:,1], x[:,:,2], x[:,:,3])
	
	cv2RGB(x::Array{T,3} where T) = RGB.(x[:,:,3]/255, x[:,:,2]/255, x[:,:,1]/255)
	RGB2cv(x::Array{RGB{T},2} where T) = UInt8.(clamp.(round.(cat(blue.(x),green.(x),red.(x), dims=3)*255), 0, 255))
	
	ComplexToHSV(z::T where T<:Complex) = HSV(angle(z)*180/π, 1, abs(z))
	ComplexToHSV(z::T where T<:Real) = HSV(0, 0, abs(z))
	ComplexToHSV(z::AbstractArray) = ComplexToHSV.(z)
	# ComplexToHSV(z::T where T<:Number) = HSV(angle(z)*180/π, 1, abs(z))
	# ComplexToHSV(z::Array{T,N} where {T<:Number, N}) = HSV.(angle.(z)*180/π, 1, normalize(abs.(z)))
	
	md"## Conversion of RGB and ``M\times{N}\times{3}`` arrays"
end

# ╔═╡ ec89a498-e270-458c-a073-c3c26874f2ed
ColorTypes.RGB(z::Complex) = HSV(angle(z)*180/π, 1, abs(z))

# ╔═╡ 7c28d052-4bc1-4fea-bc61-3658b19ab81b
#=╠═╡
# Cell 12: Generate final CGH
cgh2 = G_only ? Gray.(Array(real.(ϕG).>0)) :
    RGB.(
        Array(real.(ϕR).>0),
        Array(real.(ϕG).>0),
        Array(real.(ϕB).>0)
    );
  ╠═╡ =#

# ╔═╡ 7c24efa5-de74-4e55-8768-5263ca5682f4
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
let
# Cell 4: Calculate basic parameters
begin
    xo, yo = MetersF32.((xoff, yoff) .* u"mm")
    dx = MetersF32(4.25u"µm")
    λs = MetersF32.([λR, λG, λB] .* u"nm")
    Nx, Ny = (1,1) .* lens_scale
    Lx, Ly = (Nx, Ny) .* dx
    Z = MetersF32((f+df)*u"mm")
    YO("dx=$dx, λs=$λs, Nx=$Nx, Lx=$Lx, Z=$Z, offset=($xoff, $yoff)")
end

# Cell 5: Create coordinate grids
begin
    x = AFArray(collect(range(-Lx/2, Lx/2, Nx) .- xo))'
    y = AFArray(collect(range(-Ly/2, Ly/2, Ny) .- yo))
    X2 = 1*x.*x .+ 0*y
    Y2 = 0*x .+ 1*y.*y
    R = sqrt.(X2 .+ Y2 .+ Z^2)
end

# Cell 6: Prepare input images with random phase
begin
    img_af = AFArray(Float32.(channelview(img)))
    aϕ_rand = exp.(2f0π * im * rand(AFArray{Float32}, size(img_af)...))
    i_with_phase = img_af .* aϕ_rand
end

# Cell 7: Define lens function
flens(λs) = exp.(2f0π * 1im * R ./ reshape(λs, 1, 1, :))

# Cell 8: Calculate lens phases
aϕlens = G_only ? flens([λs[2]]) : flens(λs)

# Cell 9: Define convolution function
function myconv(s::AFArray, k::AFArray)
    sdims = size(s)
    kdims = size(k)
    pdims = Tuple(max(a,b) for (a,b) in zip(sdims, kdims))
    YO("sdims=$sdims, kdims=$kdims, pdims=$pdims")
    sp = af_pad_centered(s, pdims)
    kp = af_pad_centered(k, pdims)
    YO("size(sp)=$(size(sp)), size(kp)=$(size(kp))")
    out = ifft(fft(sp) .* fft(kp))
end

# Cell 10: Calculate final phases
ϕ = use_image ? myconv(i_with_phase, fftshift(aϕlens)) : aϕlens

# Cell 11: Generate final CGH
begin
    cgh_af = real.(ϕ) .> 0
    if G_only
        cgh = Gray.(Array(cgh_af))
    else
        cgh = colorview(RGB, permutedims(Array(cgh_af), (3,1,2)))
    end
end

# Cell 12: Display the result
cgh
end
  ╠═╡ =#

# ╔═╡ 3162b0ae-627b-4511-b453-bb929e80203a
function paraxial_cgh(img, Z, lens_scale; G_only=true, offset=(0,0))
	MetersF32(x) = Float32(ustrip(u"m", x))
	YO(args...) = printstyled(stderr, "*** ", args..., "\n", reverse=true)
	# YO(args) = nothing

	xoff, yoff = MetersF32.(offset.*u"mm")
	dx = MetersF32(4.25u"µm")
	λr = MetersF32(λR*u"nm")
	λg = MetersF32(λG*u"nm")
	λb = MetersF32(λB*u"nm")
	scale = Float32(lens_scale)
	Nx, Ny = (1,1) .* lens_scale
	Lx, Ly = (Nx, Ny) .* dx
	Z = MetersF32(Z*u"mm")

	YO("dx=$dx, λG=$λG, Nx=$Nx, Lx=$Lx, Z=$Z, offset=($xoff, $yoff)")
	
	x = AFArray(collect(range(-Lx/2, Lx/2, Nx) .- xoff))'
	y = AFArray(collect(range(-Ly/2, Ly/2, Ny) .- yoff))
	X2 = 1*x.*x .+ 0*y
	Y2 = 0*x .+ 1*y.*y
	R = sqrt.(X2 .+ Y2 .+ Z^2);

	aϕ_rand = [exp.(2f0π * im * rand(AFArray{Float32}, size(img)...)) for i in 1:3];

	iR = AFArray(Float32.(red.(img))) .* aϕ_rand[1];
	iG = AFArray(Float32.(green.(img))) .* aϕ_rand[2];
	iB = AFArray(Float32.(blue.(img))) .* aϕ_rand[3];

	flens(λ) = exp.(2f0π * 1im * R / λ)
	
	aϕlensG = flens(λg)
	aϕlensR = G_only ? aϕlensG : flens(λr)
	aϕlensB = G_only ? aϕlensG : flens(λb)

	function myconv(s::AFArray, k::AFArray)
		sdims = size(s)
	    kdims = size(k)
	    mdims = Tuple(max(a,b) for (a,b) in zip(sdims, kdims))
	    mdims = fft_first_supported_size.(mdims)
	    fft_supported(mdims) || error("ArrayFire FFT does not support dims $mdims")
	    oshift = (sdims .+ kdims) .÷ -2
	    fsa = fft2(s, 1.0, mdims[1], mdims[2])
	    fka = fft2(k, 1.0, mdims[1], mdims[2])
	    pa = ifft2!(fsa .* fka)
		return ArrayFire.shift(pa, oshift[1], oshift[2], 0, 0)
	end

	ϕG = 			   use_image ? myconv(iG, fftshift(aϕlensG)) : aϕlensG;
	ϕR = G_only ? ϕG : use_image ? myconv(iR, fftshift(aϕlensR)) : aϕlensR;
	ϕB = G_only ? ϕG : use_image ? myconv(iB, fftshift(aϕlensB)) : aϕlensB;

	cgh = G_only ? Gray.(Array(real.(ϕG).>0)) :
		RGB.(
			Array(real.(ϕR).>0),
			Array(real.(ϕG).>0),
			Array(real.(ϕB).>0)
		)
end

# ╔═╡ 01bb1995-07c0-40d1-b5d3-9000a495ed96
cgh = paraxial_cgh(img, f+df, lens_scale, G_only=G_only, offset=(xoff, yoff));

# ╔═╡ 8ecb8b58-b343-40a8-a51f-5acc982e0dc1
slm_img = extract_central(cgh, (720, 1280))

# ╔═╡ 95b60065-9494-40a4-bdbb-41139ae8d86a
send_image(openfinch, slm_img)

# ╔═╡ ad9a8072-d972-4bcf-be8a-afce44db4812
RGB.(cgh)

# ╔═╡ 8f85b529-f96c-4cb8-bb3e-3d5cc4dacfbc
# ╠═╡ disabled = true
#=╠═╡
RGB.(iG), RGB.(Array(AFArray(iG)))
  ╠═╡ =#

# ╔═╡ 0d99ff55-5f08-4079-aeb7-4feab7ce389f
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
RGB.(Array(AFArray(iG))), RGB.(iG)
  ╠═╡ =#

# ╔═╡ bed6430e-89a7-4e0f-9804-827ff23f26d7
function decode_image(msg)
	if msg isa Dict
		try
			imbuf = Base64.base64decode(msg["image_response"]["image_base64"])
		catch e
			return nothing
		end
	else
		imbuf = msg
	end
	return load(IOBuffer(imbuf))
end

# ╔═╡ b99b1ae4-1855-4952-b1ab-f31734060cbb
dashboard_html = """
<!DOCTYPE html>
<html>

<head>
	<title>OpenFinch dashboard</title>
</head>

<body>
	<h1>OpenFinch dashboard</h1>

	<div>
		<input type="checkbox" id="stream_frames" name="stream_frames" unchecked>
		<label for="stream_frames">Stream Frames</label>
	</div>

	<div>
		<input type="checkbox" id="use_base64_encoding" name="use_base64_encoding" unchecked>
		<label for="use_base64_encoding">Use base64 encoding</label>
	</div>

	<div>
		<input type="checkbox" id="send_fps_updates" name="send_fps_updates" unchecked>
		<label for="send_fps_updates">Send FPS updates</label>
	</div>

	<p>

	<div style="position: relative;">
		<img id="image" alt="image">
		<div style="position: absolute; bottom: 0%; left: 6%; z-index: 10;">
			<p style="color: hsl(0, 0%, 0%); text-shadow: rgb(255, 255, 255) 0px 0px 15px;">
				Reader/Capture/Controller fps:
				<span id="image_capture_reader_fps">0</span> /
				<span id="image_capture_capture_fps">0</span> /
				<span id="system_controller_fps">0</span>
			</p>
		</div>
	</div>

	<script>
		// default values for host and port if they have not been previously defined
		if (typeof host === 'undefined') { var host = window.location.hostname; }
		if (typeof port === 'undefined') { var port = window.location.port; }
		var uri = 'ws://' + host + ':' + port + '/ws';
		console.log("dashboard: uri = " + uri);
		var ws = new WebSocket(uri);
		ws.binaryType = 'blob'; // Set the binaryType to 'blob'
		var throttle = false;
		var nextIsImage = false;

		ws.onopen = function (event) {
			// nothing yet
		};

		ws.onmessage = function (event) {
			if (nextIsImage && event.data instanceof Blob) {
				var imgElement = document.getElementById('image');
				if (imgElement.src !== '') {
					// console.log('Revoke blob URL:', imgElement.src);
					URL.revokeObjectURL(imgElement.src); // Revoke the old object URL
				}
				var url = URL.createObjectURL(event.data);
				imgElement.src = url;
				throttle = false;
				nextIsImage = false;
			} else {
				var data = JSON.parse(event.data);

				// Handle image response
				if (data.image_response) {
					if (data.image_response.image === 'next') {
						nextIsImage = true;
					} else if (data.image_response.image === 'here') {
						var imgElement = document.getElementById('image');
						var base64Image = data.image_response.image_base64;
						imgElement.src = 'data:image/jpeg;base64,' + base64Image;
						nextIsImage = false;
					}
					// Handle metadata response
					// if (data.image_response.metadata) {
					// 	document.getElementById('metadata').textContent = data.image_response.metadata;
					// }
					if (data.image_response.metadata) {
						var metadata = data.image_response.metadata;
						var prettyMetadata = JSON.stringify(metadata, null, 2); // Pretty-print the JSON object
						document.getElementById('metadata').textContent = prettyMetadata;
					}
				} else if (data.update_controls) {
					Object.keys(data.update_controls).forEach(function (key) {
						updateElementValue(key, data.update_controls[key]);
					});
				} else {
					// Handle updates for each control element
					Object.keys(data).forEach(function (key) {
						if (data[key] && data[key].hasOwnProperty('value')) {
							updateElementValue(key, data[key].value);
						}
					});

					// Handle FPS update
					if (data.fps_update) {
						if (data.fps_update.image_capture_reader_fps !== undefined) {
							document.getElementById('image_capture_reader_fps').textContent = data.fps_update.image_capture_reader_fps.toFixed(2);
						}
						if (data.fps_update.image_capture_capture_fps !== undefined) {
							document.getElementById('image_capture_capture_fps').textContent = data.fps_update.image_capture_capture_fps.toFixed(2);
						}
						if (data.fps_update.system_controller_fps !== undefined) {
							document.getElementById('system_controller_fps').textContent = data.fps_update.system_controller_fps.toFixed(2);
						}
					}
				}
			}
		};

		document.getElementById('stream_frames').addEventListener('change', function () {
			// Send the preference to the server using the websocket connection
			ws.send(JSON.stringify({ 'stream_frames': { 'value': this.checked } }));
		});

		document.getElementById('use_base64_encoding').addEventListener('change', function () {
			// Send the preference to the server using the websocket connection
			ws.send(JSON.stringify({ 'use_base64_encoding': { 'value': this.checked } }));
		});

		document.getElementById('send_fps_updates').addEventListener('change', function () {
			// Send the preference to the server using the websocket connection
			ws.send(JSON.stringify({ 'send_fps_updates': { 'value': this.checked } }));
		});

		function sendInitialControlStates(controlIds) {
			controlIds.forEach(id => {
				const controlElement = document.getElementById(id);
				if (controlElement) {
					const controlValue = controlElement.type === 'checkbox' ? controlElement.checked : controlElement.value;
					ws.send(JSON.stringify({
						'set_control': {
							[id]: controlValue
						}
					}));
				}
			});
		}
	</script>
</body>

</html>
""";

# ╔═╡ a6003b6c-beea-49ca-bbd3-fcdb62562b2b
HTML("""
<html><body><script> 
var host = "$host";
var port = "$port";
</script></body></html>
$dashboard_html
""");

# ╔═╡ 40e043b7-31cf-443b-9002-7d453222a6c7
md"""
## Persistent websocket API (experimental)
"""

# ╔═╡ 7189d73c-9299-464d-aed2-0d8e72f113e9
# from https://discourse.julialang.org/t/http-jl-websockets-help-getting-started/102867/4
function rawws(url,headers =[])
    headers = [
        "Upgrade" => "websocket",
        "Connection" => "Upgrade",
        "Sec-WebSocket-Key" => base64encode(rand(Random.RandomDevice(), UInt8, 16)),
        "Sec-WebSocket-Version" => "13",
        headers...
    ]
    r = HTTP.openraw("GET",url,headers)[1]

    ws = WebSockets.WebSocket(r)
    return ws
end

# ╔═╡ 147e33f7-8d2a-4bb1-8e68-e229c9128c04
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
ws = rawws(URI);
  ╠═╡ =#

# ╔═╡ 13fc0230-ebc3-4711-acbb-63e51fa0cac3
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
WebSockets.send(ws, JSON.json(Dict(
	"use_base64_encoding"=>Dict("value"=>false),
	"send_fps_updates"=>Dict("value"=>false),
	"stream_frames"=>Dict("value"=>false),
)))
  ╠═╡ =#

# ╔═╡ b56b0c01-5667-4d9b-8657-bcdaab2ba27a
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
ws
  ╠═╡ =#

# ╔═╡ 718d0904-8d43-4d39-a5fb-b19a2d427e9b
# ╠═╡ disabled = true
# ╠═╡ skip_as_script = true
#=╠═╡
send(ws, JSON.json(Dict("image_request"=>true)))
  ╠═╡ =#

# ╔═╡ Cell order:
# ╟─86a65396-30db-4ace-b863-84f250a3ac4c
# ╟─32f9cb5e-3c8d-4d40-b43b-f14a3cb255f2
# ╟─ffcbbfe2-a8a0-474f-a1c8-b419bacc90e2
# ╟─5c459507-67eb-41fd-9ce6-3cd489601064
# ╠═2537ce03-ddb0-4aab-a441-1531a5e6996d
# ╠═98869068-79fb-42ee-9d21-d0c7f5a8ce1e
# ╟─a6003b6c-beea-49ca-bbd3-fcdb62562b2b
# ╠═8b76b762-aac2-43fe-9a54-b040f4342a1f
# ╟─9e0052e2-c13c-42a3-971c-d7482044c25f
# ╠═a4b4901b-6a6f-440d-867b-47e02796ebab
# ╠═2b2dd536-a71a-4364-910c-9106628a094b
# ╠═8ecb8b58-b343-40a8-a51f-5acc982e0dc1
# ╠═95b60065-9494-40a4-bdbb-41139ae8d86a
# ╟─3111a73e-c846-4153-97e2-3cae83b3e8cf
# ╠═3d8c0ba4-5145-4e61-821f-3bbd251f98c6
# ╠═a9d3b06b-2ee0-4694-b028-c4f6663d1a6c
# ╠═a7982c0e-b0a4-44e4-a9b8-f3482d096d1e
# ╠═7c493e65-f49d-4663-979d-5f5c28e63454
# ╠═54fc8894-8759-4ded-bc1a-c31661c44f5e
# ╠═05af9998-418c-4643-97fa-7581b23ffa52
# ╠═745a43ac-aec6-44bc-8efa-77ede026d4b8
# ╠═03eef203-2754-4bf2-a0b0-5de16b938498
# ╠═0d53b881-03f5-4f03-92a4-60a89c0fee73
# ╠═7c28d052-4bc1-4fea-bc61-3658b19ab81b
# ╠═7c24efa5-de74-4e55-8768-5263ca5682f4
# ╠═3162b0ae-627b-4511-b453-bb929e80203a
# ╠═01bb1995-07c0-40d1-b5d3-9000a495ed96
# ╠═c9013e4d-890d-445a-a596-91374a1da046
# ╠═1af812f7-41eb-48b6-bd4f-a68ad28d20f3
# ╠═81460640-0d9e-4bb6-a97b-6d94e533a8cf
# ╠═ad9a8072-d972-4bcf-be8a-afce44db4812
# ╠═8ebb273b-b87d-4cef-8a0c-f6e66d747b19
# ╠═e123e7de-7bd9-4b4a-880f-1f26c6c19e62
# ╠═d1fa707e-3ab8-4aed-bca6-7f75c95145ad
# ╠═1dcbea3d-11b9-4395-9e7c-5d5a1c658b28
# ╠═8a02142d-dd14-4ba8-9ad8-0bede5e16a5b
# ╠═697746d9-8baf-45a2-9eef-8c63857984b1
# ╠═ec89a498-e270-458c-a073-c3c26874f2ed
# ╟─b183ede1-7d1a-41d8-866e-ca1c826aca08
# ╠═266fc634-1a9d-45f8-9f20-2d79e477f0fa
# ╟─b3441c7d-a097-435d-b1da-46869b9d2193
# ╠═a58c5e86-b282-43a7-b74a-7dc8f1e49976
# ╠═cebdacb1-cc42-4698-9e11-5c2d81fb684c
# ╠═7a62814e-d46e-431b-91d1-18c95450351a
# ╠═5e75df4c-f952-4d80-9280-7c010bd26b9a
# ╠═21d8f8ad-9280-44be-8b66-ec8526640c5f
# ╠═c7ff7d64-9302-410f-b601-ba94a742e652
# ╠═86c329a2-8e41-47f3-8d24-81c6acb94881
# ╠═a7226d4a-0de6-4683-ac66-a679e5e4b83a
# ╠═a21ae10f-c99b-49e9-b4dd-09d3932f289c
# ╠═d57b63e3-6cc9-4f40-bb27-107b68efc909
# ╠═1ec2f842-9bba-4478-a159-35932d28e315
# ╠═d7b8aa39-8965-48c0-a095-74fa2ff5257c
# ╟─c0270980-f1d0-4ce3-8e48-ba8d720315f8
# ╠═8f85b529-f96c-4cb8-bb3e-3d5cc4dacfbc
# ╠═59df8948-694a-4c57-a3bc-3d5af5719cfe
# ╠═0d99ff55-5f08-4079-aeb7-4feab7ce389f
# ╠═ddb31ca4-cae8-4ba1-acf3-543f54783b6b
# ╠═05db845c-6dba-4583-8c62-871f63126fad
# ╠═5d598fe0-9bbf-46be-8088-c0113842d99e
# ╠═4f5f2c11-144f-49a7-87d1-1e426f90593f
# ╠═1e87f77c-e04e-40c0-a20c-e074a99682aa
# ╟─d4953849-16cb-4f3f-befe-57f1fc327735
# ╠═c10f6c81-bda1-443a-942c-6c0bcdab3c80
# ╠═51fcfd36-6404-4c33-9832-61c7b61bfec5
# ╠═b4fc462c-a529-4970-a0c0-c4b39cb8a51d
# ╠═8d230e31-8b13-4c59-ac4d-1efc102a5623
# ╠═5236f897-79ed-46f2-8b51-4aa5a0d78dec
# ╠═a1f83541-411d-4efb-b3e1-c91aed316bf6
# ╠═34fb3f29-eba3-4347-957a-c5d15199b3be
# ╟─7f1b4f21-d822-4860-94f4-4cb610a34e39
# ╟─cc316130-cf9e-4dd6-97ef-a114831644ad
# ╟─bed6430e-89a7-4e0f-9804-827ff23f26d7
# ╟─b99b1ae4-1855-4952-b1ab-f31734060cbb
# ╟─40e043b7-31cf-443b-9002-7d453222a6c7
# ╟─7189d73c-9299-464d-aed2-0d8e72f113e9
# ╠═147e33f7-8d2a-4bb1-8e68-e229c9128c04
# ╠═13fc0230-ebc3-4711-acbb-63e51fa0cac3
# ╠═b56b0c01-5667-4d9b-8657-bcdaab2ba27a
# ╠═718d0904-8d43-4d39-a5fb-b19a2d427e9b
