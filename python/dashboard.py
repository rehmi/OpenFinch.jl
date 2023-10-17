from PIL import Image, ImageEnhance, ImageOps
from flask import Flask, render_template, jsonify, request
import numpy as np
import io
import base64
import atexit
from capdisp import ImageCapture

image_capture = ImageCapture(capture_raw=False)
image_capture.open()

app = Flask(__name__)

@app.route('/')
def index():
    return render_template('dashboard.html')

@app.route('/get-image-data', methods=['GET'])
def get_image_data():
	brightness = float(request.args.get('brightness', 1.0))
	gamma = float(request.args.get('gamma', 1.0))
	contrast = float(request.args.get('contrast', 1.0))

	image_array = image_capture.capture_frame()
	img = Image.fromarray(image_array, 'RGB')

	# Adjust brightness
	enhancer = ImageEnhance.Brightness(img)
	img = enhancer.enhance(brightness / 128.0)

	# Adjust gamma
	img = img.point(lambda p: p ** (1.0 / gamma))

	# Adjust contrast
	enhancer = ImageEnhance.Contrast(img)
	img = enhancer.enhance(contrast / 128.0)

	saturation = float(request.args.get('saturation', 1.0))
	hue = float(request.args.get('hue', 1.0))
	gain = float(request.args.get('gain', 1.0))
	sharpness = float(request.args.get('sharpness', 1.0))
	exposure_absolute = float(request.args.get('exposure_absolute', 1.0))
	exposure_auto = float(request.args.get('exposure_auto', 1.0))
	power_line_frequency = float(request.args.get('power_line_frequency', 1.0))

	continuous_capture = request.args.get('continuous_capture') == 'true'
	white_balance_temperature = request.args.get('white_balance_temperature') == 'true'
	auto_exposure = request.args.get('auto_exposure') == 'true'
	auto_priority = request.args.get('auto_priority') == 'true'
	laser1 = request.args.get('laser1') == 'true'
	laser2 = request.args.get('laser2') == 'true'
	laser3 = request.args.get('laser3') == 'true'

	# Convert to base64
	buffered = io.BytesIO()
	img.convert('L').save(buffered, format="JPEG")
	img_base64 = base64.b64encode(buffered.getvalue()).decode()

	data = {
		'pixel_count': img.size[0] * img.size[1],
		'average_brightness': np.mean(image_array),
		'timestamp': np.random.randint(1609459200, 1672531199),  # Random timestamp between 2021 and 2023
		'image_base64': img_base64
	}
	return jsonify(data)

if __name__ == '__main__':
    app.run(host="0.0.0.0", port=8000, debug=False)
