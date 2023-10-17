import rpyc
from plumbum import SshMachine
from rpyc.utils.zerodeploy import DeployedServer

class RemotePython:
	pass

class RPYCClassic(RemotePython):
	def __init__(self, host, user="", connect_timeout=60):
		self.host = host
		self.mach = SshMachine(host=host, user=user, connect_timeout=connect_timeout)
		self.server = DeployedServer(self.mach)
		self.rpy = self.server.classic_connect()
		self.version = self.rpy.modules.sys.version.replace("\n", "")
		self.pid = self.rpy.modules.os.getpid()

		print(f"connected to Python {self.version}, pid {self.pid}")

	def __repr__(self):
		return f"RPYCClassic(host={self.host}, pid={self.pid}, version={self.version})"

	def __getattr__(self, k):
		if k in self.__dict__:
			return getattr(self, k)
		else:
			return getattr(self.rpy, k)

def RemotePython(host, user="", **kwargs):
	return RPYCClassic(host, user, **kwargs)
