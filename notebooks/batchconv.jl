# compare performance of sequential and parallel convolution

using ArrayFire
using Images

# Function to create a sample 3D tensor of grayscale images
function create_sample_images(width, height, num_images)
    return rand(UInt8, width, height, num_images)
end

# Function to create sample complex convolution kernels
function create_sample_kernels(kernel_size)
    return [complex.(rand(Float32, kernel_size...), 
                     rand(Float32, kernel_size...)) for _ in 1:3]
end

# Main convolution function
function convolve_images_with_kernels(images, kernels)
    # Convert images to ArrayFire array
    af_images = AFArray(images)
    
    # Initialize output array
    output_channels = Vector{AFArray}(undef, 3)
    
    for (i, kernel) in enumerate(kernels)
        # Convert kernel to ArrayFire array
        af_kernel = AFArray(ComplexF32.(kernel))
        
        # Perform convolution for each image in the stack
        conv_result = convolve2(af_images, af_kernel, AF_CONV_DEFAULT, AF_CONV_FREQ)
        
        # Store the result
        output_channels[i] = conv_result
    end
    
    return output_channels
end

# Main execution
function main()
    # Parameters
    width, height, num_images = 64, 64, 10
    kernel_size = (64, 64)
    
    # Create sample data
    images = create_sample_images(width, height, num_images)
    kernels = create_sample_kernels(kernel_size)
    
    # Perform convolution
    output_channels = convolve_images_with_kernels(images, kernels)
    
    # Print shapes of output channels
    for (i, channel) in enumerate(output_channels)
        println("Shape of output channel $i: ", size(channel))
    end
    
    # Optional: Convert back to host array and process further if needed
    # host_output = [Array(channel) for channel in output_channels]
end

# Run the main function
# main()

##

using ArrayFire
using BenchmarkTools
using Primes
using FFTW

aresults = []

fft_supported(n) = isempty(setdiff(factor(Set, n), Set([2, 3, 5, 7, 11, 13])))

for N ∈ 1:(2^16)
    if fft_supported(N)
        b = @benchmark sync(fft(v)) setup=(v=rand(AFArray{ComplexF32}, $N)) # seconds=1
        bt = minimum(b.times)/1e6
        push!(aresults, (N, bt))
        println("$N => $bt")
    end
end

data = vcat([[a b;] for (a,b) in aresults]...)
df = DataFrame(Any[Int.(data[:,1]) data[:,2]], [:n_fft, :t_ms])
CSV.write("afft_timing_finer.csv", df)

# TODO compare with timing estimates based on factorization

# collect FFT timing for FFTW

results = []

for N ∈ 1:(2^16)
    if fft_supported(N)
        b = @benchmark fft(v) setup=(v=rand(ComplexF32, $N))
        bt = minimum(b.times)/1e6
        push!(results, (N, bt))
        println("$N => $bt")
    end
end

data = vcat([[a b;] for (a,b) in results]...)
df = DataFrame(Any[Int.(data[:,1]) data[:,2]], [:n_fft, :t_ms])
CSV.write("fft_timing_finer.csv", df)

##

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

##

using ArrayFire
using TestImages
using Images
using BenchmarkTools
using Primes
using FFTW

ArrayFire.AFArray(a::Array{T,N} where {T<:AbstractGray, N}) =
    AFArray(Float32.(a))
ArrayFire.AFArray(a::Array{T,N} where {T<:AbstractRGB, N}) = 
    AFArray(Float32.(cat(red.(a), green.(a), blue.(a), dims=3)))

ColorTypes.Gray()

img_g = testimage("cameraman")
img_c = testimage("mandrill")

aimg_g = AFArray(img_g)
aimg_c = AFArray(img_c)

@benchmark Gray.(Array(shift(real.(ifft2!(fft2(aimg_g, 1, 8192, 8192))), 4096-256, 4096-256, 0, 0)))

fft_supported(n::Integer) = isempty(setdiff(factor(Set, n), Set([2, 3, 5, 7, 11, 13])))
fft_supported(t::Tuple) = all(fft_supported.(t))

function fft_first_supported_size(n::Integer)
    while !fft_supported(n)
        n += 1
    end
    return n
end

imp = zeros(ComplexF32, 2048, 2048)
imp[1024,1024] = 1
imp

function squash(a)
    lo,hi = extrema(a)
    return (a.-lo)./(hi-lo)
end

function imconv(s::Array{T, N} where {T<:AbstractGray, N}, k::Array{T, N} where {T<:Number, N})
    sdims = size(s)
    kdims = size(k)
    mdims = Tuple(max(a,b) for (a,b) in zip(sdims, kdims))
    mdims = fft_first_supported_size.(mdims)
    fft_supported(mdims) || error("ArrayFire FFT does not support dims $mdims")
    oshift = -1 .* (kdims .÷ 2)
    sa = AFArray(s)
    ka = AFArray((k))
    fsa = fft2(sa, 1.0, mdims[1], mdims[2])
    fka = fft2(ka, 1.0, mdims[1], mdims[2])
    pa = shift(ifft2!(fsa .* fka), oshift[1], oshift[2], 0, 0)
    return Gray.(Array(real.(pa)))
end

kimp5x5 = [0f0 0 0 0 0; 0 0 0 0 0; 0 0 1 0 0; 0 0 0 0 0; 0 0 0 0 0]
imconv(img_g, kimp5x5)

ra = range(-1f0, stop=1f0, length=2048)
Ra = (r->sqrt.((r.*r)'' .+ (r.*r)'))(ra)
k = sinc.(Array(200Ra))
Gray.(real.(k))

j = squash(imconv(img_g, k))
