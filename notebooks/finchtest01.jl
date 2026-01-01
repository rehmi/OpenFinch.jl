using FFTW
using LinearAlgebra
using Plots

"""
Create a 2D meshgrid.
"""
function meshgrid(x, y)
    return (repeat(x', length(y), 1), repeat(y, 1, length(x)))
end

"""
Generate a circular array of point sources.
"""
function generate_point_sources(N, radius, grid_size)
    angles = range(0, 2π, length=N+1)[1:end-1]
    x = radius * cos.(angles)
    y = radius * sin.(angles)
    
    sources = zeros(ComplexF64, grid_size, grid_size)
    center = grid_size ÷ 2 + 1
    for (xi, yi) in zip(x, y)
        sources[round(Int, center + xi), round(Int, center + yi)] = 1.0 + 0.0im
    end
    
    return sources
end

"""
Compute the Fresnel-Kirchhoff propagator.
"""
function fresnel_kirchhoff_propagator(grid_size, dx, z, wavelength)
    kx, ky = meshgrid(fftfreq(grid_size, 1/dx), fftfreq(grid_size, 1/dx))
    k = 2π / wavelength
    kz = sqrt.(Complex.(k^2 .- kx.^2 .- ky.^2))
    return exp.(1im * kz * z)
end

"""
Perform Fresnel-Kirchhoff diffraction using FFT.
"""
function fresnel_kirchhoff_diffraction(field, dx, z, wavelength)
    grid_size = size(field, 1)
    propagator = fresnel_kirchhoff_propagator(grid_size, dx, z, wavelength)
    
    field_fft = fft(field)
    propagated_field_fft = field_fft .* propagator
    propagated_field = ifft(propagated_field_fft)
    
    return propagated_field
end

using Plots

"""
Main function to set up, run the simulation, and plot results.
"""
function main()
    # Parameters
    grid_size = 512
    dx = 10e-6  # 10 μm pixel size
    z = 0.1  # 10 cm propagation distance
    wavelength = 633e-9  # 633 nm (red light)
    num_sources = 16
    source_radius = 100  # in pixels

    # Generate source field
    source_field = generate_point_sources(num_sources, source_radius, grid_size)

    # Perform diffraction
    propagated_field = fresnel_kirchhoff_diffraction(source_field, dx, z, wavelength)

    # Calculate intensities
    propagated_intensity = abs2.(propagated_field)
    propagated_phase = angle.(propagated_field)

    # Create plots
    p1 = heatmap(propagated_intensity, 
                 title="Propagated Field Intensity",
                 xlabel="x (pixels)", ylabel="y (pixels)",
                 color=:RdBu, aspect_ratio=:equal)
    
    p2 = heatmap(propagated_phase, 
                 title="Propagated Field Phase",
                 xlabel="x (pixels)", ylabel="y (pixels)",
                 color=:RdBu, aspect_ratio=:equal)

    # Combine plots
    p0 = plot(p1, p2, layout=(1,2), size=(1000,400))

    # Save the plot
    # savefig("diffraction_result.png")

    # Display some statistics
    # println("Source field - Max intensity: ", maximum(source_intensity))
    # println("Source field - Min intensity: ", minimum(source_intensity))
    # println("Propagated field - Max intensity: ", maximum(propagated_intensity))
    # println("Propagated field - Min intensity: ", minimum(propagated_intensity))

    p0
end

# Run the simulation and generate plots
main()
