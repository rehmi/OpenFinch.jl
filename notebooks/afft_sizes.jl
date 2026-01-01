procs = [ begin
	run(`julia -e "using ArrayFire; fft(rand(AFArray, $i))"`, wait=false)
end for i ∈ 1:1024 ]

##

good = getfield.(procs, :termsignal) .== 0
bad = (!).(good)

using Primes

good_factors = factor.((1:1024)[good])
bad_factors = factor.((1:1024)[bad])

good_prime_factors = Set()
bad_prime_factors = Set()

for f in good_factors
	p = first.(f.pe)
	if size(p)[1] .> 0
		push!(good_prime_factors, p...)
	end
end
good_factors = sort([good_prime_factors...])

for f in bad_factors
	p = first.(f.pe)
	if size(p)[1] .> 0
		push!(bad_prime_factors, p...)
	end
end
bad_factors = sort([bad_prime_factors...])

atest(m,n) = success(run(`julia -e "using ArrayFire; fft(rand(AFArray, $m, $n))"`))

##

# try to isolate Bus error bug when calling ArrayFire 3.9.0 on Apple Silicon

using ArrayFire
using ArrayFire: af_lib, af_err, af_array
using Base:RefValue

ENV["AF_TRACE"] = "all"
ENV["AF_PRINT_ERRORS"] = "1"

ag = rand(AFArray, 16);
ab = rand(AFArray, 17);

@ccall af_set_enable_stacktrace(1::Cint)::af_err

out = Ref{af_array}(0)
a = ab
res = @ccall af_fft(out::Ptr{af_array}, (a.arr)::af_array, Cdouble(1.0)::Cdouble, 0::dim_t)::af_err
str = @ccall af_err_to_string(res::af_err)::Cstring
unsafe_string(str)


##

msg = Ref{Cstring}()
len = Ref{dim_t}(0)

@ccall af_get_last_error(msg::Ptr{Cstring}, len::Ptr{dim_t})::Cvoid
unsafe_string(msg[])



