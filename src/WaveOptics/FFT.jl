module FFT

using KernelAbstractions
using Metal
using AbstractFFTs

export fft!, fft2!, plan_fft, fft2_profiled!

mutable struct FFTPlan{T}
    backend::T
    factors::Tuple
    kernels::Vector{Any}
end

function plan_fft(x)
    backend = KernelAbstractions.get_backend(x)
    N = length(x)
    factors = Tuple(factorize(N))
    
    kernels = []
    
    push!(kernels, mixed_radix_permutation_kernel!(backend, 256))
    
    m = 1
    p = 1
    for f in factors
        if f == 2
            push!(kernels, fft_butterfly_kernel!(backend, 256))
        else
            kernel_func = Symbol("fft_radix$(f)_kernel!")
            push!(kernels, @eval $kernel_func($backend, 256))
        end
        m *= f
        p += 1
    end
    
    return FFTPlan(backend, factors, kernels)
end

@kernel function fft_butterfly_kernel!(y, x, N, m, p)
    i = @index(Global, Linear)

    # i is the thread index, from 1 to N/2
    # p is the stage, from 1 to log2(N)
    # m is 2^(p-1)

    i_minus_1 = i - 1
    # Determine the indices for the butterfly operation
    i0 = i_minus_1 & (m - 1)
    i1 = (i_minus_1 >> (p - 1)) << p
    j = i0 + i1

    # Twiddle factor
    twiddle = exp(-2im * Float32(pi) * i0 / (2 * m))

    # Butterfly operation
    a = x[j + 1]
    b = x[j + m + 1] * twiddle
    y[j + 1] = a + b
    y[j + m + 1] = a - b
end

@kernel function bit_reverse_permutation_kernel!(y, x)
    i = @index(Global, Linear)
    N = length(x)
    log2N = trailing_zeros(N)
    j = 0
    for k in 0:log2N-1
        if (i-1) & (1 << k) != 0
            j |= 1 << (log2N - 1 - k)
        end
    end
    y[j+1] = x[i]
end

@kernel function ifft_butterfly_kernel!(y, x, N, m, p)
    i = @index(Global, Linear)

    i_minus_1 = i - 1
    # Determine the indices for the butterfly operation
    i0 = i_minus_1 & (m - 1)
    i1 = (i_minus_1 >> (p - 1)) << p
    j = i0 + i1

    # Twiddle factor
    twiddle = exp(2im * Float32(pi) * i0 / (2 * m))

    # Butterfly operation
    a = x[j + 1]
    b = x[j + m + 1] * twiddle
    y[j + 1] = a + b
    y[j + m + 1] = a - b
end

@kernel function bluestein_prep_kernel!(x_padded, x, b)
    i = @index(Global, Linear)
    N = length(x)
    if i <= N
        x_padded[i] = x[i] * b[i]
    else
        x_padded[i] = 0
    end
end

@kernel function bluestein_postp_kernel!(y, y_conv, b)
    i = @index(Global, Linear)
    y[i] = y_conv[i] * b[i]
end

@kernel function mixed_radix_permutation_kernel!(y, x, factors)
    i = @index(Global, Linear)
    N = length(x)
    
    j = 0
    n = i - 1
    stride = 1
    rev_factors = reverse(factors)
    for f in rev_factors
        j = j * f + (n % f)
        n ÷= f
    end
    
    y[j+1] = x[i]
end

function factorize(N)
    factors = Int[]
    d = 2
    while d * d <= N
        while N % d == 0
            push!(factors, d)
            N ÷= d
        end
        d += 1
    end
    if N > 1
        push!(factors, N)
    end
    return factors
end

macro generate_radix_kernel(radix, direction)
    func_name = Symbol("$(direction)_radix$(radix)_kernel!")
    
    body = quote
        i = @index(Global, Linear)
        
        i_minus_1 = i - 1
        i0 = i_minus_1 % m
        i1 = div(i_minus_1, m) * $(radix) * m
        j = i0 + i1
    end

    val_vars = [Symbol("val_$k") for k in 0:(radix-1)]
    
    # First val
    push!(body.args, :(local $(val_vars[1]) = x[j + 1]))
    
    # Other vals with twiddles
    for k in 1:(radix-1)
        twiddle_expr = :(exp(($(direction == :fft ? -1 : 1)) * 2im * Float32(pi) * i0 * $(k) / ($(radix) * m)))
        push!(body.args, :(local $(val_vars[k+1]) = x[j + $(k)*m + 1] * $(twiddle_expr)))
    end
    
    # DFT matrix calculation
    for k in 0:(radix-1)
        # Unroll sum
        sum_expr = val_vars[1] # l=0 term
        for l in 1:(radix-1)
            w_expr = :(exp(($(direction == :fft ? -1 : 1)) * 2im * Float32(pi) * $(k * l) / $(radix)))
            term = :($(val_vars[l+1]) * $(w_expr))
            sum_expr = :($(sum_expr) + $(term))
        end
        push!(body.args, :(y[j + $(k)*m + 1] = $(sum_expr)))
    end

    func_def = quote
        @kernel function $(func_name)(y, x, N, m, p)
            $(body.args...)
        end
    end
    
    return esc(func_def)
