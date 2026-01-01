using PythonCall
using Images
using TestImages
using BenchmarkTools

# Initialize torch in Julia
torch = pyimport("torch")
np = pyimport("numpy")

# Check for MPS availability
if pyconvert(Bool, torch.backends.mps.is_available())
    device = torch.device("mps")
    print("Using MPS device: $device")
else
    device = torch.device("cpu")
    print("MPS not available, using CPU.")
end


# Create a sample tensor on the selected device
x = torch.randn(4096, 4096).to(device)

# Perform an operation (example)
y = torch.exp(2f0π*im*x)


torch.mps.synchronize()

pyconvert(Array, y.cpu())


# Load the image
image = testimage("cameraman")


ch = channelview(Float32.(image))

# Convert the image to a torch tensor
image_tensor = torch.from_numpy(np.array(ch))

# Reshape to (batch, channel, height, width) format
# image_tensor = permutedims(image_tensor, (3, 2, 1))
# image_tensor = reshape(image_tensor, (1, size(image_tensor)...))

# Perform the 2D FFT
fft_result = torch.fft.fft2(image_tensor)

# Shift zero frequency component to the center 
fft_shifted = torch.fft.fftshift(fft_result)

# Calculate the magnitude spectrum
magnitude_spectrum = torch.abs(fft_shifted)

# Convert the magnitude spectrum to a viewable image format
magnitude_spectrum = magnitude_spectrum[1, 1, :, :] # Select the first channel
magnitude_spectrum = magnitude_spectrum / maximum(magnitude_spectrum) # Normalize 
magnitude_spectrum = colorview(Gray, permutedims(Float32.(magnitude_spectrum.numpy()), (2, 1)))

# Display the magnitude spectrum
imshow(magnitude_spectrum) 

x = torch.randn(4096, 4096, device="mps")
@benchmark y = torch.fft.fft(x)
y_abs = y.abs()


##

using PythonCall

# Import PyTorch
torch = PythonCall.pyimport("torch")

# pytorch backends: cpu, cuda, ipu, xpu, mkldnn, opengl, opencl, ideep, hip, ve, fpga, ort, xla, lazy, vulkan, mps, meta, hpu, mtia, private

function _get_device(backend::String="auto")
    """Returns the PyTorch device based on the backend string.

    Args:
        backend (str): The desired backend ("mps", "cuda", or "cpu").

    Returns:
        torch.device: The PyTorch device.

    Raises:
        ValueError: If the specified backend is invalid or unavailable.
    """

    try
        if backend == "mps" && pytruth(torch.backends.mps.is_available())
            return torch.device("mps")
        elseif backend == "cuda" && pytruth(torch.cuda.is_available())
            return torch.device("cuda")  # Use the first CUDA device
        # elseif backend == "rocm" && pytruth(torch.rocm.is_available())
        #     return torch.device("rocm:0")  # Use the first ROCm device
        elseif backend == "cpu"
            return torch.device("cpu")
        else
            available_backends = ["cpu"]
            if pytruth(torch.cuda.is_available())
                push!(available_backends, "cuda")
            end
            # if pytruth(torch.rocm.is_available())
            #     push!(available_backends, "rocm")
            # end
            if pytruth(torch.backends.mps.is_available())
                push!(available_backends, "mps")
            end
            error("Invalid or unavailable backend: '$backend'. Available backends: $available_backends")
        end
    catch e
        # Handle potential Python exceptions (e.g., missing modules)
        error("Error checking for backend availability: $(e.msg)") 
    end
end


function _get_torch_dtype(dtype::Type)
    """Maps Julia dtype to PyTorch dtype."""
    dtype_map = Dict(
        Float32 => torch.float32,
        Float64 => torch.float64,
        ComplexF32 => torch.complex64,
        ComplexF64 => torch.complex128
    )
    return dtype_map[dtype]
end

function generate_random_matrix(rows, cols; backend="mps", dtype=Float32)
    """Generates a matrix of random numbers on the specified backend and data type.

    Args:
        rows: Number of rows in the matrix.
        cols: Number of columns in the matrix.
        backend: Backend to use ("mps" or "cpu"). Defaults to "mps".
        dtype: Data type of the matrix (Float32, Float64, ComplexF32, ComplexF64). Defaults to Float32.

    Returns:
        A Julia Matrix containing the random numbers. 
    """

    device = _get_device(backend)
    torch_dtype = _get_torch_dtype(dtype)

    # Generate random numbers directly on the chosen device
    random_matrix = torch.rand((rows, cols), dtype=torch_dtype, device=device)

    # Transfer to CPU and convert to Julia Matrix
    return pyconvert(Matrix{dtype}, random_matrix.cpu().numpy())
end

# Generate a random matrix 
random_matrix = generate_random_matrix_mps(4,4) 

println(random_matrix)

