using FFTW
using Images
using Plots
using Statistics

function propagate(field::Matrix, distance::Float64, wavelength::Float64, pixel_size::Float64)
    Ny, Nx = size(field)
    kx = 2π * fftfreq(Nx, 1/pixel_size)
    ky = 2π * fftfreq(Ny, 1/pixel_size)
    kx = fftshift(kx)
    ky = fftshift(ky)
    
    kxx, kyy = meshgrid(kx, ky)
    k = 2π / wavelength
    kz = sqrt.(Complex.(k^2 .- kxx.^2 .- kyy.^2))
    
    H = exp.(1im * kz * distance)
    U = fft(field)
    U_propagated = U .* H
    return ifft(U_propagated)
end

function gerchberg_saxton(target::Matrix{Float64}, num_iterations::Int, distance::Float64, wavelength::Float64, pixel_size::Float64)
    hologram = exp.(2im * π * rand(size(target)...))
    
    for _ in 1:num_iterations
        # Forward propagation
        field = propagate(hologram, distance, wavelength, pixel_size)
        
        # Apply amplitude constraint in target plane
        field = sqrt.(target) .* exp.(1im * angle.(field))
        
        # Backward propagation
        hologram = propagate(field, -distance, wavelength, pixel_size)
        
        # Apply phase-only constraint in hologram plane
        hologram = exp.(1im * angle.(hologram))
    end
    
    return hologram
end

function binary_gerchberg_saxton(target::Matrix{Float64}, num_iterations::Int, distance::Float64, wavelength::Float64, pixel_size::Float64)
    # Initialize with random binary amplitude
    hologram = Float64.(rand(size(target)...) .> 0.5)
    
    for _ in 1:num_iterations
        # Forward propagation
        field = propagate(hologram, distance, wavelength, pixel_size)
        
        # Apply amplitude constraint in target plane
        field = sqrt.(target) .* exp.(1im * angle.(field))
        
        # Backward propagation
        back_field = propagate(field, -distance, wavelength, pixel_size)
        
        # Apply binary amplitude constraint in hologram plane
        hologram = Float64.(abs.(back_field) .> median(abs.(back_field)))
    end
    
    return hologram
end

function simulate_result(hologram::Matrix, distance::Float64, wavelength::Float64, pixel_size::Float64)
    field = propagate(hologram, distance, wavelength, pixel_size)
    return abs2.(field)
end

function create_target(image_size::Tuple{Int, Int})
    target = zeros(image_size)
    center = image_size .÷ 2
    radius = min(image_size...) ÷ 4
    
    for i in 1:image_size[1], j in 1:image_size[2]
        if sqrt((i - center[1])^2 + (j - center[2])^2) < radius
            target[i, j] = 1.0
        end
    end
    
    return target
end

function meshgrid(x, y)
    X = repeat(x', length(y), 1)
    Y = repeat(y, 1, length(x))
    return X, Y
end

function create_grid_target(image_size::Tuple{Int, Int}, grid_size::Int=10)
    target = zeros(image_size)
    rows, cols = image_size
    
    # Calculate spacing between points
    row_spacing = rows ÷ (grid_size + 1)
    col_spacing = cols ÷ (grid_size + 1)
    
    # Create grid of points
    for i in 1:grid_size
        for j in 1:grid_size
            row = i * row_spacing
            col = j * col_spacing
            target[row, col] = 1.0
            
            # Optional: make points larger for better visibility
            for di in -1:1, dj in -1:1
                if 1 <= row+di <= rows && 1 <= col+dj <= cols
                    target[row+di, col+dj] = 1.0
                end
            end
        end
    end
    
    return target
end

##
# function main()
    # Set parameters
    image_size = (512, 512)
    num_iterations = 50
    distance = 0.001  # 1 mm
    wavelength = 632.8e-9  # 632.8 nm (He-Ne laser)
    pixel_size = 8e-6  # 8 µm

    # Create target intensity pattern
    target = create_target(image_size)
    target = create_grid_target(image_size)

	p1 = heatmap(target, aspect_ratio=:equal, title="Target", color=:grays)

    # Run Gerchberg-Saxton algorithm
    hologram = gerchberg_saxton(target, num_iterations, distance, wavelength, pixel_size)

    p2 = heatmap(angle.(hologram), aspect_ratio=:equal, title="Hologram Phase")

	# Run Binary Gerchberg-Saxton algorithm
	bhologram = binary_gerchberg_saxton(target, 3, distance, wavelength, pixel_size)
	
	p2b = heatmap(real.(bhologram), aspect_ratio=:equal, title="Binary amplitude hologram", color=:grays)


    # Simulate the result
    result = simulate_result(bhologram, distance, wavelength, pixel_size)

    p3 = heatmap(result, aspect_ratio=:equal, title="Simulated Result", color=:grays)
    
    # p = plot(p1, p2, p3, layout=(1,3), size=(1200, 400))
    # savefig("gerchberg_saxton_result.png")
	p3
# end

main()
