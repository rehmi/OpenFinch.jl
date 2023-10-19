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

def generate_image(brightness, contrast, gamma):
	# Create a random RGB image
	img = Image.fromarray(np.random.randint(0, 256, (1200, 1600, 3), dtype=np.uint8))

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

def push_image(brightness, contrast, gamma):
	img_str = generate_image(brightness, contrast, gamma)
	socketio.emit('image_response', {'image': img_str})

def push_random_image():
	global brightness, contrast, gamma
	img_str = generate_image(brightness, contrast, gamma)
	socketio.emit('image_response', {'image': img_str})

app = Flask(__name__)

socketio = SocketIO(app)

client_connected = False

brightness, contrast, gamma = (0.5, 0.5, 1.0)

@app.route('/')
def index():
	return render_template('pushy.html')

@socketio.on('control_change')
def handle_control_change(message):
	global brightness, contrast, gamma
	brightness = float(message.get('brightness'))
	contrast = float(message.get('contrast'))
	gamma = float(message.get('gamma'))
	# print(f"got control_change, brightness={brightness}, contrast={contrast}, gamma={gamma}")
	push_random_image()

@socketio.on('image_request')
def handle_image_request(message):
	brightness = float(message.get('brightness'))
	contrast = float(message.get('contrast'))
	gamma = float(message.get('gamma'))
	push_image(brightness, contrast, gamma)

@socketio.on('connect')
def handle_connect():
	def generate_images():
		global client_connected
		while client_connected:
			push_random_image()
			time.sleep(1)

	global client_connected
	if not client_connected:
		client_connected = True
		socketio.start_background_task(generate_images)

@socketio.on('disconnect')
def handle_disconnect():
	global client_connected
	client_connected = False
	yield()

if __name__ == '__main__':
	socketio.run(app, port=8086, debug=True)
