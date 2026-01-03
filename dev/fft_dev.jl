import OpenFinch
import OpenFinch.WaveOptics
import OpenFinch.WaveOptics.FFT
using FFTW
using Metal
using BenchmarkTools
using Test

sizes = [2*13, 3*11, 5*7, 16, 4096, 4095]
for N in sizes
    println("----------------------------------------------------")
    println("Testing 1D FFT for size $N")
    x_cpu = rand(ComplexF32, N)
    x_gpu = MtlArray(x_cpu)
    
    # The first call to fft! for a given size will compile the kernels and cache a plan.
    # We use @time to see the compilation overhead.
    println("First run (compiling and caching plan):")
    @time OpenFinch.WaveOptics.FFT.fft!(x_gpu)
    
    # Reference FFT for verification
    y_cpu = fft(x_cpu)
    
    # Check correctness
    @test y_cpu ≈ Array(x_gpu)
    
    println("\nBenchmarking 1D FFT for size $N (using cached plan)")
    
    # Benchmark custom FFT. The setup expression ensures we start with fresh data for each sample.
    # The plan is already cached, so this measures execution time only.
    gpu_time = @belapsed OpenFinch.WaveOptics.FFT.fft!(x_gpu_bench) setup=(x_gpu_bench = MtlArray($x_cpu))
    
    # Benchmark reference FFT
    cpu_time = @belapsed fft(x_cpu_bench) setup=(x_cpu_bench = deepcopy($x_cpu))
    
    println("GPU time: $gpu_time")
    println("CPU time: $cpu_time\n")
    
    println("Testing 2D FFT for size $N x $N")
    x_cpu_2d = rand(ComplexF32, N, N)
    x_gpu_2d = MtlArray(x_cpu_2d)
    
    # First call to fft2! to compile and cache the plan
    println("First run (compiling and caching plan):")
    @time OpenFinch.WaveOptics.FFT.fft2!(x_gpu_2d)
    
    # Reference FFT for verification
    y_cpu_2d = fft(x_cpu_2d)
    
    # Check correctness
    @test y_cpu_2d ≈ Array(x_gpu_2d)
    
    println("\nBenchmarking 2D FFT for size $N x $N (using cached plan)")
    
    # Benchmark custom 2D FFT
    gpu_time_2d = @belapsed OpenFinch.WaveOptics.FFT.fft2!(x_gpu_bench) setup=(x_gpu_bench = MtlArray($x_cpu_2d))
    
    # Benchmark reference 2D FFT
    cpu_time_2d = @belapsed fft(x_cpu_bench) setup=(x_cpu_bench = deepcopy($x_cpu_2d))
    
    println("GPU time: $gpu_time_2d")
    println("CPU time: $cpu_time_2d")
    println("----------------------------------------------------\n")
end
