### A Pluto.jl notebook ###
# v0.19.42

using Markdown
using InteractiveUtils

# ╔═╡ dfee42d1-9878-44f9-a52c-969b0d375589
using BenchmarkTools, FFTW

# ╔═╡ de380a22-3ed4-4762-a530-fbc43e7f83b8
begin
	# ENV["AF_JIT_KERNEL_TRACE"] = joinpath(homedir(), "fardel", "tmp")
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
	ENV["AF_CUDA_MAX_JIT_LEN"] = "100"
	ENV["AF_OPENCL_MAX_JIT_LEN"] = "50"
	ENV["AF_SYNCHRONOUS_CALLS"] = "0"

	using Libdl
	((x,y)->x∈y||push!(y,x))("/opt/arrayfire/lib", Libdl.DL_LOAD_PATH)
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
	
	allowslow(AFArray, false)
	
	md"## ArrayFire extensions"
end

# ╔═╡ 2a22269a-6c4d-4b58-8a5e-d365fc48145a
N = 16384

# ╔═╡ a43d38ed-bdd1-46d2-b45d-aa5acb9dcda6
a = rand(ComplexF32, N, N);

# ╔═╡ dd8a1587-d8ba-4cf8-8c30-17b8c7f657bc
b = rand(ComplexF32, N, N);

# ╔═╡ e594a1d0-4977-4021-9b81-7ee2aca17f08
c = rand(ComplexF32, N, N);

# ╔═╡ 6acd759c-09ff-4218-9232-256f68b662a7
af = AFArray(a);

# ╔═╡ 3e87e01b-10ce-493e-b743-64f92d1fd5d7
bf = AFArray(b);

# ╔═╡ 542bf887-e131-4103-874c-5879438f9c0a
cf = AFArray(c);

# ╔═╡ 9bc8c86c-f8eb-4b92-89e7-1ea2d5fdf7f9
@benchmark ifft(c.*fft(a))

# ╔═╡ f56c09d7-f0e0-4c5a-ae0b-af53a4d1e53f
@benchmark Array(ifft(AFArray(c) .* fft(AFArray(a))))

# ╔═╡ 576f6c24-a10a-4be0-a0d7-587fb89ed369
@benchmark Array(ifft(cf .* fft(AFArray(a))))

# ╔═╡ 5c62780f-e368-41de-be59-a1c20543cb92
@benchmark Array(ifft(cf .* fft(af)))

# ╔═╡ 3a38c67a-4c70-4444-94bc-0a078670a57e
@benchmark ArrayFire.sync(ifft(cf .* fft(af)))

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
ArrayFire = "b19378d9-d87a-599a-927f-45f220a2c452"
BenchmarkTools = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"
FFTW = "7a1cc6ca-52ef-59f5-83cd-3a7055c09341"
Libdl = "8f399da3-3557-5675-b5ff-fb832c97cbdb"

[compat]
ArrayFire = "~1.0.7"
BenchmarkTools = "~1.5.0"
FFTW = "~1.8.0"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.10.4"
manifest_format = "2.0"
project_hash = "a5925ff96c7b8ae22eae55356a986b959b314f31"

