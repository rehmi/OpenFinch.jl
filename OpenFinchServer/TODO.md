# TODO

## finchcontrol.py

□ send SLM_image at original size

□ send SLM_image messages reliably

□ fix argument parsing to accept --image alongside parameter settings

## OpenFinchServer

□ display SLM_image at original size

□ receive binary SLM_image messages correctly

□ add callbacks to control_set method to update clients

□ add other camera modes

□ clean up dashboard design

□ text box containing the wave script

⧆ keep track of all frame data and metadata (e.g. timestamps, original MJPG data)

✓ add messages to set controller timing

✓ waveform generation abstraction (more LEDs, flexible camera triggering, etc.)

✓ factor out OV2311 specifics

✓ switch between output LEDs

✓ SLM image picker

✓ improve concurrency via threading and queues

✓ FPS readouts in dashboard

✓ add messages to set camera imaging controls

✓ make a python module

✓ set secondary monitor image over WS

✓ track open websockets for updates

✓ rename combo.py, reorganize OpenFinchServer and add setup.py
