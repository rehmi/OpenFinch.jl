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
import base64

from utils.display import Display
from camera.controllers.system import SystemController
from camera.captures.abstract import AbstractCameraController
from camera.captures.picamera2 import Picamera2Controller
from camera.captures.v4l2 import V4L2CameraController
from camera.utils.utils import BoundedQueue
from camera.utils.utils import BooleanControl, IntegerControl, FloatControl, MenuControl

class CameraServer:
    def __init__(self):
        self.camctrl = Picamera2Controller(device_id=0, controls={})
        self.sysctrl = SystemController(camera_controller=self.camctrl)
        self.sysctrl.set_cam_triggered()
        self.control_descriptors = self.generate_control_descriptors(self.camctrl.get_control_descriptors())
        
        self.persistent_metadata = {
            'frame_number': 0,
        }

        self.active_connections = {}
        self.message_queues = defaultdict(lambda: BoundedQueue(3))
        self.sweep_enable = False
        self.monitor_index = 1
        self.jpeg_quality = 75

        self.handlers = {
            'sweep_enable':
                lambda data: self.handle_sweep_enable(data),
            # XXX need to rethink this, or at least also pass ws as well; maybe use *args instead of data?
            'update_controls': lambda data: self.handle_update_controls(data),
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
            'colour_gain_red': lambda data: self.handle_dummy('colour_gain_red', data),
            'colour_gain_blue': lambda data: self.handle_dummy('colour_gain_blue', data),
            # XXX what was this unfinished thought?
            # 'ColourGains': lambda data: self.handle_colour_gain(data),
        }

        try:
            self.initialize_display()
        except Exception as e:
            logging.exception("CameraServer trying to initialize_display")
            pass

    async def handle_dummy(self, name, data):
        logging.info(f"handle_dummy({name}, {data})")

    def shutdown(self):
        # self.camctrl.shutdown()
        self.sysctrl.shutdown()

    async def set_control(self, control_name, control_value):
        if control_name in self.handlers:
            await self.handlers[control_name]({'value': control_value})
        else:
            await self.handle_camera_control(control_name, {'value': control_value})

    def set_color_gains(self, red_gain, blue_gain):
        """
        Sets the color gains for the camera.

        Parameters:
        - red_gain (float): The gain value for the red channel.
        - blue_gain (float): The gain value for the blue channel.
        """
        # Ensure the gains are within the allowed range as defined in IMX296.py
        # For simplicity, let's assume the range is (0.0, 32.0) for both gains.
        # You might want to fetch the actual range from the camera controls if it varies.
        red_gain = max(0.0, min(32.0, red_gain))
        blue_gain = max(0.0, min(32.0, blue_gain))

        # Set the ColourGains control
        try:
            self.camctrl.set_controls({"ColourGains": (red_gain, blue_gain)})
            logging.info(f"Color gains set to red: {red_gain}, blue: {blue_gain}")
        except Exception as e:
            logging.error(f"Failed to set color gains: {e}")

    async def handle_ws(self, request):
        ws = web.WebSocketResponse(max_msg_size=32*1024*1024)
        # self.active_connections.add(ws)
        await ws.prepare(request)
        # Initialize preferences with stream_frames set to True
        self.active_connections[ws] = {'stream_frames': True}
        logging.debug(f"WebSocket connection established: {ws}")

        # Start the active_connection_wrapper task for this connection
        asyncio.create_task(self.active_connection_wrapper(ws))
        
        # start a handler loop that persists as long as the websocket
        try:
            async for msg in ws:
                if msg.type == web.WSMsgType.TEXT:
                    data = json.loads(msg.data)
                    logging.debug(f"Received message: {data}")  # Log the received message
                    try:
                        if 'set_control' in data:
                            for control_name, control_value in data['set_control'].items():
                                if control_name == 'slm_image_url':
                                    await self.handle_display_image_url(control_value)
                                else:
                                    await self.set_control(control_name, control_value)
                        
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
                            await self.handle_display_image_url(data['slm_image_url'])

                        if 'slm_image' in data:
                            encoded_image = data['slm_image']
                            logging.info(f"SLM_image received {len(encoded_image)} bytes")

                            if encoded_image == 'next':
                                image_blob = await ws.receive_bytes()
                                img = Image.open(BytesIO(image_blob))
                                # self.display.move_to_monitor(self.monitor_index)
                            else:
                                # Decode the base64 image and display it
                                image_bytes = base64.b64decode(encoded_image)
                                img = Image.open(BytesIO(image_bytes))
                            
                            logging.info(f"img has type {type(img)} and size {img.size}")
                            self.display.display_image(img)

                    except Exception as e:
                        logging.exception("CameraServer.handle_ws")
                else:
                    # logging.debug(f"Received non-text message of type {msg.type}: {msg.data[:100]} [{len(msg.data)} bytes total]")
                    logging.debug(f"Received non-text message {msg}")

        except Exception as e:
            logging.exception("Error handling WebSocket message")
        finally:
            # the websocket has closed or an error occurred.
            logging.debug(f"WebSocket connection closed: {ws}")
            await self.cleanup_connection(ws)                   
            # self.active_connections.remove(ws)
            if ws in self.active_connections:
                del self.active_connections[ws]
    
    async def cleanup_connection(self, ws):
        if ws in self.active_connections:
            del self.active_connections[ws]
        # Perform additional cleanup if necessary
        logging.info(f"Cleaned up websocket connection")
    
    async def send_str_and_bytes(self, ws, str_data, bytes_data):
        await self.message_queues[ws].put((str_data, bytes_data))

    async def send_str(self, ws, str_data):
        try:
            if ws.closed:
                logging.warning(f"Attempt to send data to closed connection {ws}")
                await self.cleanup_connection(ws)
            else:
                await ws.send_str(str_data)
        except Exception as e:
            logging.exception(f"Failed to send data to {ws}")
            await self.cleanup_connection(ws)
    
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
            pass
            # logging.exception(f"active_connection_wrapper: error on WebSocket")
        finally:
            # Attempt to gracefully close the connection
            try:
                logging.info("Waiting for remaining messages to be sent before closing websocket.")
                # Wait for any remaining messages to be sent
                while not self.message_queues[ws].empty():
                    messages = await self.message_queues[ws].get()
                    for message in messages:
                        if isinstance(message, str):
                            await ws.send_str(message)
                        else:
                            await ws.send_bytes(message)
                # Close the WebSocket connection
                logging.info("Remaining messages have been sent, closing websocket")
                await ws.close()
                logging.info("WebSocket connection closed gracefully.")
            except Exception as e:
                logging.exception("Error while trying to gracefully close WebSocket connection.")
            finally:
                # Clean up the connection and message queue
                if ws in self.active_connections:
                    del self.active_connections[ws]
                if ws in self.message_queues:
                    del self.message_queues[ws]

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

    async def handle_update_controls(self, data):
        # Collect the current control values
        control_values = {control.name: self._get_control(control.name) for control in self.camctrl.get_control_descriptors().values()}
        # Send the control values to the client
        await self.broadcast_to_active_connections(self.send_str, json.dumps({'update_controls': control_values}))

    def generate_control_descriptors(self, controls):
        descriptors = []
        for control in controls.values():
            if control.name == 'ColourGains':
                # Split ColourGains into two separate controls for red and blue gains
                for color in ['red', 'blue']:
                    descriptor = {
                        'id': control.id,
                        'type': control.__class__.__name__,
                        'name': f'colour_gain_{color}',
                        'range': control.range,
                        'default': control.default,
                        'value': control.value,
                        'step': 0.1,  # Assuming a step value for the slider
                    }
                    descriptors.append(descriptor)
            else:
                descriptor = {
                    'id': control.id,
                    'type': control.__class__.__name__,
                    'name': control.name,
                    'range': control.range,
                    'default': control.default,
                    'value': control.value,
                    'step': control.step if hasattr(control, 'step') else (0.1 if isinstance(control, FloatControl) else None),
                    'options': control.options if isinstance(control, MenuControl) else None
                }
                descriptors.append(descriptor)
        return descriptors

    async def handle_controls_endpoint(self, request):
        # control_descriptors = self.generate_control_descriptors(self.camctrl.get_control_descriptors())
        return web.json_response(self.control_descriptors)

    def initialize_display(self):
        # Initialize display and script/wave-related components
        self.display = Display()

    def update_display(self, img):
        img_array = np.array(img)
        self.display.display_image(img_array)

    async def handle_display_image_url(self, image_url):
        try:
            response = requests.get(image_url)
            response.raise_for_status()
            image_bytes = response.content
            img = Image.open(BytesIO(image_bytes))
            self.display.display_image(img)
            # self.display.switch_to_fullscreen()
            # self.display.move_to_monitor(1)
            # self.update_display(img)
        except requests.exceptions.HTTPError as err:
            logging.exception(f"Error retrieving image")

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
        frame = self.sysctrl.capture_frame()
        if frame is not None:
            # Perform a camera sweep and update LED timing if the sweep is enabled, then update the wave.
            # XXX This should be factored out of send_captured_image()
            if self.sweep_enable:
                self.sysctrl.sweep()
                await self.update_led_time(self.sysctrl.config.LED_TIME)
            self.sysctrl.update_wave()
            # XXX end section to be factored out

            img_bin = frame.to_bytes()
            current_frame_metadata = frame.metadata

            # Update the frame number and any other relevant fields
            self.persistent_metadata['frame_number'] += 1

            # Merge or update other fields from the current frame metadata into the persistent metadata
            for key, value in current_frame_metadata.items():
                self.persistent_metadata[key] = value
            
            # Loop through each connection and check if stream_frames is True
            for ws, prefs in self.active_connections.items():
                if prefs.get('stream_frames', True):
                    if prefs.get('use_base64_encoding', False):
                        # Convert the image to base64
                        img_base64 = base64.b64encode(img_bin).decode('utf-8')
                        # Send the base64 encoded image
                        await self.send_str(ws, json.dumps({
                            'image_response': {
                                'image': 'here',
                                'metadata': self.persistent_metadata,
                                'image_base64': img_base64}}))
                    else:
                        # Send the 'next' message followed by the image blob
                        await self.send_str_and_bytes(ws, json.dumps({
                            'image_response': {
                                'image': 'next',
                                'metadata': self.persistent_metadata
                            }}), img_bin)

    async def update_led_time(self, new_value):
        await self.broadcast_to_active_connections(self.send_str, json.dumps({'LED_TIME': {'value': new_value}}))

    async def update_control_value(self, control_name, new_value):
        await self.broadcast_to_active_connections(self.send_str, json.dumps({control_name: {'value': new_value}}))

    async def send_fps_update(self):
        current_time = time.time()  # Get the current time
        if hasattr(self, 'last_fps_update_time') and current_time - self.last_fps_update_time < 1:
            # If less than 1 second has passed since the last update, do not send another update
            return
        try:
            fps_data = {
                'image_capture_reader_fps': self.sysctrl.get_reader_fps(),
                'image_capture_capture_fps': self.sysctrl.get_capture_fps(),
                'system_controller_fps': self.sysctrl.get_controller_fps()
            }
            await self.broadcast_to_active_connections(
                self.send_str, json.dumps({'fps_update': fps_data})
            )
            self.last_fps_update_time = current_time  # Update the last FPS update time
        except Exception as e:
            logging.exception("Exception in send_fps_update")

    async def handle_stream_frames(self, ws, preference_data):
        self.active_connections[ws]['stream_frames'] = preference_data.get('value', True)

    async def handle_use_base64_encoding(self, ws, preference_data):
        self.active_connections[ws]['use_base64_encoding'] = preference_data.get('value', True)

    async def handle_camera_control(self, control_name, control_data):
        # Look up the control descriptor by name
        control_descriptor = next((cd for cd in self.control_descriptors if cd['name'] == control_name), None)
        logging.debug(f"CameraServer.handle_camera_control({control_name}, {control_data})")
        value = control_data.get('value', 0)
        return self._set_control(control_name, value)

    def _set_control(self, control_name, value):
        control_method = getattr(self.sysctrl.vidcap, f"set_control")
        return control_method(control_name, value)
    
    def _get_control(self, control_name):
        control_method = getattr(self.sysctrl.vidcap, f"get_control")
        return control_method(control_name)
    
    async def handle_config_control(self, control_name, control_data):
        value = int(control_data.get('value', 0))
        if control_name in ['LED_TIME', 'LED_WIDTH', 'WAVE_DURATION']:
            setattr(self.sysctrl.config, control_name, value)
            self.sysctrl.update_wave()

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
            self.sysctrl.set_cam_freerunning()
        else:
            self.sysctrl.set_cam_triggered()

    async def handle_capture_mode(self, capture_mode):
        mode = capture_mode.get('value', 'preview')
        self.sysctrl.set_capture_mode(mode)
        logging.debug(f"Camera mode set to {mode}")

    async def handle_http(self, request):
        script_dir = os.path.dirname(__file__)
        if request.path == '/':
            file_path = os.path.join(script_dir, 'static/dashboard.html')
        else:
            file_path = os.path.join(script_dir, request.path.lstrip('/'))
        return web.FileResponse(file_path)
