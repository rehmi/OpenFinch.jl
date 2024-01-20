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
		self.update_t_cur_enable = False
		self.monitor_index = 1
		self.jpeg_quality = 75
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
  
	async def send_fps_update(self):
		try:
			fps_data = {
				'image_capture_reader_fps': self.cam.vidcap.reader_fps.get_fps(),
				'image_capture_capture_fps': self.cam.vidcap.capture_fps.get_fps(),
				'system_controller_fps': self.cam.fps_logger.get_fps()
			}
			# fps_data = {k: v for k, v in fps_data.items() if v is not None}
			if fps_data:
				tasks = [ws.send_str(json.dumps({'fps_update': fps_data}))
							for ws in list(self.active_connections)]
				await asyncio.gather(*tasks)
		except Exception as e:
			logging.exception("Exception in send_fps_update")

	async def on_startup(self, app):
		app['task'] = asyncio.create_task(self.periodic_task())

	async def periodic_task(self):
		while True:
			try:
				await self.send_captured_image(quality=self.jpeg_quality)
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
		try:
			await ws.send_str(str_data)
			await ws.send_bytes(bytes_data)
		except Exception as e:
			logging.info(f"Error occurred while sending data on WebSocket {ws}: {e}")
			try:
				self.active_connections.remove(ws)
			except KeyError:
				pass

	async def send_captured_image(self, width=None, height=None, quality=75):
		if width is None:
			width = self.img_width
		if height is None:
			height = self.img_height
		frame = self.cam.capture_frame()
		if frame is not None:
			if self.update_t_cur_enable:
				self.cam.update_t_cur()
				await self.update_led_time(self.cam.config.LED_TIME)
			self.cam.update_wave()
	
			# img = frame.to_grayscale()
			# img_bin = self.image_to_blob(img, quality)
			img_bin = frame.to_bytes()
   
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
					'WAVE_DURATION': lambda data: self.handle_wave_duration(data),
        			'image_request': lambda data: self.handle_image_request(data, ws),
   					'update_t_cur_enable': lambda data: self.handle_update_t_cur_enable(data),
					'JPEG_QUALITY': lambda data: self.handle_jpeg_quality(data),
				    'camera_mode': lambda data: self.handle_camera_mode(data),
    				'exposure_absolute': lambda data: self.handle_exposure_absolute(data),
					'brightness': lambda data: self.handle_brightness(data),
					'contrast': lambda data: self.handle_contrast(data),
					'saturation': lambda data: self.handle_saturation(data),
					'hue': lambda data: self.handle_hue(data),
					'gamma': lambda data: self.handle_gamma(data),
					'gain': lambda data: self.handle_gain(data),
					'power_line_frequency': lambda data: self.handle_power_line_frequency(data),
					'sharpness': lambda data: self.handle_sharpness(data),
					'backlight_compensation': lambda data: self.handle_backlight_compensation(data),
					'exposure_auto': lambda data: self.handle_exposure_auto(data),
					'exposure_auto_priority': lambda data: self.handle_exposure_auto_priority(data),
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
		
	async def handle_wave_duration(self, duration):
		self.cam.config.WAVE_DURATION = int(duration.get('value', self.cam.config.WAVE_DURATION))
		self.cam.update_wave()
 
	async def handle_camera_mode(self, camera_mode):
		if camera_mode['value'] == 'freerunning':
			self.cam.set_cam_freerunning()
		else:
			self.cam.set_cam_triggered()

	async def handle_exposure_absolute(self, exposure_absolute):
		self.cam.vidcap.control_set("exposure_absolute", int(exposure_absolute['value']))
  
	async def handle_brightness(self, brightness):
		self.cam.vidcap.control_set("brightness", int(brightness['value']))

	async def handle_contrast(self, contrast):
		self.cam.vidcap.control_set("contrast", int(contrast['value']))

	async def handle_saturation(self, saturation):
		self.cam.vidcap.control_set("saturation", int(saturation['value']))

	async def handle_hue(self, hue):
		self.cam.vidcap.control_set("hue", int(hue['value']))

	async def handle_gamma(self, gamma):
		self.cam.vidcap.control_set("gamma", int(gamma['value']))

	async def handle_gain(self, gain):
		self.cam.vidcap.control_set("gain", int(gain['value']))

	async def handle_power_line_frequency(self, power_line_frequency):
		self.cam.vidcap.control_set("power_line_frequency", int(power_line_frequency['value']))

	async def handle_sharpness(self, sharpness):
		self.cam.vidcap.control_set("sharpness", int(sharpness['value']))

	async def handle_backlight_compensation(self, backlight_compensation):
		self.cam.vidcap.control_set("backlight_compensation", int(backlight_compensation['value']))

	async def handle_exposure_auto(self, exposure_auto):
		self.cam.vidcap.control_set("exposure_auto", int(exposure_auto['value']))

	async def handle_exposure_auto_priority(self, exposure_auto_priority):
		self.cam.vidcap.control_set("exposure_auto_priority", int(exposure_auto_priority['value']))

	async def handle_http(self, request):
		script_dir = os.path.dirname(__file__)
		if request.path == '/':
			file_path = os.path.join(script_dir, 'dashboard.html')
		else:
			file_path = os.path.join(script_dir, request.path.lstrip('/'))
		return web.FileResponse(file_path)
