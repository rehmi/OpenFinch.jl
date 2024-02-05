from abc import ABC, abstractmethod

class AbstractCameraController(ABC):

    @abstractmethod
    def capture_frame(self, blocking=True):
        pass

    @abstractmethod
    def open(self):
        pass

    @abstractmethod
    def close(self):
        pass

    @abstractmethod
    def set_control(self, control_name, value):
        pass

    @abstractmethod
    def get_control(self, control_name):
        pass

    @abstractmethod
    def get_controls(self):
        pass

# here are common control names comprising a superset of the capabilities
# exposed by v4l2py and picamera2
common_control_names = {
    'brightness',  
    'contrast',
    'gamma',   
    'gain',
    'power_line_frequency',
    'white_balance_temperature',   
    'sharpness',   
    'backlight_compensation',  
    'exposure_time',   
    'exposure_auto',   
    'exposure_absolute',   
    'exposure_auto_priority', 
    'analogue_gain',   
    'colour_gains',
    'awb_enable', 
    'ae_enable',  
    'ae_exposure_mode',
    'ae_constraint_mode',  
    'noise_reduction_mode',
    'scaler_crop', 
}
