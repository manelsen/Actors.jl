#
# This file is part of the Actors.jl Julia package,
# MIT license, part of https://github.com/JuliaActors
#

"""
    EventHandler

A handler that processes events in an EventManager.

# Fields
- `id::Symbol`: unique identifier for this handler
- `init::Function`: called when handler is added, returns initial state
- `handle_event::Function`: called for each event, receives (event, state)
- `handle_call::Function`: called for synchronous calls, receives (request, state)
- `terminate::Union{Function,Nothing}`: called when handler is removed
- `state::Any`: current handler state
"""
mutable struct EventHandler
    id::Symbol
    init::Function
    handle_event::Function
    handle_call::Function
    terminate::Union{Function,Nothing}
    state::Any
end

"""
    EventHandler(id, init, handle_event; handle_call, terminate)

Create a new event handler.

# Arguments
- `id::Symbol`: unique identifier
- `init::Function`: `() -> initial_state` or `(args...) -> initial_state`
- `handle_event::Function`: `(event, state) -> (new_state, actions)`
- `handle_call::Function`: `(request, state) -> (response, new_state)`
- `terminate::Union{Function,Nothing}`: `(state, reason) -> nothing`

# Example
```julia
handler = EventHandler(
    :logger,
    () -> [],
    (event, state) -> begin
        push!(state, event)
        (state, [])
    end
)
```
"""
function EventHandler(id::Symbol, init::Function, handle_event::Function;
                      handle_call::Function=(req, s) -> (:ok, s),
                      terminate::Union{Function,Nothing}=nothing)
    EventHandler(id, init, handle_event, handle_call, terminate, nothing)
end

"""
    EventManager

A generic event manager inspired by Erlang/OTP's gen_event.

Manages multiple event handlers that can be added/removed dynamically.
Each event is broadcast to all handlers.

# Features
- Add/remove handlers dynamically
- Broadcast events to all handlers
- Synchronous calls to specific handlers
- Handler-specific state

# Example
```julia
# Create event manager
em = EventManager()
lk = spawn(em, mode=:event)

# Add a handler
add_handler(lk, :logger, () -> [], (e, s) -> (push!(s, e); (s, [])))

# Notify all handlers of an event
notify(lk, :something_happened)

# Call a specific handler
response = call_handler(lk, :logger, :get_events)
```
"""
struct EventManager
    handlers::Dict{Symbol, EventHandler}
    
    EventManager() = new(Dict{Symbol, EventHandler}())
end

const EVENTM_KEY = :_eventm_data

function init_event_manager()
    task_local_storage(EVENTM_KEY, EventManager())
end

function get_event_manager()
    if !haskey(task_local_storage(), EVENTM_KEY)
        init_event_manager()
    end
    task_local_storage(EVENTM_KEY)::EventManager
end

function onmessage(A::_ACT, mode::Val{:event}, msg::Msg)
    em = get_event_manager()
    
    if msg isa Cast
        event = isempty(msg.x) ? nothing : first(msg.x)
        
        if event isa Tuple && first(event) == :add_handler
            handler_spec = event[2]
            handler_args = length(event) >= 3 ? event[3] : ()
            add_handler_impl(em, handler_spec, handler_args)
            
        elseif event isa Tuple && first(event) == :delete_handler
            handler_id = event[2]
            delete_handler_impl(em, handler_id)
            
        elseif event isa Tuple && first(event) == :notify
            event_data = event[2]
            notify_impl(em, event_data)
            
        else
            notify_impl(em, event)
        end
        A.res = :ok
        
    elseif msg isa Call
        request = isempty(msg.x) ? nothing : first(msg.x)
        
        if request isa Tuple && first(request) == :call_handler
            handler_id = request[2]
            call_request = length(request) >= 3 ? request[3] : nothing
            response = call_handler_impl(em, handler_id, call_request)
            send(msg.from, Response(response, A.self))
            A.res = response
            
        elseif request isa Tuple && first(request) == :which_handlers
            response = collect(keys(em.handlers))
            send(msg.from, Response(response, A.self))
            A.res = response
            
        else
            response = notify_impl(em, request)
            send(msg.from, Response(:ok, A.self))
            A.res = :ok
        end
        
    else
        notify_impl(em, msg)
        A.res = :ok
    end
