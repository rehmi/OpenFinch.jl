import time
import logging
import asyncio
import json
from PIL import Image, ImageEnhance, ImageOps
import numpy as np
from io import BytesIO
from aiohttp import web
import os
import requests
from collections import defaultdict
from asyncio import Queue
import base64

from .display import Display
from .system_controller import SystemController
from .abstract_camera import AbstractCameraController
from ._picamera2 import Picamera2Controller
from ._v4l2 import V4L2CameraController
from .controls import picamera2_controls, IntegerControl, MenuControl

class BoundedQueue(asyncio.Queue):
    def __init__(self, maxsize):
        super().__init__(maxsize)

    async def put(self, item):
        if self.full():
            # Drop the oldest item from the queue
            await self.get()
        await super().put(item)

class CameraServer:
    def __init__(self):
        self.pcam = Picamera2Controller(device_id=0, controls={})
        self.cam = SystemController(camera_controller=self.pcam)
        self.cam.set_cam_triggered()
        self.active_connections = {}
        self.message_queues = defaultdict(lambda: BoundedQueue(3))
        self.sweep_enable = False
        self.monitor_index = 1
        self.jpeg_quality = 75

        self.handlers = {
            'sweep_enable':
                lambda data: self.handle_sweep_enable(data),
            # XXX need to rethink this, or at least also pass ws as well; maybe use *args instead of data?
            # 'stream_frames':
                # lambda data: self.handle_stream_frames(ws, data),
            'capture_mode': lambda data: self.handle_capture_mode(data),
            'JPEG_QUALITY': lambda data: self.handle_jpeg_quality(data),
            'capture_mode': lambda data: self.handle_capture_mode(data),

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

        try:
            self.initialize_display()
        except Exception as e:
            logging.exception("CameraServer trying to initialize_display")
            pass

    async def handle_ws(self, request):
        ws = web.WebSocketResponse()
        # self.active_connections.add(ws)
        await ws.prepare(request)
        # Initialize preferences with stream_frames set to True
        self.active_connections[ws] = {'stream_frames': True}
        logging.debug(f"WebSocket connection established: {ws}")

        # Start the active_connection_wrapper task for this connection
        asyncio.create_task(self.active_connection_wrapper(ws))
        
        # start a handler loop that persists as long as the websocket
        async for msg in ws:
            if msg.type == web.WSMsgType.TEXT:
                data = json.loads(msg.data)
                logging.debug(f"Received message: {data}")  # Log the received message
                try:
                    if 'set_control' in data:
                        for control_name, control_value in data['set_control'].items():
                            if control_name in self.handlers:
                                await self.handlers[control_name]({'value': control_value})
                            else:
                                await self.handle_camera_control(control_name, {'value': control_value})
                    
                    for key, handler in self.handlers.items():
                        if key in data:
                            await handler(data[key])

                    if 'stream_frames' in data:
                        await self.handle_stream_frames(ws, data['stream_frames'])
                        
                    if 'use_base64_encoding' in data:
                        await self.handle_use_base64_encoding(ws, data['use_base64_encoding'])

                    if 'image_request' in data:
                        await self.handle_image_request(data, ws)

                    # Check for the slm_image_url command
                    if 'slm_image_url' in data:
                        await self.handle_display_full_screen(data['slm_image_url'])
                        
                    if data.get('SLM_image', '') == 'next':
                        image_blob = await ws.receive_bytes()
                        # logging.debug(f"SLM_image received {len(image_blob)} bytes")
                        img = Image.open(BytesIO(image_blob))
                        # logging.debug(f"img has type {type(img)} and size {img.size}")
                        self.display.move_to_monitor(self.monitor_index)
                        self.update_display(img)
                except Exception as e:
                    logging.exception("CameraServer.handle_ws")
        
        # the websocket has closed or an error occurred.
        logging.debug(f"WebSocket connection closed: {ws}")
        # self.active_connections.remove(ws)
        if ws in self.active_connections:
            del self.active_connections[ws]

    async def send_str_and_bytes(self, ws, str_data, bytes_data):
        await self.message_queues[ws].put((str_data, bytes_data))

    async def send_str(self, ws, str_data):
        await self.message_queues[ws].put((str_data,))

    async def active_connection_wrapper(self, ws):
        try:
            while True:
                messages = await self.message_queues[ws].get()
                for message in messages:
                    if isinstance(message, str):
                        await ws.send_str(message)
                    else:
                        await ws.send_bytes(message)
        except Exception as e:
            logging.info(f"active_connection_wrapper: error occurred on WebSocket {ws}: {e}")
            try:
                if ws in self.active_connections:
                    del self.active_connections[ws]
                del self.message_queues[ws]
            except KeyError:
                pass

    async def broadcast_to_active_connections(self, func, *args):	
        tasks = [
            func(ws, *args) for ws in list(self.active_connections) # Create a copy of the set to avoid modifying it while iterating
        ]
        await asyncio.gather(*tasks)

    async def on_startup(self, app):
        app.router.add_get('/controls', self.handle_controls_endpoint)
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

    def initialize_display(self):
        # Initialize display and script/wave-related components
        self.display = Display()
        # XXX begin hack to ensure the display appears on monitor[0]
        self.display.create_window()
        self.display.move_to_monitor(0)
        self.display.update()
        self.display.move_to_monitor(0)
        self.display.update()
        # self.display.hide_window()
        self.display.update()
        # XXX end hack

    def update_display(self, img):
        img_array = np.array(img)
        self.display.display_image(img_array)
        self.display.update()

    async def handle_display_full_screen(self, image_url):
        # You would have logic here to load the image from the given URL
        # and then call the Display class method to show it full screen.
        # Example (you might need to tailor this to your Display class methods):
        try:
            response = requests.get(image_url)
            response.raise_for_status()
            image_bytes = response.content
            img = Image.open(BytesIO(image_bytes))
            self.display.switch_to_fullscreen()
            self.display.move_to_monitor(1)
            self.update_display(img)
        except requests.exceptions.HTTPError as err:
            logging.exception(f"Error retrieving image: {err}")

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

            # Loop through each connection and check if stream_frames is True
            for ws, prefs in self.active_connections.items():
                if prefs.get('stream_frames', True):
                    if prefs.get('use_base64_encoding', False):
                        # Convert the image to base64
                        img_base64 = base64.b64encode(img_bin).decode('utf-8')
                        # Send the base64 encoded image
                        await self.send_str(ws, json.dumps({'image_response': {'image': 'here', 'base64_image': img_base64}}))
                    else:
                        # Send the 'next' message followed by the image blob
                        await self.send_str_and_bytes(ws, json.dumps({'image_response': {'image': 'next'}}), img_bin)

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

    async def handle_stream_frames(self, ws, preference_data):
        self.active_connections[ws]['stream_frames'] = preference_data.get('value', True)

    async def handle_use_base64_encoding(self, ws, preference_data):
        self.active_connections[ws]['use_base64_encoding'] = preference_data.get('value', True)

    async def handle_camera_control(self, control_name, control_data):
        value = int(control_data.get('value', 0))
        control_method = getattr(self.cam.vidcap, f"set_control")
        control_method(control_name, value)
    
    async def handle_config_control(self, control_name, control_data):
        value = int(control_data.get('value', 0))
        if control_name in ['LED_TIME', 'LED_WIDTH', 'WAVE_DURATION']:
            setattr(self.cam.config, control_name, value)
            self.cam.update_wave()

    async def handle_image_request(self, image_request, ws):
        # XXX this used to work but now that send_captured_image()
        # broadcasts to all connections we need to refactor it
        # await self.send_captured_image(ws)
        logging.debug(f"CameraServer.handle_image_request() was called")
        return
    
    async def handle_sweep_enable(self, sweep_enable):
        self.sweep_enable = sweep_enable.get('value', False)

    async def handle_jpeg_quality(self, jpeg_quality):
        self.jpeg_quality = int(jpeg_quality.get('value', 10))
        
    async def handle_capture_mode(self, capture_mode):
        if capture_mode['value'] == 'freerunning':
            self.cam.set_cam_freerunning()
        else:
            self.cam.set_cam_triggered()

    async def handle_capture_mode(self, capture_mode):
        mode = capture_mode.get('value', 'preview')
        self.cam.set_capture_mode(mode)
        logging.debug(f"Camera mode set to {mode}")

    def generate_control_descriptors(self, controls):
        descriptors = []
        for control in controls.values():
            descriptor = {
                'id': control.id,
                'type': control.type,
                'name': control.name,
                'range': control.range,
                'default': control.default,
                'value': control.value,
                'step': control.step if isinstance(control, IntegerControl) else None,
                'options': control.options if isinstance(control, MenuControl) else None
            }
            descriptors.append(descriptor)
        return descriptors

    async def handle_controls_endpoint(self, request):
        control_descriptors = self.generate_control_descriptors(picamera2_controls)
        return web.json_response(control_descriptors)

    async def handle_http(self, request):
        script_dir = os.path.dirname(__file__)
        if request.path == '/':
            file_path = os.path.join(script_dir, 'dashboard.html')
        else:
            file_path = os.path.join(script_dir, request.path.lstrip('/'))
        return web.FileResponse(file_path)
