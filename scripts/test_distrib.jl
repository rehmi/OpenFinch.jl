using Distributed

finch = first(addprocs(["finch.local", 1], exename="julia", dir="/home/rehmi/finch"))
