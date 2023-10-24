from flask import Flask, render_template
from flask_socketio import SocketIO, emit
from PIL import Image, ImageEnhance, ImageOps
import numpy as np
import base64
from io import BytesIO
import random
import time
import threading
import io

def generate_image(brightness, contrast, gamma, width=1600, height=1200):
	# Create a random RGB image
	img = Image.fromarray(np.random.randint(0, 256, (height, width, 3), dtype=np.uint8))

	# Adjust brightness
	enhancer = ImageEnhance.Brightness(img)
	img = enhancer.enhance(brightness)

	# Adjust gamma
	img = img.point(lambda p: p ** (1.0 / gamma))

	# Adjust contrast
	enhancer = ImageEnhance.Contrast(img)
	img = enhancer.enhance(contrast)

	# Convert the image to base64
	buffered = BytesIO()
	img.save(buffered, format="JPEG")
	rawBytes = io.BytesIO()
	img.save(rawBytes, "JPEG")
	rawBytes.seek(0)
	img_base64 = base64.b64encode(rawBytes.read())
	return 'data:image/jpeg;base64,' + str(img_base64, 'utf-8')


brightness, contrast, gamma = (0.5, 0.5, 1.0)

def push_image(brightness, contrast, gamma, height=12, width=16):
	img_str = generate_image(brightness, contrast, gamma, height=height, width=width)
	socketio.emit('image_response', {'image': img_str})

def push_random_image(height=1200, width=1600):
	global brightness, contrast, gamma
	img_str = generate_image(brightness, contrast, gamma, height=height, width=width)
	socketio.emit('image_response', {'image': img_str})

app = Flask(__name__)

socketio = SocketIO(app)

client_connected = False

img_height, img_width = 12, 16

@app.route('/')
def index():
    print("*** index")
    return render_template('pushy.html')

@socketio.on('control_change')
def handle_control_change(message):
    print("*** handle_control_change")
    global brightness, contrast, gamma
    brightness = float(message.get('brightness'))
    contrast = float(message.get('contrast'))
    gamma = float(message.get('gamma'))
    print(f"got control_change, brightness={brightness}, contrast={contrast}, gamma={gamma}")
    push_random_image(height=img_height, width=img_width)

@socketio.on('image_request')
def handle_image_request(message):
    print("*** handle_image_request")
    brightness = float(message.get('brightness'))
    contrast = float(message.get('contrast'))
    gamma = float(message.get('gamma'))
    push_image(brightness, contrast, gamma, height=img_height, width=img_width)

@socketio.on('connect')
def handle_connect():
    print("*** handle_connect")
    def generate_images():
        print("*** generate_images in handle_connect")
        global client_connected
        while client_connected:
            push_random_image(height=12, width=16)
            time.sleep(1)

    global client_connected
    if not client_connected:
        client_connected = True
        socketio.start_background_task(generate_images)

@socketio.on('disconnect')
def handle_disconnect():
    print("*** handle_disconnect")
    global client_connected
    client_connected = False
    yield()

if __name__ == '__main__':
	socketio.run(app, port=8086, debug=True)
