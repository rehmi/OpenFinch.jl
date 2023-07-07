module RPYC

# you can do the import when the module is loaded, saving the result in a Ref
#
# module MyModule
#   using PythonCall
#   const foo = Ref{Py}()
#   function __init__()
#     foo[] = pyimport("foo")
#   end
#   bar() = foo[].bar()
# end
#
# or you can perform any imports dynamically
#
# module MyModule
#   using PythonCall
#   bar() = pyimport("foo").bar()
# end
#
# or if that is too slow, you can cache the import
#
# module MyModule
#   using PythonCall
#   bar() = @pyconst(pyimport("foo")).bar()
# end
#
# or even cache the imported function
#
# module MyModule
#   using PythonCall
#   bar() = @pyconst(pyimport("foo").bar)()
# end

using PythonCall

const rpyc = Ref{Py}()
const plumbum = Ref{Py}()
const zerodeploy = Ref{Py}()


function __init__()
    rpyc[] = pyimport("rpyc")
    plumbum[] = pyimport("plumbum")
    zerodeploy[] = pyimport("rpyc.utils.zerodeploy")
end

abstract type RemotePython end

RemotePython(host::AbstractString, user::AbstractString=""; kwargs...) = RPYCClassic(host, user; kwargs...)
struct RPYCClassic <: RemotePython
	host
	mach
	server
	rpy
	version
	pid
	
	function RPYCClassic(host::AbstractString, user::AbstractString=""; connect_timeout=60)
		host = host
		mach = plumbum[].SshMachine(host=host, user=user, connect_timeout=connect_timeout)
		server = zerodeploy[].DeployedServer(mach)
		rpy = server.classic_connect()
		version = replace(pyconvert(String, rpy.modules.sys.version), "\n"=>"")
		pid = pyconvert(Int, rpy.modules.os.getpid())

		self = new(host, mach, server, rpy, version, pid)

		@info "connected to Python $(self.version), pid $(self.pid)"
		
		return self
	end
end

function Base.show(io::IO, r::RPYCClassic)
	print(io, "RPYCClassic(host=$(r.host), pid=$(r.pid), version=$(r.version))")
end

function Base.getproperty(remote::RPYCClassic, k::Symbol)
	if k ∈ propertynames(remote)
		getfield(remote, k)
	else
		Base.getproperty(getfield(remote, :rpy), k)
	end
end

export RPYCClassic, RemotePython

end
