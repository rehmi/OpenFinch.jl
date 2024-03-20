# After a lot of searching and false or complicated leads I found this brilliant method
# that allows to use a numpy array to get direct read/write access to the rpi framebuffer
# https://stackoverflow.com/questions/58772943/how-to-show-an-image-direct-from-memory-on-rpi
# I thought it is worth sharing again since so it might someone else some research time
#
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

import numpy as np
import os

tty = "/dev/tty1"

# this turns off the cursor blink:
#os.system (f"TERM=linux setterm -foreground black -clear all >{tty}")
os.system (f"TERM=linux setterm -cursor off >{tty}")

width=1280
height=720

# this is the frambuffer for analog video output - note that this is a 16 bit RGB
# other setups will likely have a different format and dimensions which you can check with
# fbset -fb /dev/fb0 
buf = np.memmap('/dev/fb0', dtype='uint16',mode='w+', shape=(height, width))

oldbuf = buf.copy()

# fill with white
buf[:] = 0xffff

randbuf = np.random.randint(0x10000,size=(height, width),dtype="uint16")

for x in range(width):
    # create random noise (16 bit RGB)
    b = randbuf.copy()
    # make vertical line at x black
    b[:,x] = 0
    # push to screen
    buf[:] = b

buf[:] = oldbuf
# turn on the cursor again:    
#os.system(f"TERM=linux setterm -foreground white -clear all >{tty}")
os.system (f"TERM=linux setterm -cursor on >{tty}")
