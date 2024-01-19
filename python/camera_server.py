import time
from Display import Display
import logging
import asyncio
import json
from PIL import Image, ImageEnhance, ImageOps
import numpy as np
from io import BytesIO
from aiohttp import web
import os
from stats_monitor import StatsMonitor
from camera_controller import CameraController

class CameraServer:
	def __init__(self):
		self.brightness, self.contrast, self.gamma = (0.5, 0.5, 1.0)
		self.img_height, self.img_width = 1200, 1600
		self.cam = CameraController()
		self.cam.set_cam_triggered()
		self.active_connections = set()
		self.update_t_cur_enable = False
		self.monitor_index = 1
		self.jpeg_quality = 75
		self.capture_stats = StatsMonitor("cam.capture")
		self.initialize_display()

	def initialize_display(self):
		# Initialize display and script/wave-related components
		self.display = Display()
		# XXX begin hack to ensure the display appears on monitor[0]
		self.display.move_to_monitor(0)
		self.display.update()
		self.display.move_to_monitor(0)
		self.display.update()
		# XXX end hack
  
	def update_display(self, img):
		img_array = np.array(img)
		self.display.set_image(img_array)
		self.display.display_image()
		self.display.update()

	async def on_startup(self, app):
		app['task'] = asyncio.create_task(self.periodic_task())

	async def periodic_task(self):
		while True:
			try:
				await self.send_captured_image(quality=self.jpeg_quality)
				await asyncio.sleep(0.010)
			except Exception as e:
				logging.info(f"periodic_task(): got exception {e}")

	def enhance_image(self, img, brightness, contrast, gamma):
		enhancer = ImageEnhance.Brightness(img)
		img = enhancer.enhance(brightness)
		img = img.point(lambda p: p ** (1.0 / gamma))
		enhancer = ImageEnhance.Contrast(img)
		img = enhancer.enhance(contrast)
		return img

	def image_to_blob(self, img, quality):
		encodedImage = BytesIO()
		img = ImageOps.grayscale(Image.fromarray(img))
		img.save(encodedImage, 'JPEG', quality=quality)
		encodedImage.seek(0)
		return encodedImage.read()

	async def send_str_and_bytes(self, ws, str_data, bytes_data):
		try:
			await ws.send_str(str_data)
			await ws.send_bytes(bytes_data)
		except Exception as e:
			logging.info(f"Error occurred while sending data on WebSocket {ws}: {e}")
			self.active_connections.remove(ws)

	async def send_captured_image(self, width=None, height=None, quality=75):
		if width is None:
			width = self.img_width
		if height is None:
			height = self.img_height
		start = time.time()
		img = self.cam.capture_frame()
		self.capture_stats.add_point(time.time() - start)
		if img is not None:
			if self.update_t_cur_enable:
				self.cam.update_t_cur()
				await self.update_led_time(self.cam.config.LED_TIME)
			self.cam.update_wave()
			img_bin = self.image_to_blob(img, quality)
			tasks = [self.send_str_and_bytes(ws, json.dumps({'image_response': {'image': 'next'}}), img_bin)
							for ws in list(self.active_connections)] # Create a copy of the set to avoid modifying it while iterating
			await asyncio.gather(*tasks)

	async def update_led_time(self, new_value):
		for ws in list(self.active_connections): # Create a copy of the set to avoid modifying it while iterating
			try:
				await ws.send_str(json.dumps({'LED_TIME': {'value': new_value}}))
			except Exception as e:
				logging.info(f"Error occurred while sending data on WebSocket {ws}: {e}")
				self.active_connections.remove(ws)
				
	async def handle_message(self, request):
		ws = web.WebSocketResponse()
		self.active_connections.add(ws)
		await ws.prepare(request)

		async for msg in ws:
			if msg.type == web.WSMsgType.TEXT:
				data = json.loads(msg.data)
    
				# logging.info(f"got msg {msg}")

				handlers = {
					'LED_TIME': lambda data: self.handle_led_time(data),
					'LED_WIDTH': lambda data: self.handle_led_width(data),
        			'image_request': lambda data: self.handle_image_request(data, ws),
   					'update_t_cur_enable': lambda data: self.handle_update_t_cur_enable(data),
					'JPEG_QUALITY': lambda data: self.handle_jpeg_quality(data)
					# Add more handlers as needed for other controls
				}
				
				for key, handler in handlers.items():
					if key in data:
						await handler(data[key])

				if data.get('SLM_image', '') == 'next':
					image_blob = await ws.receive_bytes()
					# logging.info(f"SLM_image received {len(image_blob)} bytes")
					img = Image.open(BytesIO(image_blob))
					# logging.info(f"img has type {type(img)} and size {img.size}")
					self.display.move_to_monitor(self.monitor_index)
					self.update_display(img)
		
		self.active_connections.remove(ws)

	async def handle_image_request(self, image_request, ws):
		# XXX this used to work but now that send_captured_image()
		# broadcasts to all connections we need to refactor it
		# await self.send_captured_image(ws)
  		return

	async def handle_update_t_cur_enable(self, update_t_cur_enable):
		self.update_t_cur_enable = update_t_cur_enable.get('value', False)

	async def handle_led_time(self, LED_TIME):
		self.cam.config.LED_TIME = int(LED_TIME.get('value', self.cam.config.LED_TIME))
		self.cam.update_wave()

	async def handle_led_width(self, LED_WIDTH):
		self.cam.config.LED_WIDTH = int(LED_WIDTH.get('value', self.cam.config.LED_WIDTH))
		self.cam.update_wave()
	
	async def handle_jpeg_quality(self, jpeg_quality):
		self.jpeg_quality = int(jpeg_quality.get('value', 10))
		
	async def handle_http(self, request):
		script_dir = os.path.dirname(__file__)
		if request.path == '/':
			file_path = os.path.join(script_dir, 'combo.html')
		else:
			file_path = os.path.join(script_dir, request.path.lstrip('/'))
		return web.FileResponse(file_path)
