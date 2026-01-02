module FFT

using KernelAbstractions
using Metal
using AbstractFFTs

export fft!, fft2!

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

function fft!(x, backend)
    N = length(x)
    
    factors = Tuple(factorize(N))
    
    y = similar(x)
    perm_kernel = mixed_radix_permutation_kernel!(backend, 256)
    perm_kernel(y, x, factors, ndrange=N)
    x .= y
    
    m = 1
    p = 1
    for f in factors
        if f == 2
            kernel = fft_butterfly_kernel!(backend, 256)
            kernel(y, x, N, m, p, ndrange=N÷2)
        else
            kernel_func = Symbol("fft_radix$(f)_kernel!")
            kernel = @eval $kernel_func($backend, 256)
            kernel(y, x, N, m, p, ndrange=N÷f)
        end
        x .= y
        m *= f
        p += 1
    end
    
    return x
end

function fft!(x)
    return fft!(x, KernelAbstractions.get_backend(x))
end

@generate_radix_kernel(3, ifft)
@generate_radix_kernel(5, ifft)
@generate_radix_kernel(7, ifft)
@generate_radix_kernel(11, ifft)
@generate_radix_kernel(13, ifft)

function ifft!(x)
    N = length(x)
    backend = KernelAbstractions.get_backend(x)
    
    factors = Tuple(factorize(N))
    
    y = similar(x)
    perm_kernel = mixed_radix_permutation_kernel!(backend, 256)
    perm_kernel(y, x, factors, ndrange=N)
    x .= y
    
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
        x .= y
        m *= f
        p += 1
    end
    
    x ./= N
    
    return x
end

@kernel function transpose_kernel!(y, x)
    i, j = @index(Global, NTuple)
    y[j, i] = x[i, j]
end

@kernel function fft_row_butterfly_kernel!(x, m, p)
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
    x[row, j + 1] = a + b
    x[row, j + m + 1] = a - b
end

@kernel function bit_reverse_permutation_kernel_2d!(y, x)
    i, j = @index(Global, NTuple)
    N = size(x, 2)
    log2N = trailing_zeros(N)
    j_rev = 0
    for k in 0:log2N-1
        if (j-1) & (1 << k) != 0
            j_rev |= 1 << (log2N - 1 - k)
        end
    end
    y[i, j_rev+1] = x[i, j]
end

function fft2!(x, backend)
    N, M = size(x)
    
    # FFT each row
    for i in 1:N
        fft!(view(x, i, :), backend)
    end
    
    # Transpose
    y = similar(x)
    transpose_kernel = transpose_kernel!(backend, (16, 16))
    transpose_kernel(y, x, ndrange=(N, M))
    x .= y
    
    # FFT each "column" (which is now a row)
    for i in 1:M
        fft!(view(x, i, :), backend)
    end
    
    # Transpose back
    transpose_kernel(y, x, ndrange=(M, N))
    x .= y
    
    return x
end

function fft2!(x)
    return fft2!(x, KernelAbstractions.get_backend(x))
end

end