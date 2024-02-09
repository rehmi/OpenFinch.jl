
class Control:
    def __init__(self, name, id, type, range, default=None, value=None):
        self.name = name
        self.id = id
        self.type = type
        self.range = range
        self.default = default
        self.value = value

class IntegerControl(Control):
    def __init__(self, name, id, type, range, step, default, value):
        super().__init__(name, id, type, range, default, value)
        self.step = step

class MenuControl(Control):
    def __init__(self, name, id, type, options, default, value):
        super().__init__(name, id, type, None, default, value)
        self.options = options

class BooleanControl(Control):
    def __init__(self, name, id, type, default, value):
        super().__init__(name, id, type, (0, 1), default, value)

class FloatControl(Control):
    def __init__(self, name, id, type, range, default, value):
        super().__init__(name, id, type, range, default, value)

import v4l2py
import picamera2
from picamera2 import libcamera
from libcamera import ControlType
import logging


def convert_v4l2py_controls(dev_controls):
    controls = {}
    for control_id, control in dev_controls.items():
        control_type = type(control).__name__
        if control_type == 'MenuControl':
            break
            controls[control_id] = MenuControl(control.name, control_id, control_type, control.menu, control.default, control.value)
        elif control_type == 'IntegerControl':
            controls[control_id] = IntegerControl(control.name, control_id, control_type, (control.minimum, control.maximum), control.step, control.default, control.value)
        elif control_type == 'BooleanControl':
            controls[control_id] = BooleanControl(control.name, control_id, control_type, control.default, control.value)
        elif control_type == 'FloatControl':
            controls[control_id] = FloatControl(control.name, control_id, control_type, (control.minimum, control.maximum), control.default, control.value)
    return controls

# # Create a v4l2py device and get its controls
# dev = v4l2py.Device("/dev/video1")
# dev.open()
# dev_controls = dev.controls
# # Convert the v4l2py controls to our common format
# v4l2py_controls = convert_v4l2py_controls(dev_controls)
# # Print the common controls
# # for control in common_dev_controls.values():
#     # logging.debug(f"v4l2py control: {control.__dict__}")
# dev.close()

# # Create a picamera2 device and get its controls
# p = picamera2.Picamera2()
# camera_ctrl_info = p.camera_ctrl_info
# # Convert the picamera2 controls to our common format
# picamera2_controls = convert_picamera_controls(camera_ctrl_info)
# # Print the common controls
# # for control in picamera2_controls.values():
#     # logging.debug(f"picamera2 control: {control.__class__.__name__}{control.__dict__}")
# p.close()
