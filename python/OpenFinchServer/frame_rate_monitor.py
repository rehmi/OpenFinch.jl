import logging
import time

class FrameRateMonitor:
	def __init__(self, label, period=5.0):
		self.label = label
		self.period=period
		self.frame_count = 0
		self.start_time = time.time()
		self.latest_fps = 0

	def reset(self):
		self.frame_count = 0
		self.start_time = time.time()

	def increment(self):
		self.frame_count += 1

	def update(self):
		self.increment()
		if time.time() - self.start_time >= self.period:
			fps = self.frame_count / (time.time() - self.start_time)
			logging.info(f"{self.label}: average FPS {fps:.2f}")
			self.latest_fps = fps
			self.reset()

	def get_fps(self):
		return self.latest_fps
			
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
			self._log_summary()
			self._flush_data()

	def _log_summary(self):
		logging.info(f"{self.label} fps mean={1/statistics.mean(self.data_points):.2f}  median={1/statistics.median(self.data_points):.2f}   n={len(self.data_points)}")

	def _flush_data(self):
		self.data_points = []
		self.last_flush_time = time.time()