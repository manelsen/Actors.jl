#
# This file is part of the Actors.jl Julia package,
# MIT license, part of https://github.com/JuliaActors
#

# Traffic Light State Machine Example
# Demonstrates finite state machine pattern using StateMachine

using Actors
import Actors: spawn

println("=== Traffic Light State Machine Example ===\n")

function traffic_light_init()
    return (:green, Dict{Symbol,Any}(:duration => 5))
end

function traffic_light_handle_event(state, event, data)
    if event == :timer
        if state == :green
            println("🟢 Green -> Yellow")
            return (:yellow, data, [])
        elseif state == :yellow
            println("🟡 Yellow -> Red")
            return (:red, data, [])
        elseif state == :red
            println("🔴 Red -> Green")
            return (:green, data, [])
        end
    elseif event == :get_state
        return (state, data, [(:reply, state)])
    elseif event == :get_duration
        return (state, data, [(:reply, data[:duration])])
    end
    return (state, data, [])
end

traffic_light = StateMachine(traffic_light_init, traffic_light_handle_event)
lk = spawn(traffic_light, mode=:statem)

println("Initial state: ", call(lk, :get_state))
println("Duration setting: ", call(lk, :get_duration), " seconds\n")

println("Cycling through states:")
for i in 1:3
    cast(lk, :timer)
    sleep(0.1)
end

println("\nFinal state: ", call(lk, :get_state))

exit!(lk)
println("\nTraffic light stopped.")