end

@generate_radix_kernel(3, fft)
@generate_radix_kernel(5, fft)
@generate_radix_kernel(7, fft)
@generate_radix_kernel(11, fft)
@generate_radix_kernel(13, fft)


mutable struct FFTPlan2D{T}
    backend::T
    factors_rows::Tuple
    factors_cols::Tuple
    kernels_rows::Vector{Any}
    kernels_cols::Vector{Any}
    transpose_kernel::Any
end

function plan_fft2(x)
    backend = KernelAbstractions.get_backend(x)
    N, M = size(x)
    
    factors_rows = Tuple(factorize(N))
    factors_cols = Tuple(factorize(M))
    
    kernels_rows = []
    push!(kernels_rows, bit_reverse_permutation_kernel_2d!(backend, 256))
    m = 1
    p = 1
    for f in factors_rows
        if f == 2
            push!(kernels_rows, fft_row_butterfly_kernel!(backend, 256))
        else
            kernel_func = Symbol("fft_radix$(f)_row_kernel!")
            push!(kernels_rows, @eval $kernel_func($backend, 256))
        end
        m *= f
        p += 1
    end
    
    kernels_cols = []
    push!(kernels_cols, bit_reverse_permutation_kernel_2d!(backend, 256))
    m = 1
    p = 1
    for f in factors_cols
        if f == 2
            push!(kernels_cols, fft_row_butterfly_kernel!(backend, 256))
        else
            kernel_func = Symbol("fft_radix$(f)_row_kernel!")
            push!(kernels_cols, @eval $kernel_func($backend, 256))
        end
        m *= f
        p += 1
    end
    
    transpose_kernel = transpose_kernel!(backend, (16, 16))
    
    return FFTPlan2D(backend, factors_rows, factors_cols, kernels_rows, kernels_cols, transpose_kernel)
end

const plan_cache = Dict{Tuple{DataType, Int}, FFTPlan}()

function fft!(x_in, plan::FFTPlan)
    x = x_in
    N = length(x)
    
    y = similar(x)
    
    plan.kernels[1](y, x, plan.factors, ndrange=N)
    x, y = y, x
    
    m = 1
    p = 1
    for (i, f) in enumerate(plan.factors)
        if f == 2
            plan.kernels[i+1](y, x, N, m, p, ndrange=N÷2)
        else
            plan.kernels[i+1](y, x, N, m, p, ndrange=N÷f)
        end
        x, y = y, x
        m *= f
        p += 1
    end
    
    if x !== x_in
        x_in .= x
    end
    
    return x_in
end

function fft!(x_in, backend)
    key = (typeof(x_in), length(x_in))
    if !haskey(plan_cache, key)
        plan_cache[key] = plan_fft(x_in)
    end
    plan = plan_cache[key]
    return fft!(x_in, plan)
end

function fft!(x)
    return fft!(x, KernelAbstractions.get_backend(x))
end

@generate_radix_kernel(3, ifft)
@generate_radix_kernel(5, ifft)
@generate_radix_kernel(7, ifft)
@generate_radix_kernel(11, ifft)
@generate_radix_kernel(13, ifft)

function ifft!(x_in)
    x = x_in
    N = length(x)
    backend = KernelAbstractions.get_backend(x)
    
    factors = Tuple(factorize(N))
    
    if isempty(factors)
        x_in ./= N
        return x_in
    end

    y = similar(x)
    perm_kernel = mixed_radix_permutation_kernel!(backend, 256)
    perm_kernel(y, x, factors, ndrange=N)
    x, y = y, x
    
    m = 1
    p = 1
    for f in factors
        if f == 2
            kernel = ifft_butterfly_kernel!(backend, 256)
            kernel(y, x, N, m, p, ndrange=N÷2)
        else
            kernel_func = Symbol("ifft_radix$(f)_kernel!")
            kernel = @eval $kernel_func($backend, 256)
            kernel(y, x, N, m, p, ndrange=N÷f)
        end
        x, y = y, x
        m *= f
        p += 1
    end
    
    x ./= N
    
    if x !== x_in
        x_in .= x
    end
    
    return x_in
end

@kernel function transpose_kernel!(y, x)
    i, j = @index(Global, NTuple)
    y[j, i] = x[i, j]
