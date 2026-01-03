using OpenFinch
using Metal
using Test

const N = 4095

println("----------------------------------------------------")
println("Profiling 2D FFT for size $N x $N")

# Create data
x_cpu = rand(ComplexF32, N, N)
x_gpu = MtlArray(x_cpu)

# Create the plan to ensure kernels are compiled
println("Creating FFT plan to pre-compile kernels...")
plan = OpenFinch.WaveOptics.FFT.plan_fft2(x_gpu)
println("Plan created.")

# Warmup run
println("Performing warmup FFT...")
OpenFinch.WaveOptics.FFT.fft2!(x_gpu, plan)
Metal.synchronize()
println("Warmup complete.")


# Time the unprofiled version
println("\nTiming unprofiled FFT execution:")
start_time = time_ns()
OpenFinch.WaveOptics.FFT.fft2!(x_gpu, plan)
Metal.synchronize()
end_time = time_ns()
unprofiled_time = (end_time - start_time) / 1e6
println(" - Total unprofiled fft2! time: \t$(unprofiled_time) ms")

# Run the profiled version of the FFT
println("\nRunning profiled FFT execution:")
start_time = time_ns()
OpenFinch.WaveOptics.FFT.fft2_profiled!(x_gpu, plan)
end_time = time_ns()
profiled_time = (end_time - start_time) / 1e6
println(" - Total profiled fft2! time: \t\t$(profiled_time) ms")


println("\nProfiling complete.")
println("----------------------------------------------------")
