#
# This file is part of the Actors.jl Julia package,
# MIT license, part of https://github.com/JuliaActors
#

# Event Manager Pub/Sub Example
# Demonstrates publish-subscribe pattern using EventManager

using Actors
import Actors: spawn

println("=== Event Manager Pub/Sub Example ===\n")

em = event_manager()

# Subscriber 1 - interested in :news and :alerts
add_handler(em, :subscriber1,
    () -> [],
    (event, state) -> begin
        if event isa Tuple && first(event) in [:news, :alerts]
            push!(state, event)
            println("  [Subscriber1] Received: ", event)
        end
        (state, [])
    end;
    handle_call = (request, state) -> begin
        request == :get_messages && return (copy(state), state)
        (:unknown, state)
    end
)

# Subscriber 2 - interested in everything
add_handler(em, :subscriber2,
    () -> [],
    (event, state) -> begin
        push!(state, event)
        println("  [Subscriber2] Received: ", event)
        (state, [])
    end;
    handle_call = (request, state) -> begin
        request == :get_messages && return (copy(state), state)
        (:unknown, state)
    end
)

# Subscriber 3 - only interested in :alerts
add_handler(em, :subscriber3,
    () -> [],
    (event, state) -> begin
        if event isa Tuple && first(event) == :alerts
            push!(state, event)
            println("  [Subscriber3] URGENT: ", event)
        end
        (state, [])
    end;
    handle_call = (request, state) -> begin
        request == :get_messages && return (copy(state), state)
        (:unknown, state)
    end
)

sleep(0.1)

println("Publishing events:\n")

# Publish news
send_event(em, (:news, "Julia 1.13 released!"))
send_event(em, (:news, "Actors.jl v0.3.0 available"))
sleep(0.1)

# Publish alerts
send_event(em, (:alerts, "System overload detected"))
send_event(em, (:alerts, "Database connection lost"))
sleep(0.1)

# Publish other events
send_event(em, (:sports, "Team wins championship"))
send_event(em, (:weather, "Sunny day ahead"))
sleep(0.1)

println("\n--- Subscriber Statistics ---\n")

msg1 = call_handler(em, :subscriber1, :get_messages)
println("Subscriber1 received $(n) messages")

msg2 = call_handler(em, :subscriber2, :get_messages)
println("Subscriber2 received $(n) messages")

msg3 = call_handler(em, :subscriber3, :get_messages)
println("Subscriber3 received $(n) messages")

println("\nUnsubscribing Subscriber2...")
delete_handler(em, :subscriber2)

println("\nPublishing more events:")
send_event(em, (:alerts, "Service restored"))
send_event(em, (:news, "System back online"))
sleep(0.1)

println("\n--- Final Statistics ---\n")

msg1_final = call_handler(em, :subscriber1, :get_messages)
println("Subscriber1 total messages: $n")

msg3_final = call_handler(em, :subscriber3, :get_messages)
println("Subscriber3 total messages: $n")

exit!(em)
println("\nPub/sub system stopped.")