end

@kernel function fft_row_butterfly_kernel!(y, x, m, p)
    row, i_half = @index(Global, NTuple)

    i_minus_1 = i_half - 1
    # Determine the indices for the butterfly operation
    i0 = i_minus_1 & (m - 1)
    i1 = (i_minus_1 >> (p - 1)) << p
    j = i0 + i1

    # Twiddle factor
    twiddle = exp(-2im * Float32(pi) * i0 / (2 * m))

    # Butterfly operation
    a = x[row, j + 1]
    b = x[row, j + m + 1] * twiddle
    y[row, j + 1] = a + b
    y[row, j + m + 1] = a - b
end

@kernel function ifft_row_butterfly_kernel!(y, x, m, p)
    row, i_half = @index(Global, NTuple)

    i_minus_1 = i_half - 1
    # Determine the indices for the butterfly operation
    i0 = i_minus_1 & (m - 1)
    i1 = (i_minus_1 >> (p - 1)) << p
    j = i0 + i1

    # Twiddle factor
    twiddle = exp(2im * Float32(pi) * i0 / (2 * m))

    # Butterfly operation
    a = x[row, j + 1]
    b = x[row, j + m + 1] * twiddle
    y[row, j + 1] = a + b
    y[row, j + m + 1] = a - b
end

@kernel function bit_reverse_permutation_kernel_2d!(y, x)
    row, col = @index(Global, NTuple)
    
    N = size(x, 2)
    log2N = trailing_zeros(N)
    
    j = 0
    n = col - 1
    for k in 0:log2N-1
        if (n >> k) & 1 != 0
            j |= 1 << (log2N - 1 - k)
        end
    end
    
    y[row, j+1] = x[row, col]
end


macro generate_radix_row_kernel(radix, direction)
    func_name = Symbol("$(direction)_radix$(radix)_row_kernel!")
    
    body = quote
        row, i = @index(Global, NTuple)
        
        i_minus_1 = i - 1
        i0 = i_minus_1 % m
        i1 = div(i_minus_1, m) * $(radix) * m
        j = i0 + i1
    end

    val_vars = [Symbol("val_$k") for k in 0:(radix-1)]
    
    # First val
    push!(body.args, :(local $(val_vars[1]) = x[row, j + 1]))
    
    # Other vals with twiddles
    for k in 1:(radix-1)
        twiddle_expr = :(exp(($(direction == :fft ? -1 : 1)) * 2im * Float32(pi) * i0 * $(k) / ($(radix) * m)))
        push!(body.args, :(local $(val_vars[k+1]) = x[row, j + $(k)*m + 1] * $(twiddle_expr)))
    end
    
    # DFT matrix calculation
    for k in 0:(radix-1)
        # Unroll sum
        sum_expr = val_vars[1] # l=0 term
        for l in 1:(radix-1)
            w_expr = :(exp(($(direction == :fft ? -1 : 1)) * 2im * Float32(pi) * $(k * l) / $(radix)))
            term = :($(val_vars[l+1]) * $(w_expr))
            sum_expr = :($(sum_expr) + $(term))
        end
        push!(body.args, :(y[row, j + $(k)*m + 1] = $(sum_expr)))
    end

    func_def = quote
        @kernel function $(func_name)(y, x, m, p)
            $(body.args...)
        end
    end
    
    return esc(func_def)
end

@generate_radix_row_kernel(3, fft)
@generate_radix_row_kernel(5, fft)
@generate_radix_row_kernel(7, fft)
@generate_radix_row_kernel(11, fft)
@generate_radix_row_kernel(13, fft)

@generate_radix_row_kernel(3, ifft)
@generate_radix_row_kernel(5, ifft)
@generate_radix_row_kernel(7, ifft)
@generate_radix_row_kernel(11, ifft)
@generate_radix_row_kernel(13, ifft)

function ifft_rows!(x_in, backend)
    x = x_in
    N, M = size(x)
    factors = Tuple(factorize(M))
    
    if isempty(factors)
        return x_in
    end

    y = similar(x)
    perm_kernel = mixed_radix_permutation_kernel_2d!(backend, 256)
    perm_kernel(y, x, factors, ndrange=(N, M))
    x, y = y, x
    
    m = 1
    p = 1
    for f in factors
        if f == 2
            kernel = ifft_row_butterfly_kernel!(backend, 256)
            kernel(y, x, m, p, ndrange=(N, M÷2))
        else
            kernel_func = Symbol("ifft_radix$(f)_row_kernel!")
            kernel = @eval $kernel_func($backend, 256)
            kernel(y, x, m, p, ndrange=(N, M÷f))
        end
        x, y = y, x
        m *= f
        p += 1
    end
    
    if x !== x_in
        x_in .= x
    end
    
    return x_in
