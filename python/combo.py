import time
from ImageCapture import ImageCapture
from Display import Display
from CameraControl import start_pig, trigger_wave_script, TriggerConfig
from CameraControl import PiGPIOScript, PiGPIOWave, CameraControlDefaults
import threading
from queue import Queue
import logging
import asyncio
import websockets
import json
from PIL import Image, ImageEnhance, ImageOps
import numpy as np
import base64
from io import BytesIO
from aiohttp import web
import os
import pigpio
import numpy as np

class CameraServer:
	def __init__(self):
		self.brightness, self.contrast, self.gamma = (0.5, 0.5, 1.0)
		self.img_height, self.img_width = 1200, 1600
		self.cam = CameraController()
		self.cam.set_cam_triggered()
		self.active_connections = set()
		self.update_t_cur_enable = False
		self.monitor_index = 1
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
				# logging.info("periodic_task executed")
				await self.send_captured_image()
				await asyncio.sleep(0.001)
			except Exception as e:
				logging.info(f"periodic_task(): got exception {e}")

	def enhance_image(self, img, brightness, contrast, gamma):
		enhancer = ImageEnhance.Brightness(img)
		img = enhancer.enhance(brightness)
		img = img.point(lambda p: p ** (1.0 / gamma))
		enhancer = ImageEnhance.Contrast(img)
		img = enhancer.enhance(contrast)
		return img

	def image_to_blob(self, img):
		encodedImage = BytesIO()
		img = Image.fromarray(img)
		img.save(encodedImage, 'JPEG')
		encodedImage.seek(0)
		return encodedImage.read()

	async def send_str_and_bytes(self, ws, str_data, bytes_data):
		await ws.send_str(str_data)
		await ws.send_bytes(bytes_data)

	async def send_captured_image(self, width=None, height=None):
		if width is None:
			width = self.img_width
		if height is None:
			height = self.img_height
		img = self.cam.capture_frame()
		if self.update_t_cur_enable:
			self.cam.update_t_cur()
			await self.update_led_time(self.cam.config.LED_TIME)
		self.cam.update_wave()
		img_bin = self.image_to_blob(img)
  
		tasks = []
		for ws in list(self.active_connections): # Create a copy of the set to avoid modifying it while iterating
			try:
				tasks.append(self.send_str_and_bytes(ws, json.dumps({'image_response': {'image': 'next'}}), img_bin))
			except Exception as e:
				logging.info(f"Error occurred while sending data on WebSocket {ws}: {e}")
				self.active_connections.remove(ws)

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

				handlers = {
					'LED_TIME': lambda data: self.handle_led_time(data),
					'LED_WIDTH': lambda data: self.handle_led_width(data),
        			'image_request': lambda data: self.handle_image_request(data, ws),
   					'update_t_cur_enable': lambda data: self.handle_update_t_cur_enable(data)
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
		return ws

	async def handle_image_request(self, image_request, ws):
		await self.send_captured_image(ws)

	async def handle_update_t_cur_enable(self, update_t_cur_enable):
		self.update_t_cur_enable = update_t_cur_enable.get('value', False)

	async def handle_led_time(self, LED_TIME):
		self.cam.config.LED_TIME = int(LED_TIME.get('value', self.cam.config.LED_TIME))
		self.cam.update_wave()

	async def handle_led_width(self, LED_WIDTH):
		self.cam.config.LED_WIDTH = int(LED_WIDTH.get('value', self.cam.config.LED_WIDTH))
		self.cam.update_wave()
	
	async def handle_http(self, request):
		script_dir = os.path.dirname(__file__)
		if request.path == '/':
			file_path = os.path.join(script_dir, 'combo.html')
		else:
			file_path = os.path.join(script_dir, request.path.lstrip('/'))
		return web.FileResponse(file_path)

class FrameRateMonitor:
	def __init__(self, period=5.0):
		self.period=period
		self.frame_count = 0
		self.start_time = time.time()

	def reset(self):
		self.frame_count = 0
		self.start_time = time.time()

	def increment(self):
		self.frame_count += 1

	def update(self):
		self.increment()
		if time.time() - self.start_time >= self.period:
			fps = self.frame_count / (time.time() - self.start_time)
			logging.info(f"Average FPS: {fps:.2f}")
			self.reset()

class CameraController:
	def __init__(self):
		# Initialize the configuration first
		self.config = TriggerConfig()
		self.config.TRIG_WIDTH = 10
		self.config.LED_WIDTH = 20
		self.config.WAVE_DURATION = 40000
		self.config.LED_TIME = 1000
		self.config.LED_MASK = 1 << self.config.RED_OUT  # | 1<<GRN_OUT | 1<<BLU_OUT

		self.dt = 8333 // 100
		self.t_min = 1000
		self.t_max = 8333 + self.t_min
		self.fps_logger = FrameRateMonitor(60)

		# Now initialize the rest of the components that depend on the config
		self.pig = start_pig()
		control_defaults = CameraControlDefaults()
		self.vidcap = ImageCapture(capture_raw=False, controls=control_defaults)
		self.vidcap.open()
		self.initialize_trigger()

	def initialize_trigger(self):
		self.script = trigger_wave_script(self.pig, self.config)
		self.wave = PiGPIOWave(self.pig, self.config)

		# Wait for the script to finish initializing before starting it
		while self.script.initing():
			pass
		self.script.start(self.wave.id)

	def __del__(self):
		self.shutdown()
  
	def shutdown(self):
		try:
			self.display.close()
		except Exception as e:
			logging.info(f"CameraController shutting down display: {e}")
		try:
			self.vidcap.close()
		except Exception as e:
			logging.info(f"CameraController shutting down vidcap: {e}")
		try:
			self.script.stop()
			self.script.delete()
		except Exception as e:
			logging.info(f"CameraController shutting down script: {e}")
		try:
			self.wave.delete()
		except Exception as e:
			logging.info(f"CameraController shutting down wave: {e}")

	def capture_frame(self, timeout=0):
		if timeout <= 0:
			self.fps_logger.update()
			return self.vidcap.capture_frame()
		else:
			result = [None]

			def target():
				result[0] = self.vidcap.capture_frame()

			thread = threading.Thread(target=target)
			thread.start()
			thread.join(timeout)
			if thread.is_alive():
				return None
			else:
				self.fps_logger.update()
				return result[0]

	def stop_wave(self):
		self.script.set_params(0xffffffff) # deactivate the current wave
		self.wave.delete()
  
	def set_delay(self, t_del):
		self.config.LED_TIME = t_del
		self.wave = PiGPIOWave(self.pig, self.config)
		self.script.set_params(self.wave.id)

	def update_wave(self):
		self.stop_wave()
		self.set_delay(self.config.LED_TIME)

	def set_cam_triggered(self):
		self.vidcap.control_set("exposure_auto_priority", 1)

	def set_cam_freerunning(self):
		self.vidcap.control_set("exposure_auto_priority", 0)

	def update_t_cur(self):
		self.config.LED_TIME += self.dt
		if self.config.LED_TIME > self.t_max:
			self.config.LED_TIME = self.t_min

	def main(self):
		self.set_cam_triggered()
		self.fps_logger.reset()
		while True:
			self.process_frame()
			self.update_t_cur()
			self.fps_logger.update()   

if __name__ == "__main__":
	try:
		fmt = "%(threadName)-10s %(asctime)-15s %(levelname)-5s %(name)s: %(message)s"
		logging.basicConfig(level="INFO", format=fmt)

		server = CameraServer()
		app = web.Application()
		app.router.add_get('/', server.handle_http)
		app.router.add_get('/ws', server.handle_message)
        # Attach the startup handler
		app.on_startup.append(server.on_startup)
		web.run_app(app, host='0.0.0.0', port=8000)
		# main_obj = CameraController()
		# main_obj.main()
	except KeyboardInterrupt:
		logging.info("Ctrl-C pressed. Bailing out")
	finally:
		server.cam.shutdown()
