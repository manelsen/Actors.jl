#
# This file is part of the Actors.jl Julia package,
# MIT license, part of https://github.com/JuliaActors
#

"""
    PriorityMsg(msg, priority::Int=0)

A wrapper that adds priority to any message.

Messages with higher priority values are processed first.
Default priority is 0 (normal). Use negative for low priority,
positive for high priority.

# Example
```julia
send(lk, PriorityMsg(:urgent, 10))   # high priority
send(lk, PriorityMsg(:normal, 0))    # normal (default)
send(lk, PriorityMsg(:low, -5))      # low priority
```
"""
struct PriorityMsg
    msg::Any
    priority::Int
end

PriorityMsg(msg) = PriorityMsg(msg, 0)

Base.isless(a::PriorityMsg, b::PriorityMsg) = a.priority < b.priority

"""
    PriorityEntry

Internal structure for priority queue entries.
Uses counter to maintain FIFO order within same priority.
Higher priority values are processed first (max-heap behavior).
"""
struct PriorityEntry
    priority::Int
    counter::Int
    msg::Any
end

function _entry_gt(a::PriorityEntry, b::PriorityEntry)
    if a.priority == b.priority
        return a.counter < b.counter  # Earlier counter = processed first (FIFO)
    else
        return a.priority > b.priority  # Higher priority value = processed first
    end
end

"""
    PriorityChannel{T}(sz::Int)

A channel that delivers messages by priority (highest first).

Messages are wrapped in `PriorityMsg` to specify priority.
Within the same priority, FIFO order is maintained.
"""
mutable struct PriorityChannel{T}
    data::Vector{PriorityEntry}
    sz_max::Int
    counter::Int
    lock::ReentrantLock
    cond_take::Threads.Condition
    cond_put::Threads.Condition
    state::Symbol
    
    function PriorityChannel{T}(sz::Int) where T
        sz = max(1, sz)
        lock = ReentrantLock()
        new{T}(
            PriorityEntry[],
            sz,
            0,
            lock,
            Threads.Condition(lock),
            Threads.Condition(lock),
            :open
        )
    end
end

PriorityChannel(sz::Int=32) = PriorityChannel{Any}(sz)

Base.isready(ch::PriorityChannel) = !isempty(ch.data)
Base.isopen(ch::PriorityChannel) = ch.state == :open
Base.length(ch::PriorityChannel) = length(ch.data)
Base.isempty(ch::PriorityChannel) = isempty(ch.data)

function Base.close(ch::PriorityChannel)
    ch.state = :closed
    lock(ch.lock)
    try
        notify(ch.cond_take, nothing, true, false)
        notify(ch.cond_put, nothing, true, false)
    finally
        unlock(ch.lock)
    end
    return ch
end

function Base.put!(ch::PriorityChannel, msg)
    lock(ch.lock)
    try
        ch.state == :closed && throw(InvalidStateException("Channel is closed.", :closed))
        
        while length(ch.data) >= ch.sz_max
            ch.state == :closed && throw(InvalidStateException("Channel is closed.", :closed))
            wait(ch.cond_put)
        end
        
        priority = msg isa PriorityMsg ? msg.priority : 0
        inner_msg = msg isa PriorityMsg ? msg.msg : msg
        
        ch.counter += 1
        entry = PriorityEntry(priority, ch.counter, inner_msg)
        
        push!(ch.data, entry)
        _siftup!(ch.data, length(ch.data))
        
        notify(ch.cond_take, nothing, true, false)
    finally
        unlock(ch.lock)
    end
    return msg
end

function Base.take!(ch::PriorityChannel)
    lock(ch.lock)
    try
        while isempty(ch.data)
            ch.state == :closed && throw(InvalidStateException("Channel is closed.", :closed))
            wait(ch.cond_take)
        end
        
        entry = _heappop!(ch.data)
        notify(ch.cond_put, nothing, true, false)
        return entry.msg
    finally
        unlock(ch.lock)
    end
end

function Base.fetch(ch::PriorityChannel)
    lock(ch.lock)
    try
        while isempty(ch.data)
            ch.state == :closed && throw(InvalidStateException("Channel is closed.", :closed))
            wait(ch.cond_take)
        end
        return first(ch.data).msg
    finally
        unlock(ch.lock)
    end
end

function _siftup!(heap::Vector{PriorityEntry}, idx::Int)
    while idx > 1
        parent = idx ÷ 2
        if _entry_gt(heap[idx], heap[parent])
            heap[idx], heap[parent] = heap[parent], heap[idx]
            idx = parent
        else
            break
        end
    end
end

function _siftdown!(heap::Vector{PriorityEntry}, idx::Int, len::Int)
    while true
        left = 2 * idx
        right = 2 * idx + 1
        largest = idx
        
        if left <= len && _entry_gt(heap[left], heap[largest])
            largest = left
        end
        if right <= len && _entry_gt(heap[right], heap[largest])
            largest = right
        end
        
        if largest != idx
            heap[idx], heap[largest] = heap[largest], heap[idx]
            idx = largest
        else
            break
        end
    end
end

function _heappop!(heap::Vector{PriorityEntry})
    len = length(heap)
    len == 0 && throw(ArgumentError("heap is empty"))
    
    result = heap[1]
    heap[1] = heap[len]
    pop!(heap)
    
    if len > 1
        _siftdown!(heap, 1, len - 1)
    end
    
    return result
end

"""
    send_priority(lk::Link, msg, priority::Int)

Send a message with a specific priority.

- Higher priority values are processed first
- Default priority is 0
- Use positive for high priority, negative for low priority
"""
function send_priority(lk::Link, msg, priority::Int)
    pmsg = PriorityMsg(msg, priority)
    _send!(lk.chn, pmsg)
end

"""
    send_high(lk::Link, msg)

Send a high priority message (priority = 10).
"""
send_high(lk::Link, msg) = send_priority(lk, msg, 10)

"""
    send_low(lk::Link, msg)

Send a low priority message (priority = -10).
"""
send_low(lk::Link, msg) = send_priority(lk, msg, -10)

"""
    newPriorityLink(size=32; pid=myid(), mode=nothing)

Create a Link with a PriorityChannel instead of a regular Channel.
"""
function newPriorityLink(size=32; pid=myid(), mode=nothing)
    isnothing(mode) && (mode = :priority)
    return Link(PriorityChannel(max(1, size)), pid, mode)
end

function _send!(chn::PriorityChannel, msg)
    lock(chn.lock)
    try
        chn.state == :closed && throw(InvalidStateException("Channel is closed.", :closed))
        
        while length(chn.data) >= chn.sz_max
            chn.state == :closed && throw(InvalidStateException("Channel is closed.", :closed))
            wait(chn.cond_put)
        end
        
        priority = msg isa PriorityMsg ? msg.priority : 0
        inner_msg = msg isa PriorityMsg ? msg.msg : msg
        
        chn.counter += 1
        entry = PriorityEntry(priority, chn.counter, inner_msg)
        
        push!(chn.data, entry)
        _siftup!(chn.data, length(chn.data))
        
        notify(chn.cond_take, nothing, true, false)
    finally
        unlock(chn.lock)
    end
    return msg
end
