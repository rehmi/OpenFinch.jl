import asyncio
import websockets
import json
from PIL import Image, ImageEnhance, ImageOps
import numpy as np
import base64
from io import BytesIO
import random
import time
from http.server import HTTPServer, SimpleHTTPRequestHandler
import threading
import os

def generate_image(brightness, contrast, gamma, width=1600, height=1200):
	img = Image.fromarray(np.random.randint(0, 256, (height, width, 3), dtype=np.uint8))
	enhancer = ImageEnhance.Brightness(img)
	img = enhancer.enhance(brightness)
	img = img.point(lambda p: p ** (1.0 / gamma))
	enhancer = ImageEnhance.Contrast(img)
	img = enhancer.enhance(contrast)
	buffered = BytesIO()
	img.save(buffered, format="JPEG")
	rawBytes = BytesIO()
	img.save(rawBytes, "JPEG")
	rawBytes.seek(0)
	img_base64 = base64.b64encode(rawBytes.read())
	return 'data:image/jpeg;base64,' + str(img_base64, 'utf-8')

brightness, contrast, gamma = (0.5, 0.5, 1.0)
img_height, img_width = 12, 16

connected = set()

async def handle_message(websocket, path):
	# Add newly connected client
	connected.add(websocket)
	try:
		async for message in websocket:
			data = json.loads(message)
			control_change = data.get('control_change', {})
			image_request = data.get('image_request', {})
			global brightness, contrast, gamma

			brightness = float(control_change.get('brightness', image_request.get('brightness', brightness)))
			contrast = float(control_change.get('contrast', image_request.get('contrast', contrast)))
			gamma = float(control_change.get('gamma', image_request.get('gamma', gamma)))

			img_str = generate_image(brightness, contrast, gamma, height=img_height, width=img_width)
			await websocket.send(json.dumps({'image_response': {'image': img_str}}))
	finally:
		# Remove disconnected client
		connected.remove(websocket)
	
start_server = websockets.serve(handle_message, "localhost", 8086)

class MyHandler(SimpleHTTPRequestHandler):
	def end_headers(self):
		self.send_header('Access-Control-Allow-Origin', '*')
		SimpleHTTPRequestHandler.end_headers(self)

	def do_GET(self):
		if self.path == '/':
			self.path = '/vanilla.html'
		return SimpleHTTPRequestHandler.do_GET(self)

def start_http_server():
	os.chdir("templates")
	httpd = HTTPServer(('localhost', 8000), MyHandler)
	httpd.serve_forever()

# New coroutine to send an image_response every second
async def send_images():
	while True:
		img_str = generate_image(brightness, contrast, gamma, height=img_height, width=img_width)
		if connected:  # Only send if there is at least one connected client
			# await asyncio.wait([ws.send(json.dumps({'image_response': {'image': img_str}})) for ws in connected])
			await asyncio.wait([asyncio.create_task(ws.send(json.dumps({'image_response': {'image': img_str}}))) for ws in connected])
		await asyncio.sleep(1)  # Wait for one second

http_server_thread = threading.Thread(target=start_http_server)
http_server_thread.start()

loop = asyncio.get_event_loop()
loop.run_until_complete(start_server)
loop.create_task(send_images())
loop.run_forever()
