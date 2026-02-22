# Actor Behavior

```@meta
CurrentModule = Actors
```

An actor embodies the three essential elements of computation: 1) processing, 2) storage and 3) communication[^1]. Its behavior therefore can be described as ``f(a)[c]``,  representing

1. ``f``: a function, *processing*,
2. ``a``: acquaintances, *storage*, data that it has,
3. ``c``: *communication*, a message.

It processes an incoming message ``c`` with its behavior function ``f`` based on its acquaintances ``a``.

> When an Actor receives a message, it can concurrently:
>
> - send messages to ... addresses of Actors that it has;
> - create new Actors;
> - designate how to handle the next message it receives. [^2]

Gul Agha described the *behavior* as a ...

> ... function of the incoming communication.
>
> Two lists of identifiers are used in a behavior definition. Values for the first list of parameters must be specified when the actor is created. This list is called the *acquaintance list*. The second list of parameters, called the *communication list*, gets its bindings from an incoming communication. [^3]

A behavior then maps the incoming communication to a three tuple of messages sent, new actors created and the replacement behavior:

```math
\begin{array}{lrl}
f_i(a_i)[c_i] & \rightarrow &\{\{\mu_u,\mu_v, ...\},\;\{\alpha_x,\alpha_y,...\},\;f_{i+1}(a_{i+1})\} \quad\\
\textrm{with} & f: & \textrm{behavior function} \\
 & a: & \textrm{acquaintances,} \\
 & c: & \textrm{communication,} \\
 & \mu: & \textrm{messages sent,} \\
 & \alpha: & \textrm{actors created.} \\
\end{array}
```

## Behavior Representation in Julia

