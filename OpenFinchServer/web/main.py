import logging
from aiohttp import web
from web.server import CameraServer
import argparse

def main():
    parser = argparse.ArgumentParser(description='OpenFinchServer Application')
    parser.add_argument('--log', action='store_true', help='Direct logging to stdout')
    parser.add_argument('--log-file', type=str, help='Direct logging to a specified file')

    args = parser.parse_args()

    fmt = "%(threadName)-10s %(asctime)-15s %(levelname)-5s %(name)s: %(message)s"

    if args.log:
        logging.basicConfig(level=logging.INFO, format=fmt)
    elif args.log_file:
        logging.basicConfig(level=logging.INFO, format=fmt, filename=args.log_file, filemode='w')
    else:
        # Disable logging by default
        logging.disable(logging.CRITICAL)

    try:
        logging.info(f"starting {__name__}")

        server = CameraServer()

        app = web.Application()
        app.router.add_get('/', server.handle_http)
        app.router.add_get('/ws', server.handle_ws)
        app.on_startup.append(server.on_startup)

        web.run_app(app, host='0.0.0.0', port=8000)
    except KeyboardInterrupt:
        logging.info("Ctrl-C pressed. Bailing out")
    finally:
        server.shutdown()
        logging.info(f"ending {__name__}")
        pass

if __name__ == '__main__':
    main()

