import time
from ImageCapture import ImageCapture
from Display import Display

if __name__ == "__main__":
	vidcap = ImageCapture(capture_raw=False)
	vidcap.open()
	display = Display()

	frame_count = 0
	start_time = time.time()

	while True:
		try:
			img = vidcap.capture_frame()
			frame_count += 1

			display.show_frame(img)

			if time.time() - start_time >= 5:
				fps = frame_count / (time.time() - start_time)
				print(f"Average FPS: {fps:.2f}")
				frame_count = 0
				start_time = time.time()

			if display.waitKey(1) & 0xFF == ord('q'):
				break
		except AttributeError:
			continue

	display.close()
	vidcap.close()