`Actors` expresses actor behavior in a functional style. Actors are basically *function servers*. Their behavior is a [partial application](https://en.wikipedia.org/wiki/Partial_application) of a callable object ``f(a...,c...)`` to acquaintances ``a...``, that is, a closure over ``f(a...)``. If the actor receives a communication ``c...``, the closure invokes ``f(a...,c...)``. The [`...`-operator](https://docs.julialang.org/en/v1.6/manual/faq/#What-does-the-...-operator-do?) allows us to use multiple acquaintance and communication arguments (i.e. lists).

```@repl
f(a, c) = a + c         # define a function
partial(f, a...; kw...) = (c...) -> f(a..., c...; kw...)
bhv = partial(f, 1)     # partially apply f to 1, return a closure
bhv(2)                  # execute f(1,2)
```

Similar to the `partial` above, [`Bhv`](@ref) is a convenience function to create a partial application `ϕ(a...; kw...)` with optional keyword arguments, which can be executed with communication arguments `c...`:

```@repl bhv
using Actors, .Threads
import Actors: spawn, newLink
f(s, t; w=1, x=1) = s + t + w + x   # a function
bhv = Bhv(f, 2, w=2, x=2);          # create a behavior of f and acquaintances
bhv(2)                              # execute it with a communication parameter
```

### Object-oriented Style

Alternatively we define an object with some data (acquaintances) and make it [callable](https://en.wikipedia.org/wiki/Function_object) with communication parameters:

```@repl bhv
struct A                            # define an object 
    s; w; x                         # with acquaintances
end
(a::A)(t) = a.s + a.w + a.x + t     # make it a functor, executable with a communication parameter t
bhv = A(2, 2, 2)                    # create an instance
bhv(2)                              # execute it with a parameter
```

## Actor Operation

When we create an actor with a behavior by using [`spawn`](@ref), it is ready to receive communication arguments and to process them:

1. You can create an actor with anything callable as behavior regardless whether it contains acquaintances or not.
2. Over its [`Link`](@ref) you can [`send`](@ref) it communication arguments and cause the actor to execute its behavior with them. `Actors`' [API](../api/user_api.md) functions like [`call`](@ref), [`exec`](@ref) are just wrappers around `send` and [`receive`](@ref) using a communication [protocol](protocol.md).
3. If an actor receives wrong/unspecified communication arguments, it will fail with a `MethodError`.
4. With [`become!`](@ref) and [`become`](@ref) we can change an actor's behavior.

```@repl bhv
me = newLink()
myactor = spawn(()->send(me, threadid()),thrd=2) # create an actor with a parameterless anonymous behavior function
send(myactor)                                    # send it an empty tuple
receive(me)                                      # receive the result
become!(myactor, threadid)
call(myactor)                                    # call it without arguments
become!(myactor, (lk, x, y) -> send(lk, x^y))    # an anonymous function with communication arguments
send(myactor, me, 123, 456)                      # send it arguments
receive(me)                                      # receive the result
```

In setting actor behavior you are free to mix the functional and object oriented approaches. For example you can give functors further acquaintance parameters (as for the players in the [table-tennis example](@ref table-tennis)). Of course you can give objects containing acquaintances as parameters to a function and create a partial application with `Bhv` on them and much more.

## Actors Don't Share State

Actors must not share state in order to avoid race conditions. Acquaintance and communication parameters are actor state. `Actors` does not disallow for an actor to access and to modify mutable variables. It is therefore left to the programmer to exclude race conditions by not sharing them with other actors or tasks and accessing them concurrently. In most cases you can control which variables get passed to an actor and avoid to share them.

Note that when working with distributed actors, variables get copied automatically when sent over a `Link` (a `RemoteChannel`).

### Share Actors Instead Of Memory

But in many cases you want actors or tasks to concurrently use the same variables. You can then thread-safely model those as actors and share their links between actors and tasks alike. Each call to a link is a communication to an actor (instead of a concurrent access to a variable). See [How to (not) share variables](../howto/share.md) for a receipt.

In the Actors documentation there are many examples on how actors represent variables and get shared between actors and tasks:

- In the [table-tennis](@ref table-tennis) example player actors working on different threads share a print server actor controlling access to the `stdio` variable.
- In the [Dict-server](@ref dict-server) example a `Dict` variable gets served by an actor to tasks on parallel threads or workers.
- In the [Dining Philosophers](../examples/dining_phil.md) problem the shared chopsticks are expressed as actors. This avoids races and starvation between the philosopher actors.
- In the [Producer-Consumer](../examples/prod_cons.md) problem producers and consumers share a buffer modeled as an actor.
- You can wrap mutable variables into a [`:guard`](https://github.com/JuliaActors/Guards.jl) actor, which will manage access to them.
- In more complicated cases of resource sharing you can use a [`:genserver`](https://github.com/JuliaActors/GenServers.jl) actor.

To model concurrently shared objects or data as actors is a common and successful pattern in actor programming. It makes it easier to write clear, correct concurrent programs. Unlike common tasks or also shared variables, actors are particularly suitable for this modeling because

1. they are persistent objects like the variables or objects they represent and
2. they can express a behavior of those objects.

## State Machine Behavior (gen_statem)

For complex behaviors that involve multiple states, `Actors` provides a state machine behavior inspired by Erlang/OTP's `gen_statem`. This is particularly useful for:

- Protocol handlers (HTTP, TCP, custom protocols)
- Workflow engines
- Game state management
- Device controllers
- Any system with well-defined states and transitions

### Creating a State Machine

A state machine is created with three functions:
1. `init()` - returns initial state and data
2. `handle_event(state, event, data)` - handles events and returns `(new_state, new_data, actions)`
3. `terminate(state, reason, data)` - optional cleanup function

```@example statem
using Actors
import Actors: spawn

# Traffic light state machine
function light_init()
    return (:green, Dict{Symbol,Any}())  # (initial_state, initial_data)
end

function light_handle_event(state, event, data)
    if event == :timer
        if state == :green
            return (:yellow, data, [])
        elseif state == :yellow
            return (:red, data, [])
        elseif state == :red
            return (:green, data, [])
        end
    end
    return (state, data, [])  # no change
end

light_sm = StateMachine(light_init, light_handle_event)
lk = spawn(light_sm, mode=:statem)

# Query current state
current = call(lk, :ping)  # returns :green

# Trigger transitions
cast(lk, :timer)
sleep(0.01)
current = call(lk, :ping)  # returns :yellow

exit!(lk)
```

### State Machine Actions

The `handle_event` function can return actions as the third element of the tuple:

```julia
# Timeout action - transition to :timeout event after 5 seconds
return (:waiting, data, [(:timeout, 5.0, :timeout_event)])

# Reply action - send a reply to the caller
return (:processed, data, [(:reply, :done)])

# Next event action - queue another event
return (:continue, data, [(:next_event, :do_more)])

# Stop action - terminate the state machine
return (:done, data, [:stop])

# Multiple actions
return (:next, data, [(:reply, :ok), (:timeout, 1.0, :tick)])
```

### Helper Functions

From inside a state machine, you can access:

```@docs
statem_state
statem_data
```

### Example: Counter State Machine

```@example statem
function counter_init()
    return (:idle, 0)
end

function counter_handle_event(state, event, data)
    if state == :idle
        if event == :start
            return (:counting, 0, [])
        end
    elseif state == :counting
        if event == :increment
            return (:counting, data + 1, [])
        elseif event == :stop
            return (:idle, data, [(:reply, data)])
        end
    end
    return (state, data, [])
end

counter = StateMachine(counter_init, counter_handle_event)
lk = spawn(counter, mode=:statem)

cast(lk, :start)
for i in 1:10
    cast(lk, :increment)
end
result = call(lk, :stop)  # returns 10

exit!(lk)
```

## Event Manager Behavior (gen_event)

The Event Manager provides a way to handle events with multiple, dynamically added handlers. This is inspired by Erlang/OTP's `gen_event` and is useful for:

- Logging systems with multiple log handlers
- Pub/sub patterns
- Event notification systems
- Plugin architectures

### Creating an Event Manager

```@example event
using Actors
import Actors: spawn

# Create event manager
em = event_manager()

# Add a handler that logs events
add_handler(em, :logger,
    () -> [],  # initial state: empty list
    (event, state) -> begin
        push!(state, event)
        (state, [])  # return (new_state, actions)
    end
)

sleep(0.05)  # let handler initialize

# Send events to all handlers
send_event(em, :user_login)
send_event(em, :file_upload)
send_event(em, :user_logout)

exit!(em)
```

### Event Handler API

```@docs
EventHandler
```

```@docs
add_handler(lk::Link, id::Symbol, init::Function, handle_event::Function; handle_call, terminate)
add_handler(lk::Link, handler::EventHandler)
```

```@docs
delete_handler
send_event
call_handler
which_handlers
event_manager
```

### Handler State Management

Each handler maintains its own state:

```@example event
em = event_manager()

# Counter handler
add_handler(em, :counter,
    () -> 0,
    (event, state) -> begin
        event == :increment && return (state + 1, [])
        event == :reset && return (0, [])
        (state, [])
    end;
    handle_call = (request, state) -> begin
        request == :get && return (state, state)
        (:ok, state)
    end
)

sleep(0.05)

send_event(em, :increment)
send_event(em, :increment)
send_event(em, :increment)

count = call_handler(em, :counter, :get)  # returns 3

exit!(em)
```

### Multiple Handlers

An event manager can have multiple handlers that all receive the same events:

```@example event
em = event_manager()

# Logger handler
add_handler(em, :logger,
    () -> [],
    (event, state) -> (push!(state, event); (state, []))
)

# Metrics handler
add_handler(em, :metrics,
    () -> Dict{Symbol,Int}(),
    (event, state) -> begin
        state[event] = get(state, event, 0) + 1
        (state, [])
    end
)

sleep(0.05)

send_event(em, :click)
send_event(em, :click)
send_event(em, :view)

handlers = which_handlers(em)  # [:logger, :metrics]

exit!(em)
```

### Error Isolation

Handlers are isolated from each other - an error in one handler doesn't affect others:

```@example event
em = event_manager()

# Faulty handler
add_handler(em, :faulty,
    () -> nothing,
    (event, state) -> begin
        event == :boom && error("Handler error!")
        (state, [])
    end
)

# Healthy handler
healthy_state = Ref(0)
add_handler(em, :healthy,
    () -> healthy_state,
    (event, state) -> begin
        state[] += 1
        (state, [])
    end
)

sleep(0.05)

send_event(em, :boom)  # faulty handler errors, but healthy continues
send_event(em, :ok)

sleep(0.05)
# healthy_state[] == 2

exit!(em)
```

[^1]: [Hewitt, Meijer and Szyperski: The Actor Model (everything you wanted to know, but were afraid to ask)](http://channel9.msdn.com/Shows/Going+Deep/Hewitt-Meijer-and-Szyperski-The-Actor-Model-everything-you-wanted-to-know-but-were-afraid-to-ask), Microsoft Channel 9. April 9, 2012.
[^2]: Carl Hewitt. Actor Model of Computation: Scalable Robust Information Systems.- [arXiv:1008.1459](https://arxiv.org/abs/1008.1459).
[^3]: Gul Agha 1986. *Actors. a model of concurrent computation in distributed systems*, MIT.- p. 30
