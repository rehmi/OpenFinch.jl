import logging
import time
import statistics

class StatsMonitor():
  def __init__(self, label, flush_interval=10):
      self.label = label
      self.data_points = []
      self.flush_interval = flush_interval
      self.last_flush_time = time.time()

  def add_point(self, value):
      self.data_points.append(value)
      if time.time() - self.last_flush_time >= self.flush_interval:
          self._print_summary()
          self._flush_data()

  def _print_summary(self):
      logging.info(f"{self.label} fps mean={1/statistics.mean(self.data_points):.2f}  median={1/statistics.median(self.data_points):.2f}   n={len(self.data_points)}")

  def _flush_data(self):
      self.data_points = []
      self.last_flush_time = time.time()