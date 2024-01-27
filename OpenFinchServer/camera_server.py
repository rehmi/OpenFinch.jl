import time
import logging
import asyncio
import json
from PIL import Image, ImageEnhance, ImageOps
import numpy as np
from io import BytesIO
from aiohttp import web
import os

from .Display import Display
from .system_controller import SystemController

class CameraServer:
	def __init__(self):
		self.brightness, self.contrast, self.gamma = (0.5, 0.5, 1.0)
		self.img_height, self.img_width = 1200, 1600
		self.cam = SystemController()
		self.cam.set_cam_triggered()
		self.active_connections = set()
		self.sweep_enable = False
		self.monitor_index = 1
		self.jpeg_quality = 75
  
		self.handlers = {
			'sweep_enable':
       			lambda data: self.handle_sweep_enable(data),
			'JPEG_QUALITY': lambda data: self.handle_jpeg_quality(data),
			'camera_mode': lambda data: self.handle_camera_mode(data),

			'LED_TIME': lambda data: self.handle_config_control('LED_TIME', data),
			'LED_WIDTH': lambda data: self.handle_config_control('LED_WIDTH', data),
			'WAVE_DURATION': lambda data: self.handle_config_control('WAVE_DURATION', data),

			'exposure_absolute': lambda data: self.handle_camera_control('exposure_absolute', data),
			'brightness': lambda data: self.handle_camera_control('brightness', data),
			'contrast': lambda data: self.handle_camera_control('contrast', data),
			'saturation': lambda data: self.handle_camera_control('saturation', data),
			'hue': lambda data: self.handle_camera_control('hue', data),
			'gamma': lambda data: self.handle_camera_control('gamma', data),
			'gain': lambda data: self.handle_camera_control('gain', data),
			'power_line_frequency': lambda data: self.handle_camera_control('power_line_frequency', data),
			'sharpness': lambda data: self.handle_camera_control('sharpness', data),
			'backlight_compensation': lambda data: self.handle_camera_control('backlight_compensation', data),
			'exposure_auto': lambda data: self.handle_camera_control('exposure_auto', data),
			'exposure_auto_priority': lambda data: self.handle_camera_control('exposure_auto_priority', data),
		}
  
		self.initialize_display()

	def initialize_display(self):
		# Initialize display and script/wave-related components
		self.display = Display()
		# XXX begin hack to ensure the display appears on monitor[0]
		self.display.move_to_monitor(0)
		self.display.update()
		self.display.move_to_monitor(0)
		self.display.update()
		self.display.hide_window()
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
				await self.send_captured_image()
				await self.send_fps_update()
				await asyncio.sleep(0.001)
			except Exception as e:
				logging.exception("Exception in periodic_task")
				raise e

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
		await ws.send_str(str_data)
		await ws.send_bytes(bytes_data)

	async def send_str(self, ws, str_data):
		await ws.send_str(str_data)

	async def active_connection_wrapper(self, ws, func, *args):
		try:
			return await func(ws, *args)
		except Exception as e:
			logging.info(f"active_connection_wrapper: error occurred on WebSocket {ws}: {e}")
			try:
				self.active_connections.remove(ws)
			except KeyError:
				pass

	async def broadcast_to_active_connections(self, func, *args):	
		tasks = [
			self.active_connection_wrapper(ws, func, *args)
	   		for ws in list(self.active_connections) # Create a copy of the set to avoid modifying it while iterating
		]

		await asyncio.gather(*tasks)

	async def send_captured_image(self):
		frame = self.cam.capture_frame()
		if frame is not None:
			# Perform a camera sweep and update LED timing if the sweep is enabled, then update the wave.
			# XXX This should be factored out of send_captured_image()
			if self.sweep_enable:
				self.cam.sweep()
				await self.update_led_time(self.cam.config.LED_TIME)
			self.cam.update_wave()
			# XXX end section to be factored out

			img_bin = frame.to_bytes()
			await self.broadcast_to_active_connections(self.send_str_and_bytes, json.dumps({'image_response': {'image': 'next'}}), img_bin)

	async def update_led_time(self, new_value):
		await self.broadcast_to_active_connections(self.send_str, json.dumps({'LED_TIME': {'value': new_value}}))

	async def update_control_value(self, control_name, new_value):
		await self.broadcast_to_active_connections(self.send_str, json.dumps({control_name: {'value': new_value}}))

	async def send_fps_update(self):
		try:
			fps_data = {
				'image_capture_reader_fps': self.cam.get_reader_fps(),
				'image_capture_capture_fps': self.cam.get_capture_fps(),
				'system_controller_fps': self.cam.get_controller_fps()
			}
			await self.broadcast_to_active_connections(
				self.send_str, json.dumps({'fps_update': fps_data})
			)
		except Exception as e:
			logging.exception("Exception in send_fps_update")

	async def handle_camera_control(self, control_name, control_data):
		value = int(control_data.get('value', 0))
		control_method = getattr(self.cam.vidcap, f"control_set")
		control_method(control_name, value)
	
	async def handle_config_control(self, control_name, control_data):
		value = int(control_data.get('value', 0))
		if control_name in ['LED_TIME', 'LED_WIDTH', 'WAVE_DURATION']:
			setattr(self.cam.config, control_name, value)
			self.cam.update_wave()

	async def handle_ws(self, request):
		ws = web.WebSocketResponse()
		self.active_connections.add(ws)
		await ws.prepare(request)

		# start a handler loop that persists as long as the websocket
		async for msg in ws:
			if msg.type == web.WSMsgType.TEXT:
				data = json.loads(msg.data)
	
				for key, handler in self.handlers.items():
					if key in data:
						await handler(data[key])

				if 'image_request' in data:
					self.handle_image_request(data, ws)

				if data.get('SLM_image', '') == 'next':
					image_blob = await ws.receive_bytes()
					# logging.info(f"SLM_image received {len(image_blob)} bytes")
					img = Image.open(BytesIO(image_blob))
					# logging.info(f"img has type {type(img)} and size {img.size}")
					self.display.move_to_monitor(self.monitor_index)
					self.update_display(img)
		
		# the websocket has closed or an error occurred.
		self.active_connections.remove(ws)

	async def handle_image_request(self, image_request, ws):
		# XXX this used to work but now that send_captured_image()
		# broadcasts to all connections we need to refactor it
		# await self.send_captured_image(ws)
		return

	async def handle_sweep_enable(self, sweep_enable):
		self.sweep_enable = sweep_enable.get('value', False)

	async def handle_jpeg_quality(self, jpeg_quality):
		self.jpeg_quality = int(jpeg_quality.get('value', 10))
		
	async def handle_camera_mode(self, camera_mode):
		if camera_mode['value'] == 'freerunning':
			self.cam.set_cam_freerunning()
		else:
			self.cam.set_cam_triggered()

	async def handle_http(self, request):
		script_dir = os.path.dirname(__file__)
		if request.path == '/':
			file_path = os.path.join(script_dir, 'dashboard.html')
		else:
			file_path = os.path.join(script_dir, request.path.lstrip('/'))
		return web.FileResponse(file_path)
