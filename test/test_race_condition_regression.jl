#
# Regression Tests: Supervisor Race Condition
# PURPOSE: These tests verify that the supervisor correctly handles actor restarts
#          and that no messages are lost during the restart window.
#
# These tests should PASS both BEFORE and AFTER the Ref{Channel} implementation.
# They exist to ensure no functionality is lost during the refactoring.
#

using Test
using Actors
using Random
import Actors: spawn, newLink, diag

println("=" ^ 60)
println("REGRESSION TESTS - Supervisor Race Condition")
println("=" ^ 60)

# ============================================================================
# REGRESSION 1: Basic supervisor restart
# ============================================================================

@testset "Regression: Supervisor basic restart" begin
    sv = supervisor(:one_for_one, max_restarts=5, max_seconds=30)
    
    actor = spawn((msg) -> begin
        if msg == :ping
            return :pong
        elseif msg == :crash
            error("Intentional crash")
        end
        return nothing
    end)
    
    supervise(sv, actor, restart=:permanent)
    sleep(0.2)
    
    # Initial state
    @test call(actor, :ping) == :pong
    @test call(actor, :ping) == :pong
    
    # Crash and restart
    send(actor, :crash)
    sleep(0.5)
    
    # After restart, actor should still work
    @test call(actor, :ping) == :pong
    
    exit!(sv)
end

# ============================================================================
# REGRESSION 2: Multiple crash cycles
# ============================================================================

@testset "Regression: Multiple crash cycles" begin
    sv = supervisor(:one_for_one, max_restarts=10, max_seconds=30)
    
    actor = spawn((msg) -> begin
        if msg == :ping
            return :pong
        elseif msg == :crash
            error("Crash!")
        end
        return nothing
    end)
    
    supervise(sv, actor, restart=:permanent)
    sleep(0.2)
    
    # Multiple crash cycles
    for cycle in 1:5
        send(actor, :crash)
        sleep(0.4)
        
        # After restart, actor should respond
        result = call(actor, :ping)
        @test result == :pong
    end
    
    exit!(sv)
end

# ============================================================================
# REGRESSION 3: Messages not lost during restart
# ============================================================================

@testset "Regression: Messages not lost during restart" begin
    sv = supervisor(:one_for_one, max_restarts=5, max_seconds=30)
    results = Int[]
    lock_ = ReentrantLock()
    
    actor = spawn((msg) -> begin
        if msg isa Int
            push!(results, msg)
            return msg
        elseif msg == :crash
            error("Crash!")
        end
        return nothing
    end)
    
    supervise(sv, actor, restart=:permanent)
    sleep(0.2)
    
    # Send some messages before crash
    for i in 1:3
        call(actor, i)
    end
    
    # Crash
    send(actor, :crash)
    sleep(0.5)
    
    # Send more messages after restart
    for i in 4:6
        call(actor, i)
    end
    
    # All messages should be processed
    @test sort(results) == [1, 2, 3, 4, 5, 6]
    
    exit!(sv)
end

# ============================================================================
# REGRESSION 4: rest_for_one strategy
# ============================================================================

@testset "Regression: rest_for_one restart chain" begin
    sv = supervisor(:rest_for_one, max_restarts=5, max_seconds=30)
    
    first_actor = spawn((msg) -> begin
        if msg == :crash
            error("First actor crash!")
        elseif msg == :check
            return :first_ok
        end
        return nothing
    end)
    
    second_actor = spawn((msg) -> begin
        if msg == :check
            return :second_ok
        end
        return nothing
    end)
    
    supervise(sv, first_actor, restart=:permanent)
    supervise(sv, second_actor, restart=:permanent)
    sleep(0.3)
    
    # Both should work initially
    @test call(first_actor, :check) == :first_ok
    @test call(second_actor, :check) == :second_ok
    
    # Crash first actor - second should also restart
    send(first_actor, :crash)
    sleep(0.6)
    
    # Both should be restarted
    @test call(first_actor, :check) == :first_ok
    @test call(second_actor, :check) == :second_ok
    
    exit!(sv)
end

# ============================================================================
# REGRESSION 5: one_for_all strategy
# ============================================================================

@testset "Regression: one_for_all restart all" begin
    sv = supervisor(:one_for_all, max_restarts=5, max_seconds=30)
    
    actors = []
    for i in 1:3
        act = spawn((msg) -> begin
            if msg == :crash
                error("Crash!")
            elseif msg == :check
                return :ok
            end
            return nothing
        end)
        push!(actors, act)
        supervise(sv, act, restart=:permanent)
    end
    
    sleep(0.3)
    
    # All should work
    for act in actors
        @test call(act, :check) == :ok
    end
    
    # Crash one - all should restart
    send(actors[1], :crash)
    sleep(0.6)
    
    # All should be restarted
    for act in actors
        @test call(act, :check) == :ok
    end
    
    exit!(sv)
end

# ============================================================================
# REGRESSION 6: Nested supervisors
# ============================================================================

@testset "Regression: Nested supervisors" begin
    # Top-level supervisor
    top_sv = supervisor(:one_for_one, max_restarts=5, max_seconds=30)
    
    # Child supervisor
    child_sv = supervisor(:one_for_one, max_restarts=5, max_seconds=30)
    
    supervise(top_sv, child_sv, restart=:permanent)
    sleep(0.2)
    
    actor = spawn((msg) -> begin
        if msg == :crash
            error("Actor crash!")
        elseif msg == :check
            return :ok
        end
        return nothing
    end)
    
    supervise(child_sv, actor, restart=:permanent)
    sleep(0.2)
    
    @test call(actor, :check) == :ok
    
    send(actor, :crash)
    sleep(0.6)
    
    @test call(actor, :check) == :ok
    
    exit!(top_sv)
end

# ============================================================================
# REGRESSION 7: Concurrent messages during restart
# ============================================================================

@testset "Regression: Concurrent messages during restart" begin
    sv = supervisor(:one_for_one, max_restarts=10, max_seconds=30)
    counter = Ref(0)
    
    actor = spawn((msg) -> begin
        if msg == :increment
            counter[] += 1
            return counter[]
        elseif msg == :crash
            error("Crash!")
        end
        return counter[]
    end)
    
    supervise(sv, actor, restart=:permanent)
    sleep(0.2)
    
    # Send message
    @test call(actor, :increment) == 1
    
    # Schedule crash and concurrent messages
    @async begin
        sleep(0.1)
        send(actor, :crash)
    end
    
    # Try to send messages during potential restart window
    sleep(0.2)
    for i in 1:10
        try
            call(actor, :increment)
        catch
            # Ignore errors during restart window
        end
    end
    
    sleep(0.5)
    
    # Eventually actor should be responsive
    result = call(actor, :increment)
    @test result >= 1
    
    exit!(sv)
end

println("\n" * "=" ^ 60)
println("REGRESSION TESTS COMPLETED")
println("=" ^ 60)
