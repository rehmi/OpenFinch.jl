# import matplotlib.pyplot as plt
# import matplotlib.image as mpimg

# img = mpimg.imread('misc/71D-PfmrvjL._AC_SL1200_.jpg')

# fig = plt.figure()
# ax = plt.Axes(fig, [0., 0., 1., 1.], )
# ax.set_axis_off()
# fig.add_axes(ax)

# ax.imshow(img)
# plt.show(block=False)
# figManager = plt.get_current_fig_manager()
# figManager.window.state('zoomed') # Fullscreen mode




import matplotlib.pyplot as plt
import matplotlib.image as mpimg
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg

img = mpimg.imread('misc/71D-PfmrvjL._AC_SL1200_.jpg')

fig = plt.figure()
ax = plt.Axes(fig, [0., 0., 1., 1.])
ax.set_axis_off()
fig.add_axes(ax)

ax.imshow(img)
plt.show(block=False)

# Get the current figure canvas
canvas = plt.gcf().canvas

# Make the figure fullscreen
if canvas.manager.window:
    canvas.manager.window.state('zoomed')