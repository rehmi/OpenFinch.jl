using Test
using OpenFinch
using FFTW
using Metal

@testset "FFT Implementation" begin
    @testset "1D FFT" begin
        N = 256
        x_cpu = rand(ComplexF32, N)
        x_gpu = MtlArray(x_cpu)
        
        # Custom FFT
        OpenFinch.WaveOptics.FFT.fft!(x_gpu)
        
        # Reference FFT
        y_cpu = fft(x_cpu)
        
        @test y_cpu ≈ Array(x_gpu)
    end
    
    @testset "2D FFT" begin
        N = 256
        M = 256
        x_cpu = rand(ComplexF32, N, M)
        x_gpu = MtlArray(x_cpu)
        
        # Custom FFT
        OpenFinch.WaveOptics.FFT.fft2!(x_gpu)
        
        # Reference FFT
        y_cpu = fft(x_cpu)
        
        @test y_cpu ≈ Array(x_gpu)
    end
end