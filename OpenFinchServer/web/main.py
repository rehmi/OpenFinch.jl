import logging
from aiohttp import web
from web.server import CameraServer
import argparse
import pigpio

def del_all_procs():
    pi = pigpio.pi()
    if not pi.connected:
        logging.error("Could not connect to pigpio daemon. Is it running?")
        return
    
    for i in range(32):
        try:
            pi.delete_script(i)
        except Exception as e:
            pass
        
    pi.wave_clear()  # Clear any existing waveforms

    pi.stop()

def set_trigger_mode(mode):
    try:
        with open('/sys/module/imx296/parameters/trigger_mode', 'w') as f:
            f.write(str(mode))
        logging.info(f"Trigger mode set to {mode}")
    except IOError as e:
        logging.error(f"Failed to set trigger mode: {e}")

def main():
    parser = argparse.ArgumentParser(description='OpenFinchServer Application')
    parser.add_argument('--log', action='store_true', help='Direct logging to stdout')
    parser.add_argument('--log-file', type=str, help='Direct logging to a specified file')
    parser.add_argument('--delprocs', action='store_true', help='Delete all existing procs')
    parser.add_argument('--set-trigger-mode', type=int, choices=[0, 1], nargs='?', const=1, default=None, help='Set trigger mode for imx296 module (0 or 1, default: 1 if argument given without value)')
    parser.add_argument('--color-gains', type=str, help='Set color gains as a comma-separated pair (e.g., "1.5,1.2" for red and blue gains)')

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

        if args.delprocs:
            del_all_procs()

        if args.set_trigger_mode is not None:
            set_trigger_mode(args.set_trigger_mode)

        color_gains = args.color_gains

        if color_gains:
            try:
                red_gain, blue_gain = map(float, color_gains.split(','))
            except ValueError:
                logging.error("Invalid format for --color-gains. Expected format: 'red_gain,blue_gain'")
                exit(1)

        server = CameraServer()

        app = web.Application()
        app.router.add_get('/', server.handle_http)
        app.router.add_get('/ws', server.handle_ws)
        app.on_startup.append(server.on_startup)

        if color_gains:
            server.set_color_gains(red_gain, blue_gain)

        web.run_app(app, host='0.0.0.0', port=8000)
    except KeyboardInterrupt:
        logging.info("Ctrl-C pressed. Bailing out")
    finally:
        server.shutdown()
        logging.info(f"ending {__name__}")
        pass

if __name__ == '__main__':
    main()
    
