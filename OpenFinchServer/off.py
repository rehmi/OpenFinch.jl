import logging
from aiohttp import web
from .camera_server import CameraServer

def main():
	try:
		fmt = "%(threadName)-10s %(asctime)-15s %(levelname)-5s %(name)s: %(message)s"
		logging.basicConfig(level="INFO", format=fmt, filename="combo.log")

		server = CameraServer()

		app = web.Application()
		app.router.add_get('/', server.handle_http)
		app.router.add_get('/ws', server.handle_ws)
		app.on_startup.append(server.on_startup)

		web.run_app(app, host='0.0.0.0', port=8000)
	except KeyboardInterrupt:
		logging.info("Ctrl-C pressed. Bailing out")
	finally:
		server.cam.shutdown()
