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

	async def listen(self):
		''' Continuously listen for messages from the server and print them. '''
		while True:
			try:
				message = await self.websocket.recv()
				print("Received message:", message[:77] + '...' if len(message) > 80 else message)
			except websockets.ConnectionClosed:
				print("Connection closed.")
				break
			except Exception as e:
				print("Error:", e)

# Example usage:
async def main():
	client = OpenFinchClient("ws://finch.local:8000/ws")
	await client.connect()

	# Start listening for messages
	await client.listen()

	# Close the connection after use
	await client.close()

# Run the asyncio main loop
asyncio.run(main())
