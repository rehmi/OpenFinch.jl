def OV2311Defaults():
    return {
		"brightness": 0,
		"contrast": 32,
		"saturation": 0,
		"hue": 1,
		"gamma": 100,
		"gain": 0,
		"power_line_frequency": 0,
		"sharpness": 6,
		"backlight_compensation": 0,
		"exposure_auto": 1,
		"exposure_absolute": 66,
		"exposure_auto_priority": 0
	}


ov2311_controls = {
    'brightness': {'id': 0x00980900, 'type': 'int', 'min': -64, 'max': 64, 'step': 1, 'default': 0, 'value': 0},
    'contrast': {'id': 0x00980901, 'type': 'int', 'min': 0, 'max': 64, 'step': 1, 'default': 32, 'value': 32},
    'saturation': {'id': 0x00980902, 'type': 'int', 'min': 0, 'max': 128, 'step': 1, 'default': 64, 'value': 0},
    'hue': {'id': 0x00980903, 'type': 'int', 'min': -40, 'max': 40, 'step': 1, 'default': 0, 'value': 1},
    'white_balance_temperature_auto': {'id': 0x0098090c, 'type': 'bool', 'default': True, 'value': True},
    'gamma': {'id': 0x00980910, 'type': 'int', 'min': 72, 'max': 500, 'step': 1, 'default': 100, 'value': 100},
    'gain': {'id': 0x00980913, 'type': 'int', 'min': 0, 'max': 100, 'step': 1, 'default': 0, 'value': 0},
    'power_line_frequency': {'id': 0x00980918, 'type': 'menu', 'min': 0, 'max': 2, 'default': 2, 'value': 0},
    'white_balance_temperature': {'id': 0x0098091a, 'type': 'int', 'min': 2800, 'max': 6500, 'step': 1, 'default': 4600, 'value': 4600, 'flags': 'inactive'},
    'sharpness': {'id': 0x0098091b, 'type': 'int', 'min': 0, 'max': 6, 'step': 1, 'default': 3, 'value': 6},
    'backlight_compensation': {'id': 0x0098091c, 'type': 'int', 'min': 0, 'max': 2, 'step': 1, 'default': 1, 'value': 0},
    'exposure_auto': {'id': 0x009a0901, 'type': 'menu', 'min': 0, 'max': 3, 'default': 3, 'value': 1},
    'exposure_absolute': {'id': 0x009a0902, 'type': 'int', 'min': 1, 'max': 5000, 'step': 1, 'default': 157, 'value': 66},
    'exposure_auto_priority': {'id': 0x009a0903, 'type': 'bool', 'default': False, 'value': True}
}
