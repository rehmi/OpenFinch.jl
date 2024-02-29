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
from ImageCapture import ImageCapture

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
        cap.set_control("exposure_auto_priority", 0)
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
                control_change = data.get('control_change', {})
                image_request = data.get('image_request', {})

                self.brightness = float(control_change.get('brightness', image_request.get('brightness', self.brightness)))
                self.contrast = float(control_change.get('contrast', image_request.get('contrast', self.contrast)))
                self.gamma = float(control_change.get('gamma', image_request.get('gamma', self.gamma)))

                await self.send_captured_image(ws)
        return ws

    async def handle_http(self, request):
        script_dir = os.path.dirname(__file__)
        if request.path == '/':
            file_path = os.path.join(script_dir, 'vanilla.html')
        else:
            file_path = os.path.join(script_dir, request.path.lstrip('/'))
        return web.FileResponse(file_path)


if __name__ == '__main__':
    server = ImageCaptureServer()

    app = web.Application()
    app.router.add_get('/', server.handle_http)
    app.router.add_get('/ws', server.handle_message)
    web.run_app(app, host='0.0.0.0', port=8000)