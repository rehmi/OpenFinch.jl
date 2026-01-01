# benchmarks/gpu_performance.jl
# Benchmark script to compare ArrayFire and KernelAbstractions.jl performance for key operations.

using BenchmarkTools
using KernelAbstractions
using BenchmarkTools
using Metal
using KernelAbstractions

# --- Configuration ---
# Define representative problem sizes (N x N)
sizes = [256, 1024, 3840]

# Number of benchmark samples for each operation
samples = 10

# --- Kernel Definition ---
@kernel function pointwise_mul_kernel!(A, B, C)
    i, j = @index(Global, NTuple)
    C[i, j] = A[i, j] * B[i, j]
end

# --- Benchmarking Functions ---

"""
Benchmark the performance of a pointwise multiplication operation.
"""
function benchmark_pointwise_mul(N::Int)
    A_cpu = rand(ComplexF32, N, N)
    B_cpu = rand(ComplexF32, N, N)
    C_cpu = similar(A_cpu)

    A_mtl = MtlArray(A_cpu)
    B_mtl = MtlArray(B_cpu)
    C_mtl = similar(A_mtl)

    kernel = pointwise_mul_kernel!(MetalBackend(), 256)

    metal_time = @belapsed begin
        $kernel($A_mtl, $B_mtl, $C_mtl, ndrange=size($A_mtl))
        KernelAbstractions.synchronize(MetalBackend())
    end samples=samples
    
    cpu_time = @belapsed $C_cpu .= $A_cpu .* $B_cpu samples=samples
    
    return ("KernelAbstractions (Metal)", metal_time), ("CPU", cpu_time)
end

# --- Run Benchmarks ---
println("Running benchmarks for Metal backend")
for N in sizes
    println("\n--- Size $N x $N ---")
    
    results = benchmark_pointwise_mul(N)
    
    println("Pointwise Multiplication:")
    for (label, time) in results
        if time !== nothing
            println("  $label: $(time*1e6) μs")
        end
    end
end
