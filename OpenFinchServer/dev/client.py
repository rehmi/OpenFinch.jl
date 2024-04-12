import asyncio
import websockets
import json
import requests
from PIL import Image
from io import BytesIO

class OpenFinchClient:
    def __init__(self, uri):
        self.uri = uri
        self.websocket = None

    async def connect(self):
        self.websocket = await websockets.connect(self.uri)

    async def close(self):
        await self.websocket.close()

    async def send_control_command(self, command, value):
        message = json.dumps({command: {'value': value}})
        await self.websocket.send(message)

    async def set_capture_mode(self, mode):
        mode_value = 'triggered' if mode else 'freerunning'
        await self.send_control_command('capture_mode', mode_value)

    async def send_image_request(self, brightness='1.0', contrast='1.0', gamma='1.0'):
        request = json.dumps({'image_request': {
            'brightness': brightness,
            'contrast': contrast,
            'gamma': gamma
        }})
        await self.websocket.send(request)
        response = await self.websocket.recv()
        img = await self.receive_image()
        return img

    async def send_image_update(self, img_url_or_file):
        if img_url_or_file.startswith('http://') or img_url_or_file.startswith('https://'):
            response = requests.get(img_url_or_file)
            img_byte_arr = response.content
        else:
            with Image.open(img_url_or_file) as img:
                img_byte_arr = BytesIO()
                img.save(img_byte_arr, format='PNG')
                img_byte_arr = img_byte_arr.getvalue()

        await self.websocket.send(json.dumps({'SLM_image': 'next'}))
        await self.websocket.send(img_byte_arr)

    async def receive_image(self):
        ''' Triggers the reception of an image and returns it. '''
        response = await self.websocket.recv()
        if isinstance(response, (str, bytes)):  # Check if received data is BLOB/bytes
            image_data = BytesIO(response)
            image = Image.open(image_data)
            return image

    async def update_fps(self, callback):
        while True:
            try:
                fps_data = await self.websocket.recv()
                fps_info = json.loads(fps_data)
                callback(fps_info)  # Pass the data to a provided callback function
            except websockets.ConnectionClosed:
                break

# Example usage:
async def main():
    client = OpenFinchClient("ws://finch.local:8000/ws")
    await client.connect()

    # # Set camera to triggered mode
    # await client.set_capture_mode(True)

    # # Set LED time
    # await client.send_control_command('LED_TIME', 1000)

    # Request an image
    image_response = await client.send_image_request()
    print(image_response)

    # Use a callback to process FPS information
    # def print_fps_info(info):
        # print(info)

    # Start receiving FPS updates
    # await client.update_fps(print_fps_info)

    # Close the connection after use
    await client.close()

# Run the asyncio main loop
asyncio.run(main())
