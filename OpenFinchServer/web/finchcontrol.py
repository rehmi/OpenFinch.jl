#!/usr/bin/env python3

import aiohttp
import asyncio
import sys
import json

async def send_controls_to_openfinch(controls):
    session = aiohttp.ClientSession()
    async with session.ws_connect("ws://winch.local:8000/ws") as ws:
        await ws.send_json({"set_control": controls})
        # If you want to see the response from the server, uncomment the next lines
        # response = await ws.receive()
        # print(response.data)
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
    if len(sys.argv) < 2:
        print("Usage: python script.py control1=value1 control2=value2 ...")
        sys.exit(1)
    
    controls = parse_arguments(sys.argv[1:])
    asyncio.run(send_controls_to_openfinch(controls))


if __name__ == "__main__":
    main()