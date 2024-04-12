#!/usr/bin/env python3
import argparse
import asyncio
import websockets
import base64
from PIL import Image
import io
import json
import requests
from urllib.parse import urlparse

async def send_image(uri, img_url_or_filename):
	async with websockets.connect(uri) as websocket:
		# Check if the input is a URL
		parsed_url = urlparse(img_url_or_filename)
		if bool(parsed_url.netloc):
			# Download the image from the URL
			response = requests.get(img_url_or_filename)
			img_byte_arr = response.content
		else:
			# Open the image file
			with Image.open(img_url_or_filename) as img:
				# Convert the image to bytes
				img_byte_arr = io.BytesIO()
				img.save(img_byte_arr, format='PNG')
				img_byte_arr = img_byte_arr.getvalue()

		# Send the {SLM_image : next} message
		await websocket.send(json.dumps({'SLM_image': 'next'}))
		# Send the image blob
		await websocket.send(img_byte_arr)

if __name__ == "__main__":
   parser = argparse.ArgumentParser(description='Send an image over a websocket connection.')
   parser.add_argument('img_filename', type=str, help='The filename of the image to send.')
   args = parser.parse_args()

   asyncio.get_event_loop().run_until_complete(send_image("ws://finch.local:8000/ws", args.img_filename))
   