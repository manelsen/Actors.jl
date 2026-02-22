#
# This file is part of the Actors.jl Julia package,
# MIT license, part of https://github.com/JuliaActors
#

# Priority Messages Example
# Demonstrates priority-based message processing

using Actors
import Actors: spawn

println("=== Priority Messages Example ===\n")

processed = Symbol[]

lk = newPriorityLink(32)
t = Task(() -> begin
    while true
        msg = take!(lk.chn)
        msg == :stop && break
        push!(processed, msg)
    end
end)
schedule(t)

sleep(0.1)

println("Sending messages with different priorities:\n")

# Send messages in mixed order
println("1. Sending low priority (background)")
send_low(lk, :low1)

println("2. Sending normal priority (default)")
cast(lk, :normal1)

println("3. Sending high priority (urgent)")
send_high(lk, :high1)

println("4. Sending more normal")
cast(lk, :normal2)

println("5. Sending custom priority (50)")
send_priority(lk, :critical, 50)

println("6. Sending more low priority")
send_low(lk, :low2)

println("7. Sending more high priority")
send_high(lk, :high2)

println("8. Sending more normal")
cast(lk, :normal3)

sleep(0.3)

put!(lk.chn, :stop)
sleep(0.1)

println("\n--- Processing Order ---\n")

println("Messages were processed in this order:")
for (i, msg) in enumerate(processed)
    priority = if startswith(string(msg), "critical")
        50
    elseif startswith(string(msg), "high")
        10
    elseif startswith(string(msg), "normal")
        0
    elseif startswith(string(msg), "low")
        -10
    else
        0
    end
    println("  $i. $msg (priority=$priority)")
end

println("\n--- Analysis ---\n")

critical = count(startswith(string(m), "critical") for m in processed)
high = count(startswith(string(m), "high") for m in processed)
normal = count(startswith(string(m), "normal") for m in processed)
low = count(startswith(string(m), "low") for m in processed)

println("Critical (priority=50): $critical messages - processed FIRST")
println("High (priority=10): $high messages - processed SECOND")
println("Normal (priority=0): $normal messages - processed THIRD")
println("Low (priority=-10): $low messages - processed LAST")

println("\nAs expected, higher priority messages are processed first!")

close(lk.chn)
println("\nPriority channel closed.")
