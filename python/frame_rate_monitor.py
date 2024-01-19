import logging
import time

class FrameRateMonitor:
  def __init__(self, period=5.0):
      self.period=period
      self.frame_count = 0
      self.start_time = time.time()

  def reset(self):
      self.frame_count = 0
      self.start_time = time.time()

  def increment(self):
      self.frame_count += 1

  def update(self):
      self.increment()
      if time.time() - self.start_time >= self.period:
          fps = self.frame_count / (time.time() - self.start_time)
          logging.info(f"Average FPS: {fps:.2f}")
          self.reset()