#
# Stress Test: StateMachine
# Tests StateMachine under high load with rapid state transitions
#

using Test
using Actors
import Actors: spawn

@testset "StateMachine Stress Tests" begin
    
    @testset "Rapid state transitions (10,000 transitions)" begin
        counter = Ref(0)
        
        function stress_init()
            return (:state1, counter)
        end
        
        function stress_handle_event(state, event, data)
            if event == :toggle
                new_state = state == :state1 ? :state2 : :state1
                data[] += 1
                return (new_state, data, [])
            end
            return (state, data, [])
        end
        
        sm = StateMachine(stress_init, stress_handle_event)
        lk = spawn(sm, mode=:statem)
        
        # Rapid transitions
        for _ in 1:10000
            cast(lk, :toggle)
        end
        
        sleep(1.0)  # Allow processing
        
        @test counter[] == 10000
        exit!(lk)
    end
    
    @testset "Concurrent access from multiple tasks" begin
        transitions = Ref(0)
        
        function concurrent_init()
            return (:active, transitions)
        end
        
        function concurrent_handle_event(state, event, data)
            if event == :increment
                data[] += 1
                return (state, data, [])
            end
            return (state, data, [])
        end
        
        sm = StateMachine(concurrent_init, concurrent_handle_event)
        lk = spawn(sm, mode=:statem)
        
        # 10 tasks, 1000 increments each
        tasks = [@async begin
            for _ in 1:1000
                cast(lk, :increment)
            end
        end for _ in 1:10]
        
        wait.(tasks)
        sleep(1.0)
        
        @test transitions[] == 10000
        exit!(lk)
    end
    
    @testset "Memory stress (100 state machines)" begin
        machines = []
        for i in 1:100
            sm = StateMachine(() -> (:init, i), (s, e, d) -> (s, d, []))
            lk = spawn(sm, mode=:statem)
            push!(machines, lk)
        end
        
        sleep(0.5)
        
        # All should respond
        for lk in machines
            @test call(lk, :ping) == :init
        end
        
        foreach(exit!, machines)
        sleep(0.5)
        
        @test true  # If we get here, memory management is OK
    end
    
    @testset "Timeout stress (100 timeouts)" begin
        timeout_count = Ref(0)
        
        function timeout_init()
            return (:waiting, timeout_count)
        end
        
        function timeout_handle_event(state, event, data)
            if event == :timeout
                data[] += 1
                return (:waiting, data, [(:timeout, 0.01, :timeout)])
            elseif event == :start
                return (:waiting, data, [(:timeout, 0.01, :timeout)])
            elseif event == :stop
                return (:done, data, [])
            end
            return (state, data, [])
        end
        
        sm = StateMachine(timeout_init, timeout_handle_event)
        lk = spawn(sm, mode=:statem)
        
        cast(lk, :start)
        sleep(1.0)
        cast(lk, :stop)
        sleep(0.1)
        
        @test timeout_count[] >= 50  # At least 50 timeouts in 1 second
        exit!(lk)
    end
end

println("StateMachine stress tests completed!")
