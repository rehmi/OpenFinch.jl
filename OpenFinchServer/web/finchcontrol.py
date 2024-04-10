#!/usr/bin/env python3

import aiohttp
import asyncio
import sys
import json
import time
import base64
import argparse

host="winch.local"
port=8000

# Add a new command-line argument for the image file path
parser = argparse.ArgumentParser(description='Send controls to OpenFinch.')
parser.add_argument('--image', type=str, help='Path to the local image file to send.')
parser.add_argument('controls', nargs='*', help='Controls in the format control1=value1 control2=value2 ...')
args = parser.parse_args()

# Function to encode an image file to base64
def encode_image(image_path):
    with open(image_path, "rb") as image_file:
        return base64.b64encode(image_file.read()).decode('utf-8')

async def send_controls_to_openfinch(controls):
    session = aiohttp.ClientSession()
    async with session.ws_connect(f"ws://{host}:{port}/ws") as ws:
        await ws.send_json({"set_control": controls})
        response = await ws.receive()
        response = await ws.receive()
        await session.close()

async def send_image_to_openfinch(encoded_image):
    session = aiohttp.ClientSession()
    async with session.ws_connect(f"ws://{host}:{port}/ws") as ws:
        await ws.send_json({"slm_image": encoded_image})
        
        time.sleep(10)
        response = await ws.receive()
        await session.close()

def parse_arguments(args):
    controls = {}
    for arg in args:
        key, value = arg.split('=')
        
        # Check for boolean values first
        if value.lower() == 'true':
            value = True
        elif value.lower() == 'false':
            value = False
        else:
            # Attempt to directly parse the value as a float or integer
            try:
                value = float(value)
                if value.is_integer():
                    value = int(value)
            except ValueError:
                # If not a single float or integer, check for a list of floats
                if ',' in value:
                    try:
                        value = [float(x) for x in value.split(',')]
                    except ValueError:
                        # If parsing as list of floats fails, treat as a string
                        pass
                else:
                    # If no comma, not a float, and not a boolean, treat as a string
                    pass
        
        controls[key] = value
    return controls

def main():
    # if len(sys.argv) < 2:
    #     print("Usage: python script.py control1=value1 control2=value2 ...")
    #     sys.exit(1)

    if args.image:
        # Encode the image and send it to the server
        encoded_image = encode_image(args.image)
        asyncio.run(send_image_to_openfinch(encoded_image))
        # asyncio.run(send_controls_to_openfinch({"slm_image": encoded_image}))
    else:
        # Existing logic to send controls
        controls = parse_arguments(sys.argv[1:])
        print(controls)
        asyncio.run(send_controls_to_openfinch(controls))

    # controls = parse_arguments(sys.argv[1:])
    # asyncio.run(send_controls_to_openfinch(controls))


if __name__ == "__main__":
    main()
