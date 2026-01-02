using OpenFinch
using FFTW
using Metal
using BenchmarkTools
using Test

sizes = [2*13, 3*11, 5*7, 16, 4096, 4095]
for N in sizes
    println("Testing 1D FFT for size $N")
    x_cpu = rand(ComplexF32, N)
    x_gpu = MtlArray(x_cpu)
    
    # Custom FFT
    OpenFinch.WaveOptics.FFT.fft!(x_gpu)
    
    # Reference FFT
    y_cpu = fft(x_cpu)
    
    @test y_cpu ≈ Array(x_gpu)
    
    println("Benchmarking 1D FFT for size $N")
    
    # Custom FFT
    gpu_time = @belapsed OpenFinch.WaveOptics.FFT.fft!($x_gpu)
    
    # Reference FFT
    cpu_time = @belapsed fft($x_cpu)
    
    println("GPU time: $gpu_time")
    println("CPU time: $cpu_time")
    
    println("Testing 2D FFT for size $N x $N")
    x_cpu = rand(ComplexF32, N, N)
    x_gpu = MtlArray(x_cpu)
    
    # Custom FFT
    OpenFinch.WaveOptics.FFT.fft2!(x_gpu)
    
    # Reference FFT
    y_cpu = fft(x_cpu)
    
    @test y_cpu ≈ Array(x_gpu)
    
    println("Benchmarking 2D FFT for size $N x $N")
    
    # Custom FFT
    gpu_time = @belapsed OpenFinch.WaveOptics.FFT.fft2!($x_gpu)
    
    # Reference FFT
    cpu_time = @belapsed fft($x_cpu)
    
    println("GPU time: $gpu_time")
    println("CPU time: $cpu_time")
end