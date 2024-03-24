import requests
import numpy as np
from PIL import Image
from io import BytesIO
import numpy as np
import os

import subprocess
import re

def get_framebuffer_dimensions():
    # Execute the fbset command and capture its output
    fbset_output = subprocess.check_output(['fbset', '-fb', '/dev/fb0']).decode('utf-8')
    
    # Use regular expressions to find the geometry line
    match = re.search(r'geometry (\d+) (\d+)', fbset_output)
    if match:
        width, height = match.groups()
        return int(width), int(height)
    else:
        raise ValueError("Could not find framebuffer dimensions")

# The only caveat is that you will have to run this as root (sudo python yourscript.py), 
# But you can get around this if you add the current user to the "video" group like this:
# usermod -a -G video [user]
# source: https://medium.com/@avik.das/writing-gui-applications-on-the-raspberry-pi-without-a-desktop-environment-8f8f840d9867
# 
# in order to clear the cursor you probably also have to add the user to the tty group
# usermod -a -G tty [user]
# Potentially also to the dialout group (not so sure about that, but I did it before I realized that a reboot is required)
# usermod -a -G dialout [user]
# IMPORTANT you will have to reboot once for this to take effect

tty = "/dev/tty1"

def disable_cursor():
    # this turns off the cursor blink:
    #os.system (f"TERM=linux setterm -foreground black -clear all >{tty}")
    os.system (f"TERM=linux setterm -cursor off >{tty}")

width, height = get_framebuffer_dimensions()

def get_mapped_framebuffer():
    # this is the frambuffer for analog video output - note that this is a 16 bit RGB
    # other setups will likely have a different format and dimensions which you can check with
    # fbset -fb /dev/fb0 
    return np.memmap('/dev/fb0', dtype='uint16',mode='w+', shape=(height, width))

# oldbuf = FB.copy()

# fill with white
# buf[:] = 0xffff

# randbuf = np.random.randint(0x10000,size=(height, width),dtype="uint16")

# for x in range(width):
#     # create random noise (16 bit RGB)
#     b = randbuf.copy()
#     # make vertical line at x black
#     b[:,x] = 0
#     # push to screen
#     buf[:] = b

# buf[:] = oldbuf

def enable_cursor():
    # turn on the cursor again:    
    #os.system(f"TERM=linux setterm -foreground white -clear all >{tty}")
    os.system (f"TERM=linux setterm -cursor on >{tty}")

# Function to convert PIL image to 5-6-5 RGB format using NumPy
def convert_image_to_rgb565(image):
    # Convert the image to RGB if it's not already in RGB mode
    if image.mode != 'RGB':
        image = image.convert('RGB')

    # Convert the image to a NumPy array
    img_np = np.array(image)

    # Resize image to match your framebuffer's resolution, if necessary
    # img_np = cv2.resize(img_np, (framebuffer_width, framebuffer_height))

    # Convert pixels to 5-6-5 format
    r = (img_np[:,:,0] >> 3).astype(np.uint16)
    g = (img_np[:,:,1] >> 2).astype(np.uint16)
    b = (img_np[:,:,2] >> 3).astype(np.uint16)
    rgb565 = (r << 11) | (g << 5) | b

    # Convert the 5-6-5 RGB array to bytes
    return rgb565.tobytes()

# URL of the image
image_url = "https://www.belle-nuit.com/site/files/testchart720.tif"

# Fetch the image
response = requests.get(image_url)
img = Image.open(BytesIO(response.content))

# Convert the image to 5-6-5 RGB format
img_rgb565 = convert_image_to_rgb565(img)

disable_cursor()

# # Open the framebuffer device
# with open('/dev/fb0', 'wb') as fb:
#     # Write the image data to the framebuffer
#     fb.write(img_rgb565)

fb = get_mapped_framebuffer()

# Convert the byte array to a NumPy array of type uint16
img_rgb565_np = np.frombuffer(img_rgb565, dtype=np.uint16)

# Reshape the array to match the framebuffer's dimensions
# and assign the reshaped array to the framebuffer
fb[:] =  img_rgb565_np.reshape(height, width)

