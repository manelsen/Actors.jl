#
# Test StateMachine (gen_statem) functionality
#

using Test
using Actors
import Actors: spawn, newLink

@testset "StateMachine basic transitions" begin
    function simple_init()
        return (:idle, 0)
    end
    
    function simple_handle_event(state, event, data)
        if state == :idle
            if event == :start
                return (:running, data, [])
            elseif event == :increment
                return (:idle, data + 1, [])
            end
        elseif state == :running
            if event == :stop
                return (:idle, data, [])
            elseif event == :increment
                return (:running, data + 1, [])
            end
        end
        return (state, data, [])
    end
    
    sm = StateMachine(simple_init, simple_handle_event)
    lk = spawn(sm, mode=:statem)
    
    @test call(lk, :ping) == :idle
    
    cast(lk, :start)
    sleep(0.05)
    @test call(lk, :ping) == :running
    
    cast(lk, :increment)
    sleep(0.05)
    @test call(lk, :ping) == :running
    
    cast(lk, :stop)
    sleep(0.05)
    @test call(lk, :ping) == :idle
    
    exit!(lk)
end

@testset "StateMachine with data" begin
    function counter_init()
        return (:counting, 0)
    end
    
    function counter_handle_event(state, event, data)
        if state == :counting
            if event == :increment
                return (:counting, data + 1, [])
            elseif event == :reset
                return (:counting, 0, [])
            elseif event == :get
                return (:counting, data, [])
            end
        end
        return (state, data, [])
    end
    
    sm = StateMachine(counter_init, counter_handle_event)
    lk = spawn(sm, mode=:statem)
    
    @test call(lk, :increment) == :counting
    @test call(lk, :increment) == :counting
    @test call(lk, :increment) == :counting
    
    @test call(lk, :reset) == :counting
    
    exit!(lk)
end

println("All StateMachine tests passed!")

