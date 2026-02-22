#
# Integration Tests: Supervisor Comprehensive
# PURPOSE: Test supervisor behavior with various strategies and scenarios
#

using Test
using Actors
using Random
import Actors: spawn, newLink, diag

println("=" ^ 60)
println("INTEGRATION TESTS - Supervisor Comprehensive")
println("=" ^ 60)

# ============================================================================
# INTEGRATION 1: One-for-One with Permanent Actor
# ============================================================================

@testset "Integration: one_for_one permanent actor" begin
    sv = supervisor(:one_for_one, max_restarts=3, max_seconds=5)
    
    actor = spawn((msg) -> begin
        if msg == :crash
            error("Crash!")
        elseif msg == :get
            return :alive
        end
        return nothing
    end)
    
    supervise(sv, actor, restart=:permanent)
    sleep(0.2)
    
    @test call(actor, :get) == :alive
    
    # Crash
    send(actor, :crash)
    sleep(0.5)
    
    @test call(actor, :get) == :alive
    
    exit!(sv)
end

# ============================================================================
# INTEGRATION 2: One-for-One with Transient Actor
# ============================================================================

@testset "Integration: one_for_one transient actor" begin
    sv = supervisor(:one_for_one, max_restarts=3, max_seconds=5)
    t = Ref{Task}()
    
    actor = spawn((msg) -> begin
        if msg == :crash
            error("Crash!")
        end
        return :processed
    end; taskref=t)
    
    supervise(sv, actor, restart=:transient)
    sleep(0.2)
    
    # Transient actors are NOT restarted
    send(actor, :crash)
    sleep(0.5)
    
    @test t[].state ∈ (:done, :failed)
    
    exit!(sv)
end

# ============================================================================
# INTEGRATION 3: Rest-for-One Chain
# ============================================================================

@testset "Integration: rest_for_one restart chain" begin
    sv = supervisor(:rest_for_one, max_restarts=3, max_seconds=5)
    
    order = Int[]
    
    first = spawn((msg) -> begin
        push!(order, 1)
        if msg == :crash
            error("First crash!")
        end
        return :first
    end)
    
    second = spawn((msg) -> begin
        push!(order, 2)
        return :second
    end)
    
    third = spawn((msg) -> begin
        push!(order, 3)
        return :third
    end)
    
    supervise(sv, first, restart=:permanent)
    supervise(sv, second, restart=:permanent)
    supervise(sv, third, restart=:permanent)
    sleep(0.3)
    
    # Call all actors
    call(first, :test)
    call(second, :test)
    call(third, :test)
    
    @test sort(order) == [1, 2, 3]
    
    # Crash first - second and third should restart
    send(first, :crash)
    sleep(0.6)
    
    # After restart, all should work
    @test call(first, :test) == :first
    @test call(second, :test) == :second
    @test call(third, :test) == :third
    
    exit!(sv)
end

# ============================================================================
# INTEGRATION 4: One-for-All Restart
# ============================================================================

@testset "Integration: one_for_all restart all" begin
    sv = supervisor(:one_for_all, max_restarts=3, max_seconds=5)
    
    actors = []
    for i in 1:3
        act = spawn((msg) -> begin
            if msg == :crash
                error("Crash!")
            end
            return :ok
        end)
        push!(actors, act)
        supervise(sv, act, restart=:permanent)
    end
    
    sleep(0.3)
    
    # All work
    for act in actors
        @test call(act, :ping) == :ok
    end
    
    # Crash one - all restart
    send(actors[1], :crash)
    sleep(0.6)
    
    # All should restart and work
    for act in actors
        @test call(act, :ping) == :ok
    end
    
    exit!(sv)
end

# ============================================================================
# INTEGRATION 5: Supervisor with Checkpoint
# ============================================================================

@testset "Integration: Supervisor with checkpoint recovery" begin
    sv = supervisor(:one_for_one, max_restarts=3, max_seconds=5)
    cp = checkpointing(1)
    
    actor = spawn((msg) -> begin
        if msg == :increment
            checkpoint(cp, :count, ())
            return :incremented
        elseif msg == :crash
            error("Crash!")
        elseif msg == :restore
            restored = restore(cp, :count)
            return restored
        end
        return nothing
    end)
    
    supervise(sv, actor, restart=:transient)
    sleep(0.3)
    
    # Increment a few times
    @test call(actor, :increment) == :incremented
    @test call(actor, :increment) == :incremented
    
    # Crash - state is lost with transient restart
    send(actor, :crash)
    sleep(0.5)
    
    # Fresh actor should respond
    @test call(actor, :increment) == :incremented
    
    exit!(sv)
    exit!(cp)
end

# ============================================================================
# INTEGRATION 6: Start Actor API
# ============================================================================

@testset "Integration: start_actor API" begin
    sv = supervisor(:one_for_one, max_restarts=3, max_seconds=5)
    
    lk = start_actor(x -> x * 2, sv)
    sleep(0.2)
    
    @test call(lk, 5) == 10
    
    exit!(sv)
end

# ============================================================================
# INTEGRATION 7: Count Children
# ============================================================================

@testset "Integration: count_children" begin
    sv = supervisor(:one_for_one, max_restarts=3, max_seconds=5)
    
    @test count_children(sv).all == 0
    
    act1 = start_actor(identity, sv)
    sleep(0.1)
    
    @test count_children(sv).all == 1
    
    act2 = start_actor(identity, sv)
    sleep(0.1)
    
    @test count_children(sv).all == 2
    
    exit!(sv)
end

# ============================================================================
# INTEGRATION 8: Which Children
# ============================================================================

@testset "Integration: which_children" begin
    sv = supervisor(:one_for_one, max_restarts=3, max_seconds=5)
    
    act1 = start_actor(identity, sv)
    act2 = start_actor(x -> x + 1, sv)
    sleep(0.2)
    
    children = which_children(sv)
    @test length(children) == 2
    
    # Check info
    children_info = which_children(sv, true)
    @test length(children_info) == 2
    
    exit!(sv)
end

# ============================================================================
# INTEGRATION 9: Terminate Child
# ============================================================================

@testset "Integration: terminate_child" begin
    sv = supervisor(:one_for_one, max_restarts=3, max_seconds=5)
    
    act = start_actor(identity, sv)
    sleep(0.2)
    
    @test count_children(sv).all == 1
    
    terminate_child(sv, act)
    sleep(0.3)
    
    @test count_children(sv).all == 0
    
    exit!(sv)
end

# ============================================================================
# INTEGRATION 10: Set Strategy
# ============================================================================

@testset "Integration: set_strategy" begin
    sv = supervisor(:one_for_one, max_restarts=3, max_seconds=5)
    
    act = start_actor(identity, sv)
    sleep(0.1)
    
    # Change strategy
    set_strategy(sv, :one_for_all)
    
    # Should still work
    @test call(act, 42) == 42
    
    exit!(sv)
end

println("\n" * "=" ^ 60)
println("INTEGRATION TESTS COMPLETED")
println("=" ^ 60)
