#
# This file is part of the Actors.jl Julia package, 
# MIT license, part of https://github.com/JuliaActors
#

# -----------------------------------------------
# Basic Types
# -----------------------------------------------

"""
    Args(args...; kwargs...)

A structure for updating arguments to an actor's behavior.
"""
struct Args{A,B}
    args::A
    kwargs::B

    Args(args...; kwargs...) = new{typeof(args),typeof(kwargs)}(args, kwargs)
end

"""
    Bhv(func, a...; kw...)(c...)

A callable struct to represent actor behavior. It is executed
with parameters from the incoming communication.

# Parameters

- `f`: a callable object,
- `a...`: stored acquaintance parameters to `f`,
- `kw...`: stored keyword arguments,
- `c...`: parameters from the incoming communication.
"""
struct Bhv{F}
    f
    a::Tuple
    kw::Base.Iterators.Pairs
    ϕ::F

    function Bhv(f, a...; kw...)
        ϕ = (c...) -> f(a..., c...; kw...)
        new{typeof(ϕ)}(f, a, kw, ϕ)
    end
end
(p::Bhv)(c...) = p.ϕ(c...)

#
# Since Bhv contains an anonymous function, the following 
# is needed to make it executable in another thread or worker.
# It returns a Bhv for the current world age.
# 
_current(p::Bhv) = Bhv(p.f, p.a...; p.kw...)
_current(x) = x

"""
```
Link{C} <: ActorInterfaces.Classic.Addr
Link(chn::C, pid::Int, type::Symbol) where C
```

A mailbox for communicating with actors. A concrete type of
this must be returned by an actor on creation with [`spawn`](@ref).

# Fields/Parameters
- `chn::C`: C can be any type and characterizes the interface
    to an actor,
- `pid::Int`: the pid (worker process identifier) of the actor, 
- `mode::Symbol`: a symbol characterizing the actor mode.
"""
mutable struct Link{C} <: Addr
    chn::C
    pid::Int
    mode::Symbol
end

"Abstract type for connections between actors."
abstract type Connection end

"""
```
_ACT{B,R,S,U}
```
Internal actor status variable with type parameters for improved performance.

# Type Parameters

- `B`: behavior type (for `bhv`, `init`, `term`)
- `R`: result type (for `res`)
- `S`: state type (for `sta`)
- `U`: user type (for `usr`)

# Fields

1. `mode::Symbol`: the actor mode,
2. `bhv::B`:  behavior - a callable object,
3. `init::Union{Nothing,B}`: initialization - a callable object, 
4. `term::Union{Nothing,B}`: termination - a callable object,
5. `self::Union{Nothing,Link}`: the actor's address,
6. `name::Union{Nothing,Symbol}`: the actor's registered name,
7. `res::R`: the result of the last behavior execution,
8. `sta::S`: a variable for representing state,
9. `usr::U`: user variable for plugging in something,
10. `conn::Vector{Connection}`: connected actors.

see also: [`Bhv`](@ref), [`Link`](@ref)
"""
mutable struct _ACT{B,R,S,U}
    mode::Symbol
    bhv::B
    init::Union{Nothing,B}
    term::Union{Nothing,B}
    self::Union{Nothing,Link}
    name::Union{Nothing,Symbol}
    res::R
    sta::S
    usr::U
    conn::Vector{Connection}
end

const _ACTAny = _ACT{Any,Any,Any,Any}

"""
    _ACT(mode=:default)

Return a actor variable `_ACT` with type parameters defaulting to `Any`.
"""
_ACT(mode::Symbol=:default) = _ACT{Any,Any,Any,Any}(
    mode, Bhv(+), nothing, nothing, nothing, nothing, nothing, nothing, nothing, Connection[]
)

"""
## Actor information
- `mode::Symbol`: actor mode,
- `bhvf::Any`: behavior function,
- `pid::Int`: process identifier,
- `thrd::Int`: thread,
- `task::Task`: actor task address,
- `tid::String`: hex identifier based on task address,
- `name::Union{Nothing,Symbol}`: name under which the actor is
    registered, `nothing` if not registered.
"""
struct Info
    mode::Symbol
    bhvf::Any
    pid::Int
    thrd::Int
    task::UInt
    tid::String
    name::Union{Nothing,Symbol}
end

# -----------------------------------------------
# Public message types
# -----------------------------------------------
"Abstract type for messages to actors."
abstract type Msg end

"""
    Request(x, from::Link)

A generic [`Msg`](@ref) for user requests.
"""
struct Request <: Msg
    x
    from::Link
end

"""
    Response(y, from::Link=self())

A [`Msg`](@ref) representing a response to requests.

# Fields
- `y`: response content,
- `from::Link`: sender link.
"""
struct Response <: Msg
    y
    from::Link
end
Response(y) = Response(y, self())
