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

class MessageHandler:
    def __init__(self, camera_server):
        self.camera_server = camera_server
        self.handlers = {
            'sweep_enable': self.handle_sweep_enable,
            'update_controls': self.handle_update_controls,
            'capture_mode': self.handle_capture_mode,
            'JPEG_QUALITY': self.handle_jpeg_quality,
            'LED_TIME': lambda data, ws: self.handle_config_control('LED_TIME', data, ws),
            'LED_WIDTH': lambda data, ws: self.handle_config_control('LED_WIDTH', data, ws),
            'WAVE_DURATION': lambda data, ws: self.handle_config_control('WAVE_DURATION', data, ws),
            'ILLUMINATION_MODE': lambda data, ws: self.handle_illumination_mode(data, ws),
            'exposure_absolute': self.handle_camera_control,
            'brightness': self.handle_camera_control,
            'contrast': self.handle_camera_control,
            'saturation': self.handle_camera_control,
            'hue': self.handle_camera_control,
            'gamma': self.handle_camera_control,
            'gain': self.handle_camera_control,
            'power_line_frequency': self.handle_camera_control,
            'sharpness': self.handle_camera_control,
            'backlight_compensation': self.handle_camera_control,
            'exposure_auto': self.handle_camera_control,
            'exposure_auto_priority': self.handle_camera_control,
            'colour_gain_red': self.handle_dummy,
            'colour_gain_blue': self.handle_dummy,
            'send_fps_updates': self.handle_fps_updates,
            'stream_frames': self.handle_stream_frames,
            'use_base64_encoding': self.handle_use_base64_encoding,
            'image_request': self.handle_image_request,
            'slm_image_url': self.handle_display_image_url,
            'slm_image': self.handle_slm_image,
        }

    async def parse_message(self, data, ws):
        try:
            if 'set_control' in data:
                for control_name, control_value in data['set_control'].items():
                    await self.set_control(control_name, control_value, ws)

            for key, value in data.items():
                if key in self.handlers:
                    await self.handlers[key](value, ws)

        except Exception as e:
            logging.exception("MessageHandler.parse_message")

    async def set_control(self, control_name, control_value, ws):
        if control_name in self.handlers:
            await self.handlers[control_name]({'value': control_value}, ws)
        else:
            await self.handle_camera_control(control_name, control_value)
            
    async def handle_camera_control(self, control_name, data):
        if isinstance(data, dict):
            value = data.get('value', 0)
        else:
            value = data
        await self.camera_server._set_control(control_name, value)

    async def handle_sweep_enable(self, data, ws):
        self.camera_server.sweep_enable = data.get('value', False)

    async def handle_update_controls(self, data, ws):
        control_values = {control.name: self.camera_server._get_control(control.name) for control in self.camera_server.camctrl.get_control_descriptors().values()}
        await self.camera_server.broadcast_to_active_connections(self.camera_server.send_str, json.dumps({'update_controls': control_values}))

    async def handle_capture_mode(self, data, ws):
        mode = data.get('value', 'preview')
        self.camera_server.sysctrl.set_capture_mode(mode)
        logging.debug(f"Camera mode set to {mode}")

    async def handle_jpeg_quality(self, data, ws):
        self.camera_server.jpeg_quality = int(data.get('value', 10))

    async def handle_config_control(self, control_name, data, ws):
        logging.debug(f"handle_config_control({control_name}, {data}")
        value = int(data.get('value', 0))
        if control_name in ['LED_TIME', 'LED_WIDTH', 'WAVE_DURATION']:
            setattr(self.camera_server.sysctrl.config, control_name, value)
            self.camera_server.sysctrl.update_wave()

    async def handle_dummy(self, data, ws):
        logging.info(f"handle_dummy({data})")

    async def handle_fps_updates(self, data, ws):
        self.camera_server.active_connections[ws]['send_fps_updates'] = data.get('value', False)
        logging.info(f"FPS updates {'enabled' if self.camera_server.active_connections[ws]['send_fps_updates'] else 'disabled'} for {ws}")

    async def handle_stream_frames(self, data, ws):
        self.camera_server.active_connections[ws]['stream_frames'] = data.get('value', True)
        logging.info(f"Frame streaming {'enabled' if self.camera_server.active_connections[ws]['stream_frames'] else 'disabled'} for {ws}")

    async def handle_use_base64_encoding(self, data, ws):
        self.camera_server.active_connections[ws]['use_base64_encoding'] = data.get('value', True)
        logging.info(f"base64 encoding {'enabled' if self.camera_server.active_connections[ws]['use_base64_encoding'] else 'disabled'} for {ws}")

    async def handle_image_request(self, data, ws):
        logging.debug(f"CameraServer.handle_image_request() was called")
        return

    async def handle_display_image_url(self, data, ws):
        try:
            response = requests.get(data)
            response.raise_for_status()
            image_bytes = response.content
            img = Image.open(BytesIO(image_bytes))
            self.camera_server.display.display_image(img)
        except requests.exceptions.HTTPError as err:
            logging.exception(f"Error retrieving image")

    async def handle_slm_image(self, data, ws):
        encoded_image = data
        logging.info(f"SLM_image received {len(encoded_image)} bytes")

        if encoded_image == 'next':
            image_blob = await ws.receive_bytes()
            img = Image.open(BytesIO(image_blob))
        else:
            # Decode the base64 image and display it
            image_bytes = base64.b64decode(encoded_image)
            img = Image.open(BytesIO(image_bytes))
        
        logging.info(f"img has type {type(img)} and size {img.size}")
        self.camera_server.display.display_image(img)

    async def handle_illumination_mode(self, data, ws):
        mode = data.get('value', '777')  # Default to '777' (all LEDs on for all fields)
        
        # Validate the octal string (should be 3 digits, 0-7)
        if len(mode) == 3 and all(c in '01234567' for c in mode): 
            self.camera_server.sysctrl.config.ILLUMINATION_MODE = mode
            self.camera_server.sysctrl.update_wave()
            logging.info(f"Illumination mode set to {mode}")
        else:
            logging.warning(f"Invalid illumination mode requested: {mode}. Using default '421'.")
            self.camera_server.sysctrl.config.ILLUMINATION_MODE = '421'
            self.camera_server.sysctrl.update_wave()

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

        self.message_handler = MessageHandler(self) # Initialize the message handler

        try:
            self.initialize_display()
        except Exception as e:
            logging.exception("CameraServer trying to initialize_display")
            pass

    def shutdown(self):
        # self.camctrl.shutdown()
        self.sysctrl.shutdown()

    async def handle_ws(self, request):
        ws = web.WebSocketResponse(max_msg_size=32*1024*1024)
        await ws.prepare(request)
        self.active_connections[ws] = {
            'stream_frames': False,
            "use_base64_encoding" : False,
            'send_fps_updates': False
        }
        logging.debug(f"WebSocket connection established: {ws}")

        asyncio.create_task(self.active_connection_wrapper(ws))
        
        try:
            async for msg in ws:
                if msg.type == web.WSMsgType.TEXT:
                    data = json.loads(msg.data)
                    await self.message_handler.parse_message(data, ws) # Use the message handler to parse the message
                else:
                    logging.debug(f"Received non-text message {msg}")

        except Exception as e:
            logging.exception("Error handling WebSocket message")
        finally:
            logging.debug(f"WebSocket connection closed: {ws}")
            await self.cleanup_connection(ws)                   
            if ws in self.active_connections:
                del self.active_connections[ws]
                
    async def cleanup_connection(self, ws):
        if ws in self.active_connections:
            del self.active_connections[ws]
        # Perform additional cleanup if necessary
        logging.info(f"Cleaned up websocket connection")
    
    async def active_connection_wrapper(self, ws):
        try:
            while not ws.closed:
                messages = await self.message_queues[ws].get()
                if not messages:
                    logging.debug("No messages to send. Continuing.")
                    continue

                await self.send_messages(ws, messages)

        except Exception as e:
            logging.exception(f"An unexpected error occurred outside the message sending loop: {e}")
        finally:
            await self.cleanup_connection(ws)
            logging.info("Connection cleanup completed.")
            await self.gracefully_close_connection(ws)

    async def send_messages(self, ws, messages):
        send_tasks = [asyncio.create_task(self.send_message(ws, message)) for message in messages]
        for task in asyncio.as_completed(send_tasks, timeout=10):
            try:
                await task
            except asyncio.TimeoutError:
                logging.error("Timeout while sending message.")
            except ConnectionResetError:
                logging.error("Connection reset. Unable to send message.")
                break  # Exit the loop if the connection is reset
            except Exception as e:
                logging.exception(f"Unexpected error while sending message: {e}")

    async def send_message(self, ws, message):
        if isinstance(message, str):
            await ws.send_str(message)
        else:
            await ws.send_bytes(message)

    async def gracefully_close_connection(self, ws):
        try:
            logging.info("Waiting for remaining messages to be sent before closing websocket.")
            # Wait for any remaining messages to be sent
            while not self.message_queues[ws].empty():
                messages = await self.message_queues[ws].get()
                await self.send_messages(ws, messages)

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
            # Create a copy of the set to avoid modifying it while iterating
            func(ws, *args) for ws in list(self.active_connections) 
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
                # raise e

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
            for ws, prefs in self.active_connections.copy().items():
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
        self.last_fps_update_time = current_time  # Update the last FPS update time
        try:
            fps_data = {
                'image_capture_reader_fps': self.sysctrl.get_reader_fps(),
                'image_capture_capture_fps': self.sysctrl.get_capture_fps(),
                'system_controller_fps': self.sysctrl.get_controller_fps()
            }
            # await self.broadcast_to_active_connections(
            #     self.send_str, json.dumps({'fps_update': fps_data})
            # )
            for ws in list(self.active_connections):
                if self.active_connections[ws].get('send_fps_updates', False):
                    await ws.send_str(json.dumps({'fps_update': fps_data}))
        except Exception as e:
            logging.exception("Exception in send_fps_update")

    async def _set_control(self, control_name, value):
        control_method = getattr(self.sysctrl.vidcap, f"set_control")
        return control_method(control_name, value)
    
    async def _get_control(self, control_name):
        control_method = getattr(self.sysctrl.vidcap, f"get_control")
        return control_method(control_name)
    
    async def handle_http(self, request):
        script_dir = os.path.dirname(__file__)
        if request.path == '/':
            file_path = os.path.join(script_dir, 'static/dashboard.html')
        else:
            file_path = os.path.join(script_dir, request.path.lstrip('/'))
        return web.FileResponse(file_path)

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
