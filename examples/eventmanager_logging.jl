#
# This file is part of the Actors.jl Julia package,
# MIT license, part of https://github.com/JuliaActors
#

# Event Manager Logging Example
# Demonstrates event manager with multiple handlers

using Actors
import Actors: spawn

println("=== Event Manager Logging Example ===\n")

em = event_manager()

# Logger handler - stores all events
add_handler(em, :logger,
    () -> [],
    (event, state) -> begin
        push!(state, event)
        (state, [])
    end;
    handle_call = (request, state) -> begin
        if request == :get_events
            return (copy(state), state)
        elseif request == :clear
            return ([], [])
        end
        (:unknown_request, state)
    end
)

# Counter handler - counts events
add_handler(em, :counter,
    () -> Dict{Symbol,Int}(),
    (event, state) -> begin
        key = event isa Symbol ? event : :unknown
        state[key] = get(state, key, 0) + 1
        (state, [])
    end;
    handle_call = (request, state) -> begin
        request == :get_counts && return (copy(state), state)
        (:unknown_request, state)
    end
)

# Printer handler - prints events
add_handler(em, :printer,
    () -> nothing,
    (event, state) -> begin
        println("  [Printer] Received event: $event")
        (state, [])
    end
)

sleep(0.1)

println("Sending events:\n")

send_event(em, :startup)
send_event(em, :user_login)
send_event(em, :user_login)
send_event(em, :file_upload)
send_event(em, :user_login)
send_event(em, :file_download)
send_event(em, :shutdown)

sleep(0.2)

println("\n--- Querying handlers ---\n")

println("Handlers: ", which_handlers(em))

events = call_handler(em, :logger, :get_events)
println("\nLogged events ($n): $n")
println("  ", events)

counts = call_handler(em, :counter, :get_counts)
println("\nEvent counts:")
for (event, count) in sort(collect(counts), by=x->x[2], rev=true)
    println("  $event: $count")
end

println("\nClearing logger...")
call_handler(em, :logger, :clear)

events_after = call_handler(em, :logger, :get_events)
println("Events after clear: $n")

println("\nRemoving printer handler...")
delete_handler(em, :printer)

println("\nSending more events (printer removed):")
send_event(em, :test_event)
sleep(0.1)

println("\nHandlers after removal: ", which_handlers(em))

exit!(em)
println("\nEvent manager stopped.")
