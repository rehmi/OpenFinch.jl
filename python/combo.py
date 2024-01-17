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


class ImageCaptureServer:
	def __init__(self):
		self.brightness, self.contrast, self.gamma = (0.5, 0.5, 1.0)
		self.img_height, self.img_width = 1200, 1600
		self.vidcap = self.initialize_image_capture()

	def create_random_image(self, width=1600, height=1200):
		img = Image.fromarray(np.random.randint(0, 256, (height, width, 3), dtype=np.uint8))
		return img

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

	def generate_image(self, brightness, contrast, gamma, width=1600, height=1200):
		img = self.create_random_image(width, height)
		img = self.enhance_image(img, brightness, contrast, gamma)
		return img

	def initialize_image_capture(self, capture_raw=False):
		pi = pigpio.pi()
		pi.set_mode(17, pigpio.OUTPUT)
		pi.write(17, 0)
		cap = ImageCapture(capture_raw=capture_raw)
		cap.control_set("exposure_auto_priority", 0)
		cap.open()
		return cap

	async def send_random_image(self, ws, width=None, height=None):
		if width is None:
			width = self.img_width
		if height is None:
			height = self.img_height
		img = self.generate_image(self.brightness, self.contrast, self.gamma, height=height, width=width)
		img_bin = self.image_to_blob(img)
		await ws.send_str(json.dumps({'image_response': {'image': 'next'}}))
		await ws.send_bytes(img_bin)

	async def send_captured_image(self, ws, width=None, height=None):
		if width is None:
			width = self.img_width
		if height is None:
			height = self.img_height
		img = self.vidcap.capture_frame()
		img_bin = self.image_to_blob(img)
		await ws.send_str(json.dumps({'image_response': {'image': 'next'}}))
		await ws.send_bytes(img_bin)

	async def handle_message(self, request):
		ws = web.WebSocketResponse()
		await ws.prepare(request)

		async for msg in ws:
			if msg.type == web.WSMsgType.TEXT:
				data = json.loads(msg.data)

				if 'control_change' in data:
					control_change = data.get('control_change', {})
					self.brightness = float(control_change.get('brightness', image_request.get('brightness', self.brightness)))
					self.contrast = float(control_change.get('contrast', image_request.get('contrast', self.contrast)))
					self.gamma = float(control_change.get('gamma', image_request.get('gamma', self.gamma)))
				
				if 'image_request' in data:
					image_request = data.get('image_request', {})
					await self.send_captured_image(ws)
		return ws
	
	async def handle_http(self, request):
		script_dir = os.path.dirname(__file__)
		if request.path == '/':
			file_path = os.path.join(script_dir, 'vanilla.html')
		else:
			file_path = os.path.join(script_dir, request.path.lstrip('/'))
		return web.FileResponse(file_path)

def start_server():
	server = ImageCaptureServer()
	app = web.Application()
	app.router.add_get('/', server.handle_http)
	app.router.add_get('/ws', server.handle_message)
	web.run_app(app, host='0.0.0.0', port=8000)


class FPSLogger:
	def __init__(self):
		self.frame_count = 0
		self.start_time = time.time()

	def reset(self):
		self.frame_count = 0
		self.start_time = time.time()

	def increment(self):
		self.frame_count += 1

	def update(self):
		self.increment()
		if time.time() - self.start_time >= 3:
			fps = self.frame_count / (time.time() - self.start_time)
			logging.info(f"Average FPS: {fps:.2f}")
			self.reset()

class MainClass:
	def __init__(self):
		# Initialize the configuration first
		self.config = TriggerConfig()
		self.config.TRIG_WIDTH = 10
		self.config.LED_WIDTH = 20
		self.config.WAVE_DURATION = 40000
		self.config.LED_TIME = 1000
		self.config.LED_MASK = 1 << self.config.RED_OUT  # | 1<<GRN_OUT | 1<<BLU_OUT

		self.dt = 8333 // 1000
		self.t_min = 1000
		self.t_max = 8333 + self.t_min
		self.t_cur = self.t_min
		self.fps_logger = FPSLogger()

		# Now initialize the rest of the components that depend on the config
		self.pig = start_pig()
		control_defaults = CameraControlDefaults()
		self.vidcap = ImageCapture(capture_raw=False, controls=control_defaults)
		self.vidcap.open()

		# Initialize display and script/wave-related components
		self.display = Display()
		# XXX begin hack to ensure the display appears on monitor[0]
		self.display.move_to_monitor(0)
		self.display.update()
		self.display.move_to_monitor(0)
		self.display.update()
		# XXX end hack
		self.script = trigger_wave_script(self.pig, self.config)
		self.wave = PiGPIOWave(self.pig, self.config)

		# Wait for the script to finish initializing before starting it
		while self.script.initing():
			pass
		self.script.start(self.wave.id)

	def shutdown(self):
		try:
			self.display.close()
			self.vidcap.close()
			self.script.stop()
			self.script.delete()
			self.wave.delete()
		except Exception as e:
			logging.info(f"While shutting down: {e}")

	def capture_frame(self):
		return self.vidcap.capture_frame()

	def capture_frame_with_timeout(self, timeout=0.25):
		result = [None]

		def target():
			result[0] = self.vidcap.capture_frame()

		thread = threading.Thread(target=target)
		thread.start()
		thread.join(timeout)
		if thread.is_alive():
			return None
		else:
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
		self.set_delay(self.t_cur)

	def update_display(self, img):
		self.display.set_image(img)
		self.display.display_image()
		self.display.update()

	def process_frame(self):
		try:
			img = self.capture_frame_with_timeout()
			if img is not None:
				self.update_wave()
				self.update_display(img)
			else:
				logging.info("capture_frame timed out!")
		except Exception as e:
			logging.info(f"EXCEPTION: {e}")


	def main(self):
		self.vidcap.control_set("exposure_auto_priority", 1)
		self.fps_logger.reset()
		while True:
			if self.t_cur > self.t_max:
				self.t_cur = self.t_min

			self.process_frame()
			self.fps_logger.update()
   
			self.t_cur += self.dt


if __name__ == "__main__":
	# start_server()
	try:
		fmt = "%(threadName)-10s %(asctime)-15s %(levelname)-5s %(name)s: %(message)s"
		logging.basicConfig(level="INFO", format=fmt)
		main_obj = MainClass()
		main_obj.main()
	except KeyboardInterrupt:
		logging.info("Ctrl-C pressed. Bailing out")
	finally:
		main_obj.shutdown()
