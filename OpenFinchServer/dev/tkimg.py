from PIL import Image, ImageTk
import tkinter as tk
import time

root = tk.Tk()
root.attributes('-fullscreen', True) # Fullscreen mode

img = Image.open('misc/71D-PfmrvjL._AC_SL1200_.jpg')
photo = ImageTk.PhotoImage(img)

label = tk.Label(root, image=photo)
label.pack()

root.mainloop()

# root = tk.Tk()
