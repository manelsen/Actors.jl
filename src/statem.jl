#
# This file is part of the Actors.jl Julia package,
# MIT license, part of https://github.com/JuliaActors
#

"""
    StateMachine

A generic state machine behavior inspired by Erlang/OTP's gen_statem.

Provides a structured way to implement finite state machines with:
- State enter/exit callbacks
- Event handling per state
- Timeout support per state
- Transition actions

# Example

```julia
# Traffic light state machine
function light_init()
    return (:green, Dict{Symbol,Any}())
end

function light_handle_event(state, event, data)
    if state == :green
        if event == :timer
            return (:yellow, data, [])
        end
    elseif state == :yellow
        if event == :timer
            return (:red, data, [])
        end
    elseif state == :red
        if event == :timer
            return (:green, data, [])
        end
    end
    return (state, data, [])
end

light_sm = StateMachine(light_init, light_handle_event)
lk = spawn(light_sm, mode=:statem)
cast(lk, :timer)  # green -> yellow
cast(lk, :timer)  # yellow -> red
```
"""
struct StateMachine
    init::Function
    handle_event::Function
    terminate::Union{Function,Nothing}
    
    function StateMachine(init::Function, handle_event::Function; terminate::Union{Function,Nothing}=nothing)
        new(init, handle_event, terminate)
    end
end

StateMachine(init::Function) = StateMachine(init, (s, e, d) -> (s, d, []))

mutable struct StateMachineData
    state::Symbol
    data::Any
    timer::Union{Timer,Nothing}
end

StateMachineData(state::Symbol, data) = StateMachineData(state, data, nothing)

const STATEM_KEY = :_statem_data

function onmessage(A::_ACT, mode::Val{:statem}, msg::Msg)
    sm = A.bhv
    if sm isa StateMachine
        onmessage_statem(A, sm, msg)
    else
        onmessage(A, msg)
    end
end

function onmessage_statem(A::_ACT, sm::StateMachine, msg::Msg)
    if !haskey(task_local_storage(), STATEM_KEY)
        result = sm.init()
        if result isa Tuple && length(result) >= 2
            init_state, init_data = result[1], result[2]
        else
            init_state = result
            init_data = nothing
        end
        task_local_storage(STATEM_KEY, StateMachineData(init_state, init_data))
    end
    
    sd = task_local_storage(STATEM_KEY)::StateMachineData
    
    event = if msg isa Cast
        x = msg.x
        isempty(x) ? nothing : first(x)
    elseif msg isa Call
        x = msg.x
        isempty(x) ? nothing : first(x)
    else
        msg
    end
    
    result = Base.invokelatest(sm.handle_event, sd.state, event, sd.data)
    
    if result isa Tuple && length(result) >= 3
        new_state, new_data, actions = result[1], result[2], result[3]
    elseif result isa Tuple && length(result) >= 2
        new_state, new_data = result[1], result[2]
        actions = []
    else
        new_state = result
        new_data = sd.data
        actions = []
    end
    
    if new_state != sd.state
        if !isnothing(sd.timer)
            close(sd.timer)
        end
        new_timer = nothing
        for action in actions
            if action isa Tuple && first(action) == :timeout
                timeout_sec = action[2]
                timeout_event = length(action) >= 3 ? action[3] : :timeout
                new_timer = Timer(t -> send(A.self, Cast(timeout_event)), timeout_sec)
                break
            end
        end
        task_local_storage(STATEM_KEY, StateMachineData(new_state, new_data, new_timer))
    else
        if !isnothing(sd.timer)
            new_timer = sd.timer
        else
            new_timer = nothing
            for action in actions
                if action isa Tuple && first(action) == :timeout
                    timeout_sec = action[2]
                    timeout_event = length(action) >= 3 ? action[3] : :timeout
                    new_timer = Timer(t -> send(A.self, Cast(timeout_event)), timeout_sec)
                    break
                end
            end
        end
        task_local_storage(STATEM_KEY, StateMachineData(sd.state, new_data, new_timer))
    end
    
    if msg isa Call
        response = new_state
        send(msg.from, Response(response, A.self))
    end
    
    for action in actions
        if action == :stop
            if !isnothing(sm.terminate)
                sm.terminate(new_state, :normal, new_data)
            end
            exit!(A.self, :normal)
            break
        elseif action isa Tuple && first(action) == :reply
            if msg isa Call
                send(msg.from, Response(action[2], A.self))
            end
        elseif action isa Tuple && first(action) == :next_event
            send(A.self, Cast(action[2]))
        end
    end
    
    A.res = new_state
end

function statem_state()
    sd = task_local_storage(STATEM_KEY)::StateMachineData
    return sd.state
end

function statem_data()
    sd = task_local_storage(STATEM_KEY)::StateMachineData
    return sd.data
end

statem(sm::StateMachine) = sm
