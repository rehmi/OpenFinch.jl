from abc import ABC, abstractmethod

class CameraControllerInterface(ABC):
    @abstractmethod
    def set_preview_mode(self):
        pass

    @abstractmethod
    def set_still_mode(self):
        pass

    @abstractmethod
    def set_video_mode(self):
        pass
