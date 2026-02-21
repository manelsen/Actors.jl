#
# Integration Tests: All new features working together
#

using Test
using Actors
import Actors: spawn

@testset "Integration Tests" begin
    
    @testset "StateMachine + EventManager" begin
        # State machine that publishes state changes to event manager
        em = event_manager()
        
        state_changes = []
        add_handler(em, :logger,
            () -> state_changes,
            (event, state) -> begin
                push!(state, event)
                (state, [])
            end
        )
        
        sleep(0.05)
        
        function sm_init()
            return (:idle, em)
        end
        
        function sm_handle_event(state, event, em)
            if event == :start && state == :idle
                send_event(em, (:state_change, :idle, :running))
                return (:running, em, [])
            elseif event == :stop && state == :running
                send_event(em, (:state_change, :running, :idle))
                return (:idle, em, [])
            end
            return (state, em, [])
        end
        
        sm = StateMachine(sm_init, sm_handle_event)
        lk = spawn(sm, mode=:statem)
        
        cast(lk, :start)
        sleep(0.1)
        cast(lk, :stop)
        sleep(0.1)
        
        @test length(state_changes) == 2
        @test (:state_change, :idle, :running) in state_changes
        @test (:state_change, :running, :idle) in state_changes
        
        exit!(lk)
        exit!(em)
    end
    
    @testset "PriorityChannel + StateMachine" begin
        # State machine with priority-based transitions
        processed = Symbol[]
        
        lk = newPriorityLink(32)
        t = Task(() -> begin
            state = :normal
            while true
                msg = take!(lk.chn)
                msg == :stop && break
                
                if msg == :urgent
                    state = :urgent
                    push!(processed, :entered_urgent)
                elseif msg == :normal
                    state = :normal
                    push!(processed, :entered_normal)
                end
            end
        end)
        schedule(t)
        
        sleep(0.1)
        
        # Send low, then high - high should process first
        send_low(lk, :normal)
        send_high(lk, :urgent)
        
        sleep(0.2)
        
        put!(lk.chn, :stop)
        sleep(0.1)
        
        # Urgent should have been processed first
        @test first(processed) == :entered_urgent
        @test last(processed) == :entered_normal
        
        close(lk.chn)
    end
    
    @testset "EventManager + PriorityChannel" begin
        # Event manager with priority events
        processed = []
        
        lk = newPriorityLink(32)
        t = Task(() -> begin
            while true
                event = take!(lk.chn)
                event == :stop && break
                push!(processed, event)
            end
        end)
        schedule(t)
        
        sleep(0.1)
        
        # Simulate event manager behavior with priorities
        send_low(lk, (:user_event, "background task"))
        send_priority(lk, (:system_event, "health check"), 20)
        send_high(lk, (:system_event, "alert"))
        send_low(lk, (:user_event, "cleanup"))
        
        sleep(0.2)
        
        put!(lk.chn, :stop)
        sleep(0.1)
        
        # System events should come first
        @test first(processed)[1] == :system_event
        
        close(lk.chn)
    end
    
    @testset "All three features together" begin
        # Complex scenario: State machine publishes to event manager,
        # both use priority channels
        
        em_lk = newPriorityLink(32)
        em_task = Task(() -> begin
            handlers = Dict{Symbol,Any}(
                :logger => []
            )
            while true
                msg = take!(em_lk.chn)
                if msg == :stop
                    break
                elseif msg isa Tuple && first(msg) == :event
                    event = msg[2]
                    push!(handlers[:logger], event)
                end
            end
            handlers
        end)
        schedule(em_task)
        
        sleep(0.1)
        
        sm_lk = newPriorityLink(32)
        sm_task = Task(() -> begin
            state = :idle
            while true
                msg = take!(sm_lk.chn)
                if msg == :stop
                    break
                elseif msg == :start
                    send_high(em_lk, (:event, (:state_change, state, :running)))
                    state = :running
                elseif msg == :stop_task
                    send_priority(em_lk, (:event, (:state_change, state, :idle)), 50)
                    state = :idle
                end
            end
        end)
        schedule(sm_task)
        
        sleep(0.1)
        
        # Send commands
        send_high(sm_lk, :start)
        sleep(0.1)
        send_priority(sm_lk, :stop_task, 50)
        sleep(0.1)
        
        # Stop everything
        send_priority(em_lk, :stop, 100)
        send_priority(sm_lk, :stop, 100)
        
        sleep(0.2)
        
        # Event manager should have logged state changes
        handlers = fetch(em_task)
        @test length(handlers[:logger]) == 2
        @test (:state_change, :idle, :running) in handlers[:logger]
        @test (:state_change, :running, :idle) in handlers[:logger]
        
        close(em_lk.chn)
        close(sm_lk.chn)
    end
    
    @testset "Integration with supervision" begin
        # State machine supervised by supervisor
        sv = supervisor(:one_for_one, max_restarts=5, max_seconds=10.0)
        
        started = Ref(false)
        
        function supervised_init()
            started[] = true
            return (:running, 0)
        end
        
        function supervised_handle_event(state, event, data)
            if event == :crash
                error("Intentional crash")
            elseif event == :increment
                return (:running, data + 1, [])
            end
            return (state, data, [])
        end
        
        sm = StateMachine(supervised_init, supervised_handle_event)
        lk = start_actor(sm, sv)
        
        sleep(0.2)
        
        @test started[] == true
        
        # Use it normally
        cast(lk, :increment)
        sleep(0.1)
        
        # Supervisor should handle crashes
        started[] = false
        cast(lk, :crash)
        sleep(0.3)
        
        # Should have been restarted
        @test started[] == true
        
        exit!(sv, :shutdown)
    end
end

println("Integration tests completed!")
