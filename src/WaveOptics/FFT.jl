module FFT

using KernelAbstractions
using Metal
using AbstractFFTs

export fft!, fft2!

@kernel function fft_butterfly_kernel!(x, N, m, p)
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
    x[j + 1] = a + b
    x[j + m + 1] = a - b
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

function fft!(x)
    N = length(x)
    backend = KernelAbstractions.get_backend(x)
    
    # Bit reversal permutation
    y = similar(x)
    kernel = bit_reverse_permutation_kernel!(backend, 256)
    kernel(y, x, ndrange=N)
    x .= y
    
    # Iterative Cooley-Tukey
    p = 1
    m = 1
    while m < N
        kernel = fft_butterfly_kernel!(backend, 256)
        kernel(x, N, m, p, ndrange=N÷2)
        m *= 2
        p += 1
    end
    
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

function fft2!(x)
    N, M = size(x)
    backend = KernelAbstractions.get_backend(x)
    
    # Bit reversal permutation
    y = similar(x)
    kernel = bit_reverse_permutation_kernel_2d!(backend, (16, 16))
    kernel(y, x, ndrange=(N, M))
    x .= y
    
    # FFT each row
    m = 1
    p = 1
    while m < M
        kernel = fft_row_butterfly_kernel!(backend, (16, 16))
        kernel(x, m, p, ndrange=(N, M÷2))
        m *= 2
        p += 1
    end
    
    # Transpose
    transpose_kernel = transpose_kernel!(backend, (16, 16))
    transpose_kernel(y, x, ndrange=(N, M))
    x .= y
    
    # Bit reversal permutation
    kernel = bit_reverse_permutation_kernel_2d!(backend, (16, 16))
    kernel(y, x, ndrange=(M, N))
    x .= y
    
    # FFT each "column" (which is now a row)
    m = 1
    p = 1
    while m < N
        kernel = fft_row_butterfly_kernel!(backend, (16, 16))
        kernel(x, m, p, ndrange=(M, N÷2))
        m *= 2
        p += 1
    end
    
    # Transpose back
    transpose_kernel(y, x, ndrange=(M, N))
    x .= y
    
    return x
end

end