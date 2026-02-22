#
# This file is part of the Actors.jl Julia package, MIT license
#
# Paul Bayer, 2020
#

_root(d::Dict{Symbol,Any}) = d
_root(d::Dict{Symbol,Any}, key::Symbol, val) = d[key] = val

function __init__()
    if myid() == 1
        global _REG = Link(
            RemoteChannel(()->spawn(_reg, Dict{Symbol, Link}()).chn), 
            1, :registry)
        global _ROOT = Link(
            RemoteChannel(()->spawn(_root, Dict{Symbol,Any}(:start=>now())).chn),
            1, :root)
        update!(_ROOT, :system, s=:mode)
    else
        # Fetch only the RemoteChannel (a plain Distributed type, always deserializable)
        # and construct the Link locally, avoiding Actors-type deserialization
        # during __init__ when the module is not yet registered.
        global _REG = Link(remotecall_fetch(()->Actors._REG.chn, 1), 1, :registry)
        global _ROOT = Link(remotecall_fetch(()->Actors._ROOT.chn, 1), 1, :root)
    end
end
