import asyncio
import websockets
import json
from PIL import Image, ImageEnhance, ImageOps
import numpy as np
import base64
from io import BytesIO
from aiohttp import web
import threading
import os
import pigpio
from ImageCapture import ImageCapture

def create_random_image(width=1600, height=1200):
	img = Image.fromarray(np.random.randint(0, 256, (height, width, 3), dtype=np.uint8))
	return img

def enhance_image(img, brightness, contrast, gamma):
	enhancer = ImageEnhance.Brightness(img)
	img = enhancer.enhance(brightness)
	img = img.point(lambda p: p ** (1.0 / gamma))
	enhancer = ImageEnhance.Contrast(img)
	img = enhancer.enhance(contrast)
	return img

def image_to_blob(img):
	encodedImage = BytesIO()
	img = Image.fromarray(img)
	img.save(encodedImage, 'JPEG')
	encodedImage.seek(0)
	return encodedImage.read()

def encode_to_string(binary_blob):
	img_base64 = base64.b64encode(binary_blob)
	return 'data:image/jpeg;base64,' + str(img_base64, 'utf-8')

def generate_image(brightness, contrast, gamma, width=1600, height=1200):
	img = create_random_image(width, height)
	img = enhance_image(img, brightness, contrast, gamma)
	return img

brightness, contrast, gamma = (0.5, 0.5, 1.0)
img_height, img_width = 1200, 1600
connected = set()

def initialize_image_capture(capture_raw=False):
	pi = pigpio.pi()
	pi.set_mode(17, pigpio.OUTPUT)  # set GPIO 17 as output
	pi.write(17, 0)  # set GPIO 17 to logic 0
	cap = ImageCapture(capture_raw=capture_raw)
	cap.control_set("exposure_auto_priority", 0)
	cap.open()
	return cap

async def send_random_image(ws, width=img_width, height=img_height):
	img = generate_image(brightness, contrast, gamma, height=img_height, width=img_width)
	img_bin = image_to_blob(img)
	await ws.send_str(json.dumps({'image_response': {'image': 'next'}}))
	await ws.send_bytes(img_bin)

async def send_captured_image(ws, width=img_width, height=img_height):
	global VideoCapture	# XXX
	img = vidcap.capture_frame()
	img_bin = image_to_blob(img)
	await ws.send_str(json.dumps({'image_response': {'image': 'next'}}))
	await ws.send_bytes(img_bin)

async def handle_message(request):
	ws = web.WebSocketResponse()
	await ws.prepare(request)

	async for msg in ws:
		if msg.type == web.WSMsgType.TEXT:
			data = json.loads(msg.data)
			control_change = data.get('control_change', {})
			image_request = data.get('image_request', {})

			global brightness, contrast, gamma

			brightness = float(control_change.get('brightness', image_request.get('brightness', brightness)))
			contrast = float(control_change.get('contrast', image_request.get('contrast', contrast)))
			gamma = float(control_change.get('gamma', image_request.get('gamma', gamma)))

			await send_captured_image(ws)
	return ws

async def handle_http(request):
	script_dir = os.path.dirname(__file__)  # get the directory of the current script
	if request.path == '/':
		file_path = os.path.join(script_dir, 'vanilla.html')  # construct the path to vanilla.html
	else:
		file_path = os.path.join(script_dir, request.path.lstrip('/'))  # construct the path to the requested file
	return web.FileResponse(file_path)

if __name__ == '__main__':
	vidcap = initialize_image_capture()

	# async def send_images():
	# 	while True:
	# 		img_str = generate_image(brightness, contrast, gamma, height=img_height, width=img_width)
	# 		if connected:
	# 			await asyncio.wait([asyncio.create_task(ws.send_str(json.dumps({'image_response': {'image': img_str}}))) for ws in connected])
	# 		await asyncio.sleep(1)

	app = web.Application()
	app.router.add_get('/', handle_http)
	app.router.add_get('/ws', handle_message)

	web.run_app(app, host='0.0.0.0', port=8000)
