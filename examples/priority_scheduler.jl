#
# This file is part of the Actors.jl Julia package,
# MIT license, part of https://github.com/JuliaActors
#

# Priority Task Scheduler Example
# Demonstrates practical use of priority messages in a task scheduler

using Actors
import Actors: spawn

println("=== Priority Task Scheduler Example ===\n")

# Priority constants
const SHUTDOWN = 100
const CRITICAL = 50
const HIGH = 10
const NORMAL = 0
const LOW = -10

# Task types
struct Task
    name::String
    priority::Int
end

processed_tasks = Task[]

lk = newPriorityLink(100)

scheduler = Task(() -> begin
    while true
        task = take!(lk.chn)
        if task == :shutdown
            println("[Scheduler] Shutdown signal received")
            break
        end
        push!(processed_tasks, task)
        println("[Scheduler] Processing: $(task.name) (priority=$(task.priority))")
    end
end)
schedule(scheduler)

sleep(0.1)

println("Submitting tasks to scheduler:\n")

# Submit tasks in random order
send_priority(lk, Task("Background cleanup", LOW), LOW)
send_priority(lk, Task("User request #1", NORMAL), NORMAL)
send_priority(lk, Task("Database reconnect", CRITICAL), CRITICAL)
send_priority(lk, Task("User request #2", NORMAL), NORMAL)
send_priority(lk, Task("Cache refresh", LOW), LOW)
send_priority(lk, Task("Handle timeout", HIGH), HIGH)
send_priority(lk, Task("User request #3", NORMAL), NORMAL)
send_priority(lk, Task("System health check", HIGH), HIGH)

sleep(0.3)

println("\nSending shutdown signal...\n")
send_priority(lk, :shutdown, SHUTDOWN)
sleep(0.1)

println("\n--- Task Processing Summary ---\n")

println("Tasks processed in priority order:")
for (i, task) in enumerate(processed_tasks)
    println("  $i. $(task.name) [priority=$(task.priority)]")
end

println("\n--- Statistics ---\n")

critical_count = count(t -> t.priority == CRITICAL, processed_tasks)
high_count = count(t -> t.priority == HIGH, processed_tasks)
normal_count = count(t -> t.priority == NORMAL, processed_tasks)
low_count = count(t -> t.priority == LOW, processed_tasks)

println("Critical tasks: $critical_count")
println("High tasks: $high_count")
println("Normal tasks: $normal_count")
println("Low tasks: $low_count")

if critical_count > 0
    first_critical_idx = findfirst(t -> t.priority == CRITICAL, processed_tasks)
    println("\nFirst critical task processed at position: $first_critical_idx (should be 1)")
end

println("\nPriority-based scheduling ensures critical tasks are never delayed by normal tasks!")

close(lk.chn)
println("\nTask scheduler stopped.")
