# Actors.jl

Concurrent computing in Julia with actors.

[![stable docs](https://img.shields.io/badge/docs-stable-blue.svg)](https://juliaactors.github.io/Actors.jl/stable/)
[![dev docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://JuliaActors.github.io/Actors.jl/dev)
![CI](https://github.com/JuliaActors/Actors.jl/workflows/CI/badge.svg)
[![Coverage](https://codecov.io/gh/JuliaActors/Actors.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/JuliaActors/Actors.jl)

`Actors` implements the [Actor Model](https://en.wikipedia.org/wiki/Actor_model) of computation:

> An actor ... in response to a message it receives, can concurrently:
>
> - send a finite number of messages to other actors;
> - create a finite number of new actors;
> - designate the behavior to be used for the next message it receives.

`Actors` makes concurrency easy to understand and reason about and integrates well with Julia's multi-threading and distributed computing. It provides an API for writing [reactive](https://www.reactivemanifesto.org) applications, that are:

- *responsive*: react to inputs and events,
- *message-driven*: rely on asynchronous message-passing,
- *resilient*: can cope with failures,
- *elastic*: can distribute load over multiple threads and workers.

## Requirements

- **Julia 1.12+**
- `ActorInterfaces.jl` for abstract interface

## Features

- **Simple yet powerful API**: `spawn`, `send`, `call`, `cast`, `request`, `become`
- **Fault tolerance**: Supervision trees, connection monitoring, error handling
- **Distributed computing**: Seamless support across workers
- **State machines**: Built-in `gen_statem` behavior
- **Event handling**: Built-in `gen_event` behavior
- **Priority messages**: Support for high-priority message handling
- **Checkpointing**: Hierarchical state persistence
- **Registry**: Global name service for actors
- **Type-stable**: Optimized for performance with Julia 1.12+

## Greeting Actors

The following example defines two behavior functions: `greet` and `hello` and spawns two actors with them. `sayhello` will forward a message to `greeter`, get a greeting string back and deliver it as a result:

```julia
julia> using Actors

julia> import Actors: spawn

julia> greet(greeting, msg) = greeting*", "*msg*"!" # a greetings server
greet (generic function with 1 method)

julia> hello(greeter, to) = request(greeter, to)    # a greetings client
hello (generic function with 1 method)

julia> greeter = spawn(greet, "Hello")              # start the server with a greet string
Link{Channel{Any}}(Channel{Any}(sz_max:32,sz_curr:0), 1, :default)

julia> sayhello = spawn(hello, greeter)             # start the client with a link to the server
Link{Channel{Any}}(Channel{Any}(sz_max:32,sz_curr:0), 1, :default)

julia> request(sayhello, "World")                   # request the client
"Hello, World!"

julia> request(sayhello, "Kermit")
"Hello, Kermit!"
```

Please look into [the manual](https://JuliaActors.github.io/Actors.jl/dev) for more information and more serious examples.

## Key Concepts

### Actors and Links

An **actor** is a Julia `Task` running a message-processing loop (`_act(ch::Channel)`). Each actor maintains its state in task-local storage.

A **link** (`Link{C}`) is the actor's mailbox - it wraps a `Channel` (local) or `RemoteChannel` (distributed) and serves as the actor's address.

### Message Passing

- **`send(lk, msg...)`**: Async, fire-and-forget messaging
- **`cast(lk, args...)`**: Async, triggers behavior without response
- **`call(lk, args...)`**: Sync request-response pattern
- **`request(lk, args...)`**: General blocking call
- **`receive(lk; timeout)`**: Receive with optional filtering

### State Management

- **`query(lk, field)`**: Read actor state (`:sta`, `:res`, `:bhv`, `:mode`, `:usr`)
- **`update!(lk, x; s=:sta)`**: Write actor state fields
- **`become!(lk, func, args...)`**: Change actor behavior dynamically

### Fault Tolerance

- **`connect(lk)` / `disconnect(lk)`**: Bidirectional links with automatic failure propagation
- **`monitor(lk, onsignal...)` / `demonitor(lk)`**: One-way failure observation
- **`trapExit(lk)`**: Make actor `:sticky` to absorb Exit signals
- **Supervisors**: Erlang-style supervision trees with strategies (`:one_for_one`, `:one_for_all`, `:rest_for_one`)

### Special Behaviors

- **`gen_statem`**: State machine behavior with automatic state transitions
- **`gen_event`**: Event manager pattern with multiple event handlers
- **Priority messages**: High-priority message handling support

## Documentation

- [Stable Documentation](https://juliaactors.github.io/Actors.jl/stable/)
- [Development Documentation](https://JuliaActors.github.io/Actors.jl/dev)
- [Tutorial](https://JuliaActors.github.io/Actors.jl/dev/tutorial/)
- [API Reference](https://JuliaActors.github.io/Actors.jl/dev/api/)
- [Examples](https://JuliaActors.github.io/Actors.jl/dev/examples/)

## Installation

```julia
using Pkg
Pkg.add("Actors")
```

## Contributing

`Actors` is part of the [JuliaActors](https://github.com/JuliaActors) GitHub organization. Contributions are welcome!

### Development Setup

```bash
# Clone the repository
git clone https://github.com/JuliaActors/Actors.jl.git
cd Actors.jl

# Run tests
julia --project -e 'using Pkg; Pkg.test()'

# Build documentation
julia --project=docs docs/make.jl
```

See [CLAUDE.md](CLAUDE.md) for detailed architecture and modernization notes.

## Authors

- Oliver Schulz (until v0.1, Oct 2017)
- Paul Bayer (rewrite since v0.1.1, Nov 2020)

## License

MIT
