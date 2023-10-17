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

from capdisp import ImageCapture

image_capture = ImageCapture(capture_raw=False)
image_capture.open()

OV2311_defaults = {
	"brightness": 0,
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

# The user's code is already a Flask-Based interactive interface using jupyter widgets (IPython). However, if they want to replace it with a traditional Flask (Web-Based) framework, here is a simple reference:

from flask import Flask, request, render_template
from flask_wtf import FlaskForm
from wtforms import SubmitField, BooleanField, IntegerField
from wtforms.validators import DataRequired

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
	print("entering home()")
	form = CameraControls()
	captured_image = False
	
	if form.validate_on_submit():
		print("Capturing image...")
  
		image_array = image_capture.capture_frame()
		img = PILImage.fromarray(image_array, 'RGB')

		# Convert image to data URL
		data = io.BytesIO()
		img.save(data, "JPEG")
		data64 = base64.b64encode(data.getvalue())
		captured_image = "data:image/jpeg;base64," + data64.decode('utf-8')

		return render_template('camdash.html', form=form, captured_image=captured_image)
	else:
		return render_template('camdash.html', form=form)

if __name__ == "__main__":
	app.run(debug=False)

# The above Flask app creates a form using the Flask-WTF library with fields corresponding to your code's controls.
# Each field corresponds to a user input control you had with similar names. The home route renders this form on a simple HTML template (referenced as 'home.html').
# If the form is valid after submission, the respective control's value should be updated accordingly.
# Please consider that you should write a separate HTML file ('home.html') to render the front end of your application.