end

function add_handler_impl(em::EventManager, handler::EventHandler, args::Tuple=())
    state = isempty(args) ? Base.invokelatest(handler.init) : Base.invokelatest(handler.init, args...)
    handler.state = state
    em.handlers[handler.id] = handler
    return :ok
end

function add_handler_impl(em::EventManager, handler_spec::Tuple, args::Tuple=())
    id, init, handle_event = handler_spec[1], handler_spec[2], handler_spec[3]
    handle_call = length(handler_spec) >= 4 ? handler_spec[4] : (req, s) -> (:ok, s)
    terminate = length(handler_spec) >= 5 ? handler_spec[5] : nothing
    
    handler = EventHandler(id, init, handle_event; handle_call=handle_call, terminate=terminate)
    add_handler_impl(em, handler, args)
end

function delete_handler_impl(em::EventManager, handler_id::Symbol)
    if haskey(em.handlers, handler_id)
        handler = em.handlers[handler_id]
        if !isnothing(handler.terminate)
            handler.terminate(handler.state, :normal)
        end
        delete!(em.handlers, handler_id)
        return :ok
    end
    return :not_found
end

function notify_impl(em::EventManager, event)
    for (id, handler) in em.handlers
        try
            result = Base.invokelatest(handler.handle_event, event, handler.state)
            if result isa Tuple
                handler.state = result[1]
            else
                handler.state = result
            end
        catch e
            @warn "EventHandler $id threw error" exception=e
        end
    end
    return :ok
end

function call_handler_impl(em::EventManager, handler_id::Symbol, request)
    if !haskey(em.handlers, handler_id)
        return (:error, :handler_not_found)
    end
    
    handler = em.handlers[handler_id]
    result = Base.invokelatest(handler.handle_call, request, handler.state)
    
    if result isa Tuple && length(result) >= 2
        response, new_state = result[1], result[2]
        handler.state = new_state
        return response
    else
        handler.state = result
        return :ok
    end
end

"""
    add_handler(lk::Link, id::Symbol, init, handle_event; kwargs...)
    add_handler(lk::Link, handler::EventHandler)

Add an event handler to an event manager.

# Arguments
- `lk::Link`: event manager link
- `id::Symbol`: unique handler identifier
- `init`: function returning initial state
- `handle_event`: function `(event, state) -> (new_state, actions)`
- `handle_call`: function `(request, state) -> (response, new_state)`
- `terminate`: function `(state, reason) -> nothing`
"""
function add_handler(lk::Link, id::Symbol, init::Function, handle_event::Function;
                     handle_call::Function=(req, s) -> (:ok, s),
                     terminate::Union{Function,Nothing}=nothing)
    handler = EventHandler(id, init, handle_event; handle_call=handle_call, terminate=terminate)
    cast(lk, (:add_handler, handler))
end

add_handler(lk::Link, handler::EventHandler) = cast(lk, (:add_handler, handler))

"""
    delete_handler(lk::Link, id::Symbol)

Remove an event handler from an event manager.
"""
delete_handler(lk::Link, id::Symbol) = cast(lk, (:delete_handler, id))

"""
    send_event(lk::Link, event)

Send an event to all handlers in an event manager.
"""
send_event(lk::Link, event) = cast(lk, (:notify, event))

"""
    call_handler(lk::Link, id::Symbol, request)

Make a synchronous call to a specific handler.
"""
call_handler(lk::Link, id::Symbol, request) = call(lk, (:call_handler, id, request))

"""
    which_handlers(lk::Link)

Get a list of all handler IDs in an event manager.
"""
which_handlers(lk::Link) = call(lk, (:which_handlers,))

event_manager(; kwargs...) = spawn(EventManager, mode=:event; kwargs...)
