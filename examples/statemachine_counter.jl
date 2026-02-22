#
# This file is part of the Actors.jl Julia package,
# MIT license, part of https://github.com/JuliaActors
#

# Counter State Machine Example
# Demonstrates state machine with data persistence and multiple transitions

using Actors
import Actors: spawn

println("=== Counter State Machine Example ===\n")

function counter_init()
    return (:idle, 0)
end

function counter_handle_event(state, event, data)
    if state == :idle
        if event == :start
            println("Starting counter at 0")
            return (:counting, 0, [])
        end
    elseif state == :counting
        if event == :increment
            new_count = data + 1
            println("  Incrementing: $data -> $new_count")
            return (:counting, new_count, [])
        elseif event == :decrement
            new_count = max(0, data - 1)
            println("  Decrementing: $data -> $new_count")
            return (:counting, new_count, [])
        elseif event == :reset
            println("  Resetting to 0")
            return (:counting, 0, [])
        elseif event == :stop
            println("Stopping counter at $data")
            return (:idle, data, [(:reply, data)])
        elseif event == :get_count
            return (:counting, data, [(:reply, data)])
        end
    end
    return (state, data, [])
end

counter = StateMachine(counter_init, counter_handle_event)
lk = spawn(counter, mode=:statem)

println("Starting state machine...")
cast(lk, :start)
sleep(0.05)

println("\nIncrementing 5 times:")
for i in 1:5
    cast(lk, :increment)
    sleep(0.02)
end

count = call(lk, :get_count)
println("\nCurrent count: $count")

println("\nDecrementing 2 times:")
for i in 1:2
    cast(lk, :decrement)
    sleep(0.02)
end

count = call(lk, :get_count)
println("\nCurrent count: $count")

println("\nResetting...")
cast(lk, :reset)
sleep(0.05)

println("\nIncrementing 3 times:")
for i in 1:3
    cast(lk, :increment)
    sleep(0.02)
end

final_count = call(lk, :stop)
println("\nFinal count: $final_count")

exit!(lk)
println("\nCounter stopped.")
