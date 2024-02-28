# TODO

## OpenFinch.jl

□ API to communicate with OpenFinchServer

□ add README.md, link to SLM-VERA


## OpenFinchServer, combo.py:

□ add callbacks to control_set method to update clients

□ waveform generation abstraction (more LEDs, flexible camera triggering, etc.)

□ add other camera modes

□ factor out OV2311 specifics

□ clean up dashboard design

□ switch between output LEDs

□ SLM image picker

□ text box containing the wave script

□ improve concurrency via threading and queues

⧆ keep track of all frame data and metadata (e.g. timestamps, original MJPG data)

⧆ add messages to set controller timing

✓ FPS readouts in dashboard

✓ add messages to set camera imaging controls

✓ make a python module

✓ set secondary monitor image over WS

✓ track open websockets for updates

✓ rename combo.py, reorganize OpenFinchServer and add setup.py