end




const plan_cache_2d = Dict{Tuple{DataType, Int, Int}, FFTPlan2D}()

function fft_rows!(x_in, plan::FFTPlan2D, use_cols::Bool)
    x = x_in
    N, M = size(x)
    
    factors = use_cols ? plan.factors_cols : plan.factors_rows
    kernels = use_cols ? plan.kernels_cols : plan.kernels_rows
    
    if isempty(factors)
        return x_in
    end

    y = similar(x)
    kernels[1](y, x, ndrange=(N, M))
    x, y = y, x
    
    m = 1
    p = 1
    for (i, f) in enumerate(factors)
        if f == 2
            kernels[i+1](y, x, m, p, ndrange=(N, M÷2))
        else
            kernels[i+1](y, x, m, p, ndrange=(N, M÷f))
        end
        x, y = y, x
        m *= f
        p += 1
    end
    
    if x !== x_in
        x_in .= x
    end
    
    return x_in
end

function fft2!(x, plan::FFTPlan2D)
    N, M = size(x)
    
    fft_rows!(x, plan, false)
    
    # Transpose
    y = similar(x)
    plan.transpose_kernel(y, x, ndrange=(N, M))
    
    fft_rows!(y, plan, true)
    
    # Transpose back
    plan.transpose_kernel(x, y, ndrange=(M, N))
    
    return x
end

function fft2!(x, backend)
    key = (typeof(x), size(x, 1), size(x, 2))
    if !haskey(plan_cache_2d, key)
        plan_cache_2d[key] = plan_fft2(x)
    end
    plan = plan_cache_2d[key]
    return fft2!(x, plan)
end

function fft2!(x)
    return fft2!(x, KernelAbstractions.get_backend(x))
end

function fft_rows_profiled!(x_in, plan::FFTPlan2D, use_cols::Bool)
    total_start_time = time_ns()
    
    x = x_in
    N, M = size(x)
    
    factors = use_cols ? plan.factors_cols : plan.factors_rows
    kernels = use_cols ? plan.kernels_cols : plan.kernels_rows
    
    if isempty(factors)
        return x_in
    end

    y = similar(x)
    
    # Profile permutation kernel
    perm_start_time = time_ns()
    kernels[1](y, x, ndrange=(N, M))
    Metal.synchronize()
    perm_end_time = time_ns()
    println("  - Permutation kernel: \t$((perm_end_time - perm_start_time) / 1e6) ms")
    
    x, y = y, x
    
    m = 1
    p = 1
    for (i, f) in enumerate(factors)
        kernel_start_time = time_ns()
        if f == 2
            kernels[i+1](y, x, m, p, ndrange=(N, M÷2))
        else
            kernels[i+1](y, x, m, p, ndrange=(N, M÷f))
        end
        Metal.synchronize()
        kernel_end_time = time_ns()
        println("  - Radix-$f kernel: \t\t$((kernel_end_time - kernel_start_time) / 1e6) ms")
        
        x, y = y, x
        m *= f
        p += 1
    end
    
    if x !== x_in
        copy_start_time = time_ns()
        x_in .= x
        Metal.synchronize()
        copy_end_time = time_ns()
        println("  - Final copy: \t\t$((copy_end_time - copy_start_time) / 1e6) ms")
    end
    
    total_end_time = time_ns()
    println("  - Total fft_rows! time: \t$((total_end_time - total_start_time) / 1e6) ms")
    
    return x_in
end

function fft2_profiled!(x, plan::FFTPlan2D)
    total_start_time = time_ns()
    
    N, M = size(x)
    
    println(" - Profiling row-wise FFTs:")
    fft_rows_profiled!(x, plan, false)
    
    # Transpose
    y = similar(x)
    transpose_start_time = time_ns()
    plan.transpose_kernel(y, x, ndrange=(N, M))
    Metal.synchronize()
    transpose_end_time = time_ns()
    println(" - Transpose (1): \t\t$((transpose_end_time - transpose_start_time) / 1e6) ms")
    
    println(" - Profiling column-wise FFTs (after transpose):")
    fft_rows_profiled!(y, plan, true)
    
    # Transpose back
    transpose_back_start_time = time_ns()
    plan.transpose_kernel(x, y, ndrange=(M, N))
    Metal.synchronize()
    transpose_back_end_time = time_ns()
    println(" - Transpose (2): \t\t$((transpose_back_end_time - transpose_back_start_time) / 1e6) ms")
    
    total_end_time = time_ns()
    println(" - Total fft2! time: \t\t$((total_end_time - total_start_time) / 1e6) ms")
    
    return x
end

end
