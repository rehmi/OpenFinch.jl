from typing import Type
from ipywidgets import IntSlider, Checkbox, Button, Image
from IPython.display import display
from io import BytesIO
import base64
from PIL import Image as PILImage
import numpy as np
import cv2
import pigpio
import v4l2py
import rpyc
import io
from RPYC import RemotePython, RPYCClassic

from flask import Flask, request, render_template
from flask_wtf import FlaskForm
from flask import jsonify
from flask import session
from wtforms import SubmitField, BooleanField, IntegerField
from wtforms.validators import DataRequired
from capdisp import ImageCapture

image_capture = ImageCapture(capture_raw=False)
image_capture.open()

OV2311_defaults = {
	"brightness": 50,
	"contrast": 32,
	"saturation": 64,
	"hue": 1,
	"gamma": 72,
	"gain": 54,
	"power_line_frequency": 2,
	"sharpness": 3,
	"backlight_compensation": 0,
	"exposure_auto": 1,
	"exposure_absolute": 1,
	"exposure_auto_priority": 0,
	# "white_balance_temperature": 4600
}

app = Flask(__name__)
app.config['SECRET_KEY'] = '9a1db2409162b580b1f7b4895e37e2bb'

class CameraControls(FlaskForm):
	capture_frame = SubmitField('Capture Frame')
	continuous_capture = BooleanField('Continuous capture')
	brightness = IntegerField('Brightness', validators=[DataRequired()], default=OV2311_defaults["brightness"])
	contrast = IntegerField('Contrast', validators=[DataRequired()], default=OV2311_defaults["contrast"])
	saturation = IntegerField('Saturation', validators=[DataRequired()], default=OV2311_defaults["saturation"])
	gamma = IntegerField('Gamma', validators=[DataRequired()], default=OV2311_defaults["gamma"])
	gain = IntegerField('Gain', validators=[DataRequired()], default=OV2311_defaults["gain"])
	sharpness = IntegerField('Sharpness', validators=[DataRequired()], default=OV2311_defaults["sharpness"])
	exposure_absolute = IntegerField('Exposure absolute', validators=[DataRequired()], default=OV2311_defaults["exposure_absolute"])
	white_balance_temperature_auto = BooleanField('White balance temperature auto')
	exposure_auto_priority = BooleanField('Exposure auto priority')
	exposure_auto = IntegerField('Exposure auto', validators=[DataRequired()], default=OV2311_defaults["exposure_auto"])
	power_line_frequency = IntegerField('Power line frequency', validators=[DataRequired()], default=OV2311_defaults["power_line_frequency"])
	laser1 = BooleanField('Laser 1')
	laser2 = BooleanField('Laser 2')
	laser3 = BooleanField('Laser 3')

@app.route("/", methods=['GET', 'POST'])
def home():
	captured_image = False

	form = CameraControls()

	if form.validate_on_submit():
		session['continuous_capture'] = form.continuous_capture.data

		image_array = image_capture.capture_frame()
		img = PILImage.fromarray(image_array, 'RGB')

		# Convert image to data URL
		data = io.BytesIO()
		img.save(data, "JPEG")
		data64 = base64.b64encode(data.getvalue())
		captured_image = "data:image/jpeg;base64," + data64.decode('utf-8')

	form.continuous_capture.data = session.get('continuous_capture', False)
	return render_template('camdash.html', form=form, captured_image=captured_image)

@app.route("/capture", methods=['POST'])
def capture():
	image_array = image_capture.capture_frame()
	img = PILImage.fromarray(image_array, 'RGB')

	# Convert image to data URL
	data = io.BytesIO()
	img.save(data, "JPEG")
	data64 = base64.b64encode(data.getvalue())
	captured_image = "data:image/jpeg;base64," + data64.decode('utf-8')

	return jsonify({'captured_image': captured_image})

if __name__ == "__main__":
	app_ctx = app.app_context()
	app_ctx.push()

	app.run(debug=False)
	app_ctx.pop()
