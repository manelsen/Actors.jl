# Priority Messages API

```@meta
CurrentModule = Actors
```

Priority messages allow you to control the order in which messages are processed by an actor. Messages with higher priority values are processed before messages with lower priority values.

## Overview

The priority message system consists of:
- `PriorityMsg` - A wrapper that adds priority to any message
- `PriorityChannel` - A channel that delivers messages by priority (highest first)
- Helper functions for sending priority messages

## Types

```@docs
PriorityMsg
PriorityChannel
```

## Internal Types

```@docs
Actors.PriorityEntry
```

## Sending Priority Messages

```@docs
send_priority
send_high
send_low
```

## Creating Priority Links

```@docs
newPriorityLink
```

## Usage Examples

### Basic Priority Ordering

```jldoctest
julia> using Actors

julia> ch = PriorityChannel(10);

julia> put!(ch, :normal);          # priority 0 (default)

julia> put!(ch, PriorityMsg(:urgent, 10));  # high priority

julia> put!(ch, PriorityMsg(:low, -5));     # low priority

julia> take!(ch)
:urgent

julia> take!(ch)
:normal

julia> take!(ch)
:low
```

### Using Priority Links

```jldoctest
julia> using Actors
julia> import Actors: spawn

julia> # Create a link with PriorityChannel
       lk = newPriorityLink(32);

julia> # Messages will be processed by priority
       send_low(lk, :background_task);

julia> send_high(lk, :urgent_task);

julia> cast(lk, :normal_task);

julia> close(lk.chn);
```

### Priority with Actors

```julia
using Actors
import Actors: spawn

# Actor that logs message order
processed = []

lk = newPriorityLink(32)
t = Task(() -> begin
    while true
        msg = take!(lk.chn)
        msg == :stop && break
        push!(processed, msg)
    end
end)
schedule(t)

# Send messages with different priorities
send_low(lk, :low1)
cast(lk, :normal1)
send_high(lk, :high1)
cast(lk, :normal2)
send_low(lk, :low2)
send_high(lk, :high2)

sleep(0.1)

# processed will be: [:high1, :high2, :normal1, :normal2, :low1, :low2]

put!(lk.chn, :stop)
```

### Practical Example: Task Scheduler

```julia
using Actors
import Actors: spawn

function task_scheduler()
    lk = newPriorityLink(100)
    
    # Priority levels:
    #  100: system shutdown
    #   50: critical system tasks
    #   10: high priority user tasks
    #    0: normal tasks (default)
    #  -10: low priority background tasks
    
    scheduler = Task(() -> begin
        while true
            task = take!(lk.chn)
            task == :shutdown && break
            # Process task...
            println("Processing: ", task)
        end
    end)
    
    schedule(scheduler)
    
    # API functions
    shutdown!() = send_priority(lk, :shutdown, 100)
    critical!(task) = send_priority(lk, task, 50)
    high!(task) = send_high(lk, task)
    normal!(task) = cast(lk, task)
    low!(task) = send_low(lk, task)
    
    return (shutdown!, critical!, high!, normal!, low!)
end

(shutdown!, critical!, high!, normal!, low!) = task_scheduler()

# Tasks will be processed in priority order
low!(:cleanup_temp_files)
normal!(:process_user_request)
high!(:handle_timeout)
critical!(:database_reconnect)
shutdown!()
```

## Performance Characteristics

- **Insertion**: O(log n) - heap insertion
- **Extraction**: O(log n) - heap extraction  
- **Space**: O(n) where n is channel capacity
- **Thread safety**: Fully thread-safe with locks

The implementation uses a max-heap (binary heap) where:
- Root element is always the highest priority message
- FIFO ordering is maintained within same priority using a counter
- Lock-based synchronization ensures thread safety

## Implementation Details

### Priority Ordering

Messages are ordered by:
1. **Priority value** (higher values first)
2. **Counter** (lower counter = earlier arrival, for FIFO within same priority)

This ensures that:
- Urgent messages are always processed first
- Messages with the same priority are processed in arrival order (FIFO)
- No starvation - even low priority messages will eventually be processed

### Max-Heap Structure

```
           [P=10, C=1]
          /           \
    [P=5, C=2]       [P=8, C=3]
    /       \
[P=1, C=4] [P=3, C=5]

P = Priority, C = Counter
```

- `put!` adds to the end and sifts up
- `take!` removes root, moves last to root, sifts down
- Both operations are O(log n)

### Comparison with Regular Channel

| Feature | Channel | PriorityChannel |
|---------|---------|-----------------|
| Ordering | FIFO | Priority + FIFO |
| Insertion | O(1) amortized | O(log n) |
| Extraction | O(1) | O(log n) |
| Memory | O(n) | O(n) |
| Thread safe | Yes | Yes |

Use `PriorityChannel` when:
- Some messages are more urgent than others
- You need to process system messages before user messages
- Real-time requirements demand priority handling

Use regular `Channel` when:
- All messages are equally important
- FIFO ordering is sufficient
- Maximum throughput is needed

## Best Practices

1. **Use meaningful priority values**:
   ```julia
   const SYSTEM_SHUTDOWN = 100
   const CRITICAL = 50
   const HIGH = 10
   const NORMAL = 0
   const LOW = -10
   const BACKGROUND = -20
   ```

2. **Don't overuse priorities**:
   - Too many priority levels can lead to complex debugging
   - 3-5 levels are usually sufficient

3. **Beware of priority inversion**:
   - A low-priority task holding a resource needed by a high-priority task
   - Use priority inheritance if this becomes an issue

4. **Test priority behavior**:
   - Verify that high-priority messages are indeed processed first
   - Test with mixed workloads

5. **Monitor for starvation**:
   - Ensure low-priority messages eventually get processed
   - Consider periodic priority boosts if needed
