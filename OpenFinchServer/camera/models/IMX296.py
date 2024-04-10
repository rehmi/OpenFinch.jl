def IMX296Defaults():
	return {
    	# 'AeLocked': True,
		'AnalogueGain': 1.0,
		# 'ColourCorrectionMatrix': (1.5848532915115356,
		# 							-0.385071337223053,
		# 							-0.24371767044067383,
		# 							-0.4105437695980072,
		# 							1.5727728605270386,
		# 							-0.1410859227180481,
		# 							0.21162152290344238,
		# 							-1.1596087217330933,
		# 							1.8914762735366821),
		'ColourGains': (1.0, 1.0),
		# 'ColourTemperature': 2445,
		# 'DigitalGain': 1.0098035335540771,
		'ExposureTime': 8333,
		# 'FocusFoM': 898,
		# 'FrameDuration': 120058,
		# 'Lux': 2.695587396621704,
		'ScalerCrop': (0, 0, 1456, 1088),
		# 'SensorBlackLevels': (3840, 3840, 3840, 3840),
		# 'SensorTimestamp': 170709439110000
  	}

imx296_controls = {
    'FrameDurationLimits': {'id': 25, 'type': 'integer64', 'range': (16562, 15534444)},
    'ExposureValue': {'id': 6, 'type': 'float', 'range': (-8.0, 8.0)},
    'AwbMode': {'id': 13, 'type': 'integer32', 'range': (0, 7)},
    'AeExposureMode': {'id': 5, 'type': 'integer32', 'range': (0, 3)},
    'NoiseReductionMode': {'id': 39, 'type': 'integer32', 'range': (0, 4)},
    'ScalerCrop': {'id': 22, 'type': 'rectangle', 'range': ((0, 0), (1456, 1088))},
    'Sharpness': {'id': 19, 'type': 'float', 'range': (0.0, 16.0)},
    'AwbEnable': {'id': 12, 'type': 'bool', 'range': (False, True)},
    'AeEnable': {'id': 1, 'type': 'bool', 'range': (False, True)},
    'ExposureTime': {'id': 7, 'type': 'integer32', 'range': (29, 15534385)},
    'AeConstraintMode': {'id': 4, 'type': 'integer32', 'range': (0, 3)},
    'Brightness': {'id': 9, 'type': 'float', 'range': (-1.0, 1.0)},
    'ColourGains': {'id': 15, 'type': 'float', 'range': (0.0, 32.0)},
    'AnalogueGain': {'id': 8, 'type': 'float', 'range': (1.0, 251.188644)},
    'Contrast': {'id': 10, 'type': 'float', 'range': (0.0, 1.0)}
}