[[deps.AbstractFFTs]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "d92ad398961a3ed262d8bf04a1a2b8340f915fef"
uuid = "621f4979-c628-5d54-868e-fcf4e3e8185c"
version = "1.5.0"

    [deps.AbstractFFTs.extensions]
    AbstractFFTsChainRulesCoreExt = "ChainRulesCore"
    AbstractFFTsTestExt = "Test"

    [deps.AbstractFFTs.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[deps.ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"
version = "1.1.1"

[[deps.ArrayFire]]
deps = ["DSP", "FFTW", "Libdl", "LinearAlgebra", "Random", "SparseArrays", "SpecialFunctions", "Statistics", "Test"]
git-tree-sha1 = "9153a509145fc1666b070a47ea5024c2242755be"
uuid = "b19378d9-d87a-599a-927f-45f220a2c452"
version = "1.0.7"

[[deps.Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"

[[deps.Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"

[[deps.BenchmarkTools]]
deps = ["JSON", "Logging", "Printf", "Profile", "Statistics", "UUIDs"]
git-tree-sha1 = "f1dff6729bc61f4d49e140da1af55dcd1ac97b2f"
uuid = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"
version = "1.5.0"

[[deps.Compat]]
deps = ["TOML", "UUIDs"]
git-tree-sha1 = "b1c55339b7c6c350ee89f2c1604299660525b248"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "4.15.0"
weakdeps = ["Dates", "LinearAlgebra"]

    [deps.Compat.extensions]
    CompatLinearAlgebraExt = "LinearAlgebra"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"
version = "1.1.1+0"

[[deps.DSP]]
deps = ["FFTW", "IterTools", "LinearAlgebra", "Polynomials", "Random", "Reexport", "SpecialFunctions", "Statistics"]
git-tree-sha1 = "2a63cb5fc0e8c1f0f139475ef94228c7441dc7d0"
uuid = "717857b8-e6f2-59f4-9121-6e50c889abd2"
version = "0.6.10"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"

[[deps.Downloads]]
deps = ["ArgTools", "FileWatching", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"
version = "1.6.0"

[[deps.ExprTools]]
git-tree-sha1 = "27415f162e6028e81c72b82ef756bf321213b6ec"
uuid = "e2ba6199-217a-4e67-a87a-7c52f15ade04"
version = "0.1.10"

[[deps.FFTW]]
deps = ["AbstractFFTs", "FFTW_jll", "LinearAlgebra", "MKL_jll", "Preferences", "Reexport"]
git-tree-sha1 = "4820348781ae578893311153d69049a93d05f39d"
uuid = "7a1cc6ca-52ef-59f5-83cd-3a7055c09341"
version = "1.8.0"

[[deps.FFTW_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "c6033cc3892d0ef5bb9cd29b7f2f0331ea5184ea"
uuid = "f5851436-0d7a-5f13-b9de-f02708fd171a"
version = "3.3.10+0"

[[deps.FileWatching]]
uuid = "7b1f6079-737a-58dc-b8bc-7a2ca5c1b5ee"

[[deps.InlineStrings]]
deps = ["Parsers"]
git-tree-sha1 = "9cc2baf75c6d09f9da536ddf58eb2f29dedaf461"
uuid = "842dd82b-1e85-43dc-bf29-5d0ee9dffc48"
version = "1.4.0"

[[deps.IntelOpenMP_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "be50fe8df3acbffa0274a744f1a99d29c45a57f4"
uuid = "1d5cc7b8-4909-519e-a0f8-d0f5ad9712d0"
version = "2024.1.0+0"

[[deps.InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"

[[deps.Intervals]]
deps = ["Dates", "Printf", "RecipesBase", "Serialization", "TimeZones"]
git-tree-sha1 = "ac0aaa807ed5eaf13f67afe188ebc07e828ff640"
uuid = "d8418881-c3e1-53bb-8760-2df7ec849ed5"
version = "1.10.0"

[[deps.IterTools]]
git-tree-sha1 = "42d5f897009e7ff2cf88db414a389e5ed1bdd023"
uuid = "c8e1da08-722c-5040-9ed9-7db0dc04731e"
version = "1.10.0"

[[deps.JLLWrappers]]
deps = ["Artifacts", "Preferences"]
git-tree-sha1 = "7e5d6779a1e09a36db2a7b6cff50942a0a7d0fca"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.5.0"

[[deps.JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "31e996f0a15c7b280ba9f76636b3ff9e2ae58c9a"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.4"

[[deps.LazyArtifacts]]
deps = ["Artifacts", "Pkg"]
uuid = "4af54fe1-eca0-43a8-85a7-787d91b784e3"

[[deps.LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"
version = "0.6.4"

[[deps.LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"
version = "8.4.0+0"

[[deps.LibGit2]]
deps = ["Base64", "LibGit2_jll", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"

[[deps.LibGit2_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll"]
uuid = "e37daf67-58a4-590a-8e99-b0245dd2ffc5"
version = "1.6.4+0"

[[deps.LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "MbedTLS_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"
version = "1.11.0+1"

[[deps.Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"

[[deps.LinearAlgebra]]
deps = ["Libdl", "OpenBLAS_jll", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"

[[deps.Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"

[[deps.MKL_jll]]
deps = ["Artifacts", "IntelOpenMP_jll", "JLLWrappers", "LazyArtifacts", "Libdl", "oneTBB_jll"]
git-tree-sha1 = "80b2833b56d466b3858d565adcd16a4a05f2089b"
uuid = "856f044c-d86e-5d09-b602-aeab76dc8ba7"
version = "2024.1.0+0"

[[deps.Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"

[[deps.MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"
version = "2.28.2+1"

[[deps.Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"

[[deps.Mocking]]
deps = ["Compat", "ExprTools"]
git-tree-sha1 = "bf17d9cb4f0d2882351dfad030598f64286e5936"
uuid = "78c3b35d-d492-501b-9361-3d52fe80e533"
version = "0.7.8"

[[deps.MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"
version = "2023.1.10"

[[deps.NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"
version = "1.2.0"

[[deps.OffsetArrays]]
git-tree-sha1 = "e64b4f5ea6b7389f6f046d13d4896a8f9c1ba71e"
uuid = "6fe1bfb0-de20-5000-8ca7-80f57d26f881"
version = "1.14.0"

    [deps.OffsetArrays.extensions]
    OffsetArraysAdaptExt = "Adapt"

    [deps.OffsetArrays.weakdeps]
    Adapt = "79e6a3ab-5dfb-504d-930d-738a2a938a0e"

[[deps.OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"
version = "0.3.23+4"

[[deps.OpenSpecFun_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "13652491f6856acfd2db29360e1bbcd4565d04f1"
uuid = "efe28fd5-8261-553b-a9e1-b2916fc3738e"
version = "0.5.5+0"

[[deps.Parsers]]
deps = ["Dates", "PrecompileTools", "UUIDs"]
git-tree-sha1 = "8489905bcdbcfac64d1daa51ca07c0d8f0283821"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.8.1"

[[deps.Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "FileWatching", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "REPL", "Random", "SHA", "Serialization", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"
version = "1.10.0"

[[deps.Polynomials]]
deps = ["Intervals", "LinearAlgebra", "OffsetArrays", "RecipesBase"]
git-tree-sha1 = "0b15f3597b01eb76764dd03c3c23d6679a3c32c8"
uuid = "f27b6e38-b328-58d1-80ce-0feddd5e7a45"
version = "1.2.1"

[[deps.PrecompileTools]]
deps = ["Preferences"]
git-tree-sha1 = "5aa36f7049a63a1528fe8f7c3f2113413ffd4e1f"
uuid = "aea7be01-6a6a-4083-8856-8a6e6704d82a"
version = "1.2.1"

[[deps.Preferences]]
deps = ["TOML"]
git-tree-sha1 = "9306f6085165d270f7e3db02af26a400d580f5c6"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.4.3"

[[deps.Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"

[[deps.Profile]]
deps = ["Printf"]
uuid = "9abbd945-dff8-562f-b5e8-e1ebf5ef1b79"

[[deps.REPL]]
deps = ["InteractiveUtils", "Markdown", "Sockets", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"

[[deps.Random]]
deps = ["SHA"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[[deps.RecipesBase]]
deps = ["PrecompileTools"]
git-tree-sha1 = "5c3d09cc4f31f5fc6af001c250bf1278733100ff"
uuid = "3cdcf5f2-1ef4-517c-9805-6587b60abb01"
version = "1.3.4"

[[deps.Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"
version = "0.7.0"

[[deps.Scratch]]
deps = ["Dates"]
git-tree-sha1 = "3bac05bc7e74a75fd9cba4295cde4045d9fe2386"
uuid = "6c6a2e73-6563-6170-7368-637461726353"
version = "1.2.1"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[deps.Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"

[[deps.SparseArrays]]
deps = ["Libdl", "LinearAlgebra", "Random", "Serialization", "SuiteSparse_jll"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"
version = "1.10.0"

[[deps.SpecialFunctions]]
deps = ["OpenSpecFun_jll"]
git-tree-sha1 = "d8d8b8a9f4119829410ecd706da4cc8594a1e020"
uuid = "276daf66-3868-5448-9aa4-cd146d93841b"
version = "0.10.3"

[[deps.Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"
version = "1.10.0"

[[deps.SuiteSparse_jll]]
deps = ["Artifacts", "Libdl", "libblastrampoline_jll"]
uuid = "bea87d4a-7f5b-5778-9afe-8cc45184846c"
version = "7.2.1+1"

[[deps.TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"
version = "1.0.3"

[[deps.TZJData]]
deps = ["Artifacts"]
git-tree-sha1 = "1607ad46cf8d642aa779a1d45af1c8620dbf6915"
uuid = "dc5dba14-91b3-4cab-a142-028a31da12f7"
version = "1.2.0+2024a"

[[deps.Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"
version = "1.10.0"

[[deps.Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[deps.TimeZones]]
deps = ["Dates", "Downloads", "InlineStrings", "Mocking", "Printf", "Scratch", "TZJData", "Unicode", "p7zip_jll"]
git-tree-sha1 = "a6ae8d7a27940c33624f8c7bde5528de21ba730d"
uuid = "f269a46b-ccf7-5d73-abea-4c690281aa53"
version = "1.17.0"
weakdeps = ["RecipesBase"]

    [deps.TimeZones.extensions]
    TimeZonesRecipesBaseExt = "RecipesBase"

[[deps.UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"

[[deps.Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"

[[deps.Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"
version = "1.2.13+1"

[[deps.libblastrampoline_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"
version = "5.8.0+1"

[[deps.nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"
version = "1.52.0+1"

[[deps.oneTBB_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "7d0ea0f4895ef2f5cb83645fa689e52cb55cf493"
uuid = "1317d2d5-d96f-522e-a858-c73665f53c3e"
version = "2021.12.0+0"

[[deps.p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"
version = "17.4.0+2"
"""

# ╔═╡ Cell order:
# ╠═dfee42d1-9878-44f9-a52c-969b0d375589
# ╠═2a22269a-6c4d-4b58-8a5e-d365fc48145a
# ╠═a43d38ed-bdd1-46d2-b45d-aa5acb9dcda6
# ╠═dd8a1587-d8ba-4cf8-8c30-17b8c7f657bc
# ╠═e594a1d0-4977-4021-9b81-7ee2aca17f08
# ╠═6acd759c-09ff-4218-9232-256f68b662a7
# ╠═3e87e01b-10ce-493e-b743-64f92d1fd5d7
# ╠═542bf887-e131-4103-874c-5879438f9c0a
# ╠═9bc8c86c-f8eb-4b92-89e7-1ea2d5fdf7f9
# ╠═f56c09d7-f0e0-4c5a-ae0b-af53a4d1e53f
# ╠═576f6c24-a10a-4be0-a0d7-587fb89ed369
# ╠═5c62780f-e368-41de-be59-a1c20543cb92
# ╠═3a38c67a-4c70-4444-94bc-0a078670a57e
# ╠═de380a22-3ed4-4762-a530-fbc43e7f83b8
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
