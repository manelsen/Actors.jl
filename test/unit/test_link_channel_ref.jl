#
# Unit Tests: Link and Channel Ref Semantics
# PURPOSE: Test the behavior of Link with Channel and the upcoming Ref{Channel} change
#

using Test
using Actors
import Actors: spawn, newLink, diag

println("=" ^ 60)
println("UNIT TESTS - Link and Channel Semantics")
println("=" ^ 60)

# ============================================================================
# LINK TESTS
# ============================================================================

@testset "Link: Basic creation and access" begin
    ch = Channel{Any}(32)
    lk = Link(ch, 1, :default)
    
    @test lk.chn === ch
    @test lk.pid == 1
    @test lk.mode == :default
    @test lk isa Actors.Link
end

@testset "Link: Mutable channel update" begin
    ch1 = Channel{Any}(32)
    lk = Link(ch1, 1, :default)
    
    ch2 = Channel{Any}(32)
    lk.chn = ch2
    
    @test lk.chn === ch2
    @test lk.chn !== ch1
end

@testset "Link: Channel state inspection" begin
    ch = Channel{Any}(32)
    lk = Link(ch, 1, :default)
    
    @test ch.state == :open
    @test lk.chn.state == :open
    
    # Close the channel
    close(ch)
    
    @test ch.state == :closed
    @test lk.chn.state == :closed
end

# ============================================================================
# CHANNEL REFERENCE TESTS
# ============================================================================

@testset "Channel: Send and receive" begin
    ch = Channel{Any}(32)
    
    # Send to channel
    put!(ch, "hello")
    put!(ch, 42)
    
    # Receive from channel
    @test take!(ch) == "hello"
    @test take!(ch) == 42
end

@testset "Channel: Bound to task" begin
    ch = Channel{Any}(32)
    t = Task(() -> begin
        take!(ch)
    end)
    
    bind(ch, t)
    schedule(t)
    
    # Put should trigger the task
    put!(ch, "message")
    
    wait(t)
    @test t.state == :done
    
    # Channel should be closed after bound task finishes
    @test ch.state == :closed
end

@testset "Channel: Multiple producers" begin
    ch = Channel{Any}(32)
    results = Int[]
    lock_ = ReentrantLock()
    
    # Multiple producers
    producers = Task[]
    for i in 1:3
        t = Task(() -> begin
            for j in 1:10
                put!(ch, i * 100 + j)
            end
        end)
        push!(producers, t)
    end
    
    # Schedule all producers
    for t in producers
        schedule(t)
    end
    
    # Wait for all to complete
    for t in producers
        wait(t)
    end
    
    # Drain the channel
    while isready(ch)
        push!(results, take!(ch))
    end
    
    @test length(results) == 30
end

# ============================================================================
# LINK WITH SPAWN TESTS
# ============================================================================

@testset "Spawn: Link channel lifecycle" begin
    lk = spawn(identity)
    
    # Channel should exist and be open
    @test lk.chn isa Channel
    @test lk.chn.state == :open
    
    # Actor should respond
    result = call(lk, 42)
    @test result == 42
    
    # Exit the actor
    exit!(lk)
    sleep(0.2)
    
    # After exit, channel should be closed
    @test lk.chn.state == :closed
end

@testset "Spawn: Channel replacement via become!" begin
    lk = spawn((x) -> x * 2)
    
    @test call(lk, 5) == 10
    
    become!(lk, (x) -> x + 100)
    
    @test call(lk, 5) == 105
end

# ============================================================================
# PROXY/REF BEHAVIOR TESTS (for Ref{Channel} implementation)
# ============================================================================

@testset "Ref behavior: Atomic swap" begin
    ref = Ref(Channel{Any}(32))
    
    # Put something in first channel
    put!(ref[], "first")
    
    # Create new channel and swap
    new_ch = Channel{Any}(32)
    old_ch = ref[]
    ref[] = new_ch
    
    # New channel should be accessible
    @test ref[] === new_ch
    @test ref[] !== old_ch
    
    # Old channel should still be accessible via old reference
    @test isready(old_ch) || take!(old_ch) == "first"
end

@testset "Ref behavior: Thread-safe update" begin
    ref = Ref(0)
    
    # Concurrent updates
    tasks = Task[]
    for _ in 1:10
        t = @async begin
            for _ in 1:1000
                ref[] = ref[] + 1
            end
        end
        push!(tasks, t)
    end
    
    for t in tasks
        wait(t)
    end
    
    @test ref[] == 10000
end

println("\n" * "=" ^ 60)
println("UNIT TESTS COMPLETED")
println("=" ^ 60)
