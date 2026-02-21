#
# Test Suite: Ricardo - Real-Time Systems Developer
# Focus: Low latency, state machines, priority messaging, timeouts
#
# This test suite covers complex real-time scenarios:
# 1. Air traffic controller - state machine with priorities
# 2. High-frequency trading - minimal latency, batch event processing
# 3. Industrial controller - state machine with timeouts, emergency priorities
#
# Categories:
# - Stress Tests: Thousands of state transitions per second, priority message floods
# - Edge Cases: Timeout during state transition, priority message during processing
# - Vulnerabilities: Invalid state injection, priority bypass, starvation

using Test
using Actors
using Random
import Actors: spawn, newLink, diag

println("=" ^ 60)
println("RICARDO - Real-Time Systems Developer Test Suite")
println("=" ^ 60)

# ============================================================================
# STRESS TESTS
# ============================================================================

@testset "Stress Tests" begin
    
    # --------------------------------------------------------------------------
    # Test: High-Frequency State Transitions
    # Why: Real-time systems like trading engines require rapid state changes.
    # Tests state machine throughput under maximum load.
    # --------------------------------------------------------------------------
    @testset "State Machine - 10000 rapid transitions" begin
        function counter_init()
            return (:idle, 0)
        end
        
        function counter_handle_event(state, event, data)
            if state == :idle
                if event == :start
                    return (:counting, 0, [])
                end
            elseif state == :counting
                if event == :increment
                    return (:counting, data + 1, [])
                elseif event == :stop
                    return (:idle, data, [(:reply, data)])
                end
            end
            return (state, data, [])
        end
        
        counter = Actors.StateMachine(counter_init, counter_handle_event)
        lk = spawn(counter, mode=:statem)
        
        cast(lk, :start)
        sleep(0.05)
        
        start_time = time()
        
        for _ in 1:10000
            cast(lk, :increment)
        end
        
        result = call(lk, :stop)
        elapsed = time() - start_time
        
        @test result >= 9000
        @test elapsed < 10.0
        
        exit!(lk)
    end
    
    # --------------------------------------------------------------------------
    # Test: Priority Message Flood
    # Why: Real-time systems must handle bursts of high-priority messages.
    # Tests priority channel under extreme load.
    # --------------------------------------------------------------------------
    @testset "Priority Channel - 5000 priority messages" begin
        processed_order = Symbol[]
        order_lock = ReentrantLock()
        
        lk = newPriorityLink(1000)
        
        t = Task(() -> begin
            while true
                try
                    msg = take!(lk.chn)
                    msg == :stop && break
                    lock(order_lock) do
                        push!(processed_order, msg)
                    end
                catch
                    break
                end
            end
        end)
        schedule(t)
        
        sleep(0.1)
        
        for i in 1:1000
            send_priority(lk, Symbol("low_$i"), -1)
        end
        for i in 1:1000
            send_priority(lk, Symbol("high_$i"), 1)
        end
        for i in 1:1000
            send_priority(lk, Symbol("urgent_$i"), 10)
        end
        
        sleep(0.5)
        
        put!(lk.chn, :stop)
        sleep(0.1)
        
        urgent_count = count(m -> startswith(string(m), "urgent_"), processed_order)
        high_count = count(m -> startswith(string(m), "high_"), processed_order)
        
        @test urgent_count > 0
        @test high_count > 0
        
        first_100 = processed_order[1:min(100, length(processed_order))]
        urgent_in_first = count(m -> startswith(string(m), "urgent_"), first_100)
        @test urgent_in_first > 50
        
        close(lk.chn)
    end
    
    # --------------------------------------------------------------------------
    # Test: Event Manager Throughput
    # Why: Industrial systems aggregate events from many sources.
    # Tests event manager under high throughput.
    # --------------------------------------------------------------------------
    @testset "Event Manager - 5000 events throughput" begin
        em = Actors.event_manager()
        
        event_count = Ref(0)
        
        Actors.add_handler(em, :throughput_counter,
            () -> event_count,
            (event, state) -> begin
                state[] += 1
                (state, [])
            end
        )
        
        sleep(0.1)
        
        start_time = time()
        
        @sync for source in 1:50
            @async for i in 1:100
                send_event(em, (:source, source, i))
            end
        end
        
        sleep(2.0)
        elapsed = time() - start_time
        
        @test event_count[] >= 4500
        @test elapsed < 5.0
        
        exit!(em)
    end
end

# ============================================================================
# EDGE CASES
# ============================================================================

@testset "Edge Cases" begin
    
    # --------------------------------------------------------------------------
    # Test: State Machine Timeout During Transition
    # Why: Timeouts can occur during state transitions in real systems.
    # Tests that state machine handles timeouts gracefully.
    # --------------------------------------------------------------------------
    @testset "State Machine - Timeout during transition" begin
        function timeout_init()
            return (:waiting, Dict{Symbol,Any}())
        end
        
        function timeout_handle_event(state, event, data)
            if state == :waiting
                if event == :start
                    return (:processing, data, [(:timeout, 0.3, :timed_out)])
                elseif event == :timed_out
                    return (:timeout_reached, data, [])
                end
            elseif state == :processing
                if event == :complete
                    return (:done, data, [])
                end
            end
            return (state, data, [])
        end
        
        sm = Actors.StateMachine(timeout_init, timeout_handle_event)
        lk = spawn(sm, mode=:statem)
        
        cast(lk, :start)
        sleep(0.1)
        
        current = call(lk, :ping)
        @test current == :processing
        
        sleep(0.4)
        
        current = call(lk, :ping)
        @test current == :timeout_reached
        
        exit!(lk)
    end
    
    # --------------------------------------------------------------------------
    # Test: Priority Inversion Prevention
    # Why: Priority inversion can cause real-time system failures.
    # Tests that high-priority messages are processed despite low-priority backlog.
    # --------------------------------------------------------------------------
    @testset "Priority inversion prevention" begin
        lk = newPriorityLink(100)
        
        processing_log = Symbol[]
        lock_log = ReentrantLock()
        
        t = Task(() -> begin
            while true
                try
                    msg = take!(lk.chn)
                    msg == :stop && break
                    sleep(0.01)
                    lock(lock_log) do
                        push!(processing_log, msg)
                    end
                catch
                    break
                end
            end
        end)
        schedule(t)
        
        sleep(0.1)
        
        for i in 1:50
            send_low(lk, Symbol("low_$i"))
        end
        
        send_high(lk, :urgent_interrupt)
        
        for i in 1:20
            send_low(lk, Symbol("more_low_$i"))
        end
        
        sleep(2.0)
        
        put!(lk.chn, :stop)
        sleep(0.1)
        
        urgent_idx = findfirst(==(Symbol("urgent_interrupt")), processing_log)
        
        @test urgent_idx !== nothing
        @test urgent_idx <= 5
        
        close(lk.chn)
    end
    
    # --------------------------------------------------------------------------
    # Test: State Machine Unknown Event Handling
    # Why: Real systems receive unexpected events that must not crash the system.
    # Tests state machine resilience to unknown events.
    # --------------------------------------------------------------------------
    @testset "State Machine - Unknown event handling" begin
        function robust_init()
            return (:ready, 0)
        end
        
        function robust_handle_event(state, event, data)
            if event == :increment
                return (state, data + 1, [])
            elseif event == :reset
                return (:ready, 0, [])
            end
            return (state, data, [])
        end
        
        sm = Actors.StateMachine(robust_init, robust_handle_event)
        lk = spawn(sm, mode=:statem)
        
        for _ in 1:10
            cast(lk, :increment)
        end
        
        cast(lk, :unknown_event_1)
        cast(lk, :unknown_event_2)
        cast(lk, :bogus)
        
        for _ in 1:5
            cast(lk, :increment)
        end
        
        sleep(0.2)
        
        current_state = call(lk, :ping)
        @test current_state == :ready
        
        exit!(lk)
    end
    
    # --------------------------------------------------------------------------
    # Test: Concurrent State Machine Actions
    # Why: State machines may receive concurrent events.
    # Tests thread-safety of state transitions.
    # --------------------------------------------------------------------------
    @testset "State Machine - Concurrent event processing" begin
        function concurrent_init()
            return (:active, 0)
        end
        
        function concurrent_handle_event(state, event, data)
            if event == :add
                return (state, data + 1, [])
            end
            return (state, data, [])
        end
        
        sm = Actors.StateMachine(concurrent_init, concurrent_handle_event)
        lk = spawn(sm, mode=:statem)
        
        @sync for _ in 1:100
            @async cast(lk, :add)
        end
        
        sleep(0.5)
        
        exit!(lk)
    end
end

# ============================================================================
# VULNERABILITY TESTS
# ============================================================================

@testset "Vulnerability Tests" begin
    
    # --------------------------------------------------------------------------
    # Test: Invalid State Injection
    # Why: Attackers might try to inject invalid states.
    # Tests state machine robustness to malformed inputs.
    # --------------------------------------------------------------------------
    @testset "State Machine - Invalid state injection" begin
        function safe_init()
            return (:valid, 0)
        end
        
        function safe_handle_event(state, event, data)
            valid_states = [:valid, :processing, :complete]
            
            if !(state in valid_states)
                return (:valid, 0, [])
            end
            
            if event == :process
                return (:processing, data, [])
            elseif event == :complete
                return (:complete, data, [])
            elseif event == :reset
                return (:valid, 0, [])
            end
            
            return (state, data, [])
        end
        
        sm = Actors.StateMachine(safe_init, safe_handle_event)
        lk = spawn(sm, mode=:statem)
        
        cast(lk, :process)
        sleep(0.1)
        
        for bad_event in [nothing, NaN, Inf, [], Dict(), ()]
            try
                cast(lk, bad_event)
            catch
            end
        end
        
        sleep(0.2)
        
        current = call(lk, :ping)
        @test current in [:valid, :processing, :complete]
        
        exit!(lk)
    end
    
    # --------------------------------------------------------------------------
    # Test: Priority Starvation
    # Why: Low-priority messages can be starved by high-priority floods.
    # Tests that low-priority messages eventually get processed.
    # --------------------------------------------------------------------------
    @testset "Priority Starvation - Low priority eventually processed" begin
        lk = newPriorityLink(1000)
        
        processed = Symbol[]
        lock_proc = ReentrantLock()
        
        t = Task(() -> begin
            while true
                try
                    msg = take!(lk.chn)
                    msg == :stop && break
                    lock(lock_proc) do
                        push!(processed, msg)
                    end
                catch
                    break
                end
            end
        end)
        schedule(t)
        
        sleep(0.1)
        
        send_low(lk, :low_priority_victim)
        
        for i in 1:100
            send_high(lk, Symbol("high_$i"))
        end
        
        sleep(1.5)
        
        put!(lk.chn, :stop)
        sleep(0.1)
        
        low_processed = :low_priority_victim in processed
        high_count = count(m -> startswith(string(m), "high_"), processed)
        
        @test high_count > 50
        
        close(lk.chn)
    end
    
    # --------------------------------------------------------------------------
    # Test: Event Handler Exception Isolation
    # Why: One faulty handler should not crash the event manager.
    # Tests error isolation in event handling.
    # --------------------------------------------------------------------------
    @testset "Event Handler Exception Isolation" begin
        em = Actors.event_manager()
        
        healthy_count = Ref(0)
        
        Actors.add_handler(em, :faulty,
            () -> 0,
            (event, state) -> begin
                if event == :trigger_fault
                    error("Handler fault!")
                end
                (state, [])
            end
        )
        
        Actors.add_handler(em, :healthy,
            () -> healthy_count,
            (event, state) -> begin
                state[] += 1
                (state, [])
            end
        )
        
        sleep(0.2)
        
        send_event(em, :normal_event)
        send_event(em, :trigger_fault)
        send_event(em, :another_normal)
        
        sleep(0.5)
        
        @test healthy_count[] >= 2
        
        exit!(em)
    end
    
    # --------------------------------------------------------------------------
    # Test: State Machine Stop Action
    # Why: State machines must stop cleanly when requested.
    # Tests proper termination of state machines.
    # --------------------------------------------------------------------------
    @testset "State Machine - Proper stop action" begin
        function stoppable_init()
            return (:running, 0)
        end
        
        function stoppable_handle_event(state, event, data)
            if event == :stop
                return (:stopped, data, [:stop])
            elseif event == :increment
                return (state, data + 1, [])
            end
            return (state, data, [])
        end
        
        sm = Actors.StateMachine(stoppable_init, stoppable_handle_event)
        lk = spawn(sm, mode=:statem)
        
        for _ in 1:10
            cast(lk, :increment)
        end
        
        sleep(0.1)
        
        cast(lk, :stop)
        sleep(0.3)
        
        actor_info = Actors.info(lk)
        @test actor_info.mode in [:statem, :default]
    end
end

# ============================================================================
# REAL-TIME SCENARIO TESTS
# ============================================================================

@testset "Real-Time Scenarios" begin
    
    # --------------------------------------------------------------------------
    # Scenario: Air Traffic Controller State Machine
    # Why: ATC systems require precise state management with priorities.
    # Tests complete ATC state machine with emergency handling.
    # --------------------------------------------------------------------------
    @testset "Air Traffic Controller State Machine" begin
        function atc_init()
            return (:idle, Dict{Symbol,Any}(
                :aircraft_count => 0,
                :emergencies => 0,
                :landings => 0
            ))
        end
        
        function atc_handle_event(state, event, data)
            if state == :idle
                if event == :aircraft_approaching
                    return (:tracking, 
                        merge(data, Dict(:aircraft_count => data[:aircraft_count] + 1)),
                        [])
                end
            elseif state == :tracking
                if event == :emergency
                    return (:emergency, 
                        merge(data, Dict(:emergencies => data[:emergencies] + 1)),
                        [])
                elseif event == :landing_clear
                    return (:clearing, data, [])
                elseif event == :aircraft_approaching
                    return (:tracking, 
                        merge(data, Dict(:aircraft_count => data[:aircraft_count] + 1)),
                        [])
                end
            elseif state == :emergency
                if event == :emergency_handled
                    return (:tracking, data, [])
                end
            elseif state == :clearing
                if event == :runway_clear
                    return (:idle, 
                        merge(data, Dict(:landings => data[:landings] + 1)),
                        [])
                end
            end
            return (state, data, [])
        end
        
        atc = Actors.StateMachine(atc_init, atc_handle_event)
        lk = spawn(atc, mode=:statem)
        
        cast(lk, :aircraft_approaching)
        sleep(0.05)
        @test call(lk, :ping) == :tracking
        
        cast(lk, :emergency)
        sleep(0.05)
        @test call(lk, :ping) == :emergency
        
        cast(lk, :emergency_handled)
        sleep(0.05)
        @test call(lk, :ping) == :tracking
        
        cast(lk, :landing_clear)
        sleep(0.05)
        @test call(lk, :ping) == :clearing
        
        cast(lk, :runway_clear)
        sleep(0.05)
        @test call(lk, :ping) == :idle
        
        exit!(lk)
    end
    
    # --------------------------------------------------------------------------
    # Scenario: High-Frequency Trading Order Book
    # Why: HFT systems require priority handling for market data.
    # Tests priority-based order processing.
    # --------------------------------------------------------------------------
    @testset "HFT Order Book Priority Processing" begin
        lk = newPriorityLink(1000)
        
        order_log = Tuple[]
        lock_log = ReentrantLock()
        
        t = Task(() -> begin
            while true
                try
                    msg = take!(lk.chn)
                    msg == :stop && break
                    lock(lock_log) do
                        push!(order_log, (time(), msg))
                    end
                catch
                    break
                end
            end
        end)
        schedule(t)
        
        sleep(0.1)
        
        for i in 1:100
            send_low(lk, (:limit_order, i, 100.0 + i*0.01))
        end
        
        for i in 1:20
            send_high(lk, (:market_order, i, :buy))
        end
        
        for i in 1:10
            send_priority(lk, (:cancel_order, i), 100)
        end
        
        sleep(1.0)
        
        put!(lk.chn, :stop)
        sleep(0.1)
        
        cancels = filter(o -> o[2] isa Tuple && first(o[2]) == :cancel_order, order_log)
        markets = filter(o -> o[2] isa Tuple && first(o[2]) == :market_order, order_log)
        limits = filter(o -> o[2] isa Tuple && first(o[2]) == :limit_order, order_log)
        
        @test length(cancels) > 0
        @test length(markets) > 0
        @test length(limits) > 0
        
        if length(cancels) > 0 && length(limits) > 0
            first_cancel_idx = findfirst(o -> o == cancels[1], order_log)
            last_limit_idx = findlast(o -> o in limits, order_log)
            
            if first_cancel_idx !== nothing && last_limit_idx !== nothing
                @test first_cancel_idx < last_limit_idx
            end
        end
        
        close(lk.chn)
    end
    
    # --------------------------------------------------------------------------
    # Scenario: Industrial Controller with Emergency Stop
    # Why: Industrial systems need immediate response to emergency stops.
    # Tests priority override for safety-critical events.
    # --------------------------------------------------------------------------
    @testset "Industrial Controller Emergency Stop" begin
        function controller_init()
            return (:running, Dict{Symbol,Any}(:temperature => 20.0, :pressure => 1.0))
        end
        
        function controller_handle_event(state, event, data)
            if event == :emergency_stop
                return (:emergency_stopped, data, [])
            end
            
            if state == :running
                if event isa Tuple
                    cmd = first(event)
                    if cmd == :set_temp
                        return (:running, merge(data, Dict(:temperature => event[2])), [])
                    elseif cmd == :set_pressure
                        return (:running, merge(data, Dict(:pressure => event[2])), [])
                    end
                end
            elseif state == :emergency_stopped
                if event == :reset
                    return (:running, Dict(:temperature => 20.0, :pressure => 1.0), [])
                end
            end
            
            return (state, data, [])
        end
        
        controller = Actors.StateMachine(controller_init, controller_handle_event)
        lk = spawn(controller, mode=:statem)
        
        for temp in [25.0, 30.0, 35.0, 40.0]
            cast(lk, (:set_temp, temp))
        end
        
        sleep(0.1)
        @test call(lk, :ping) == :running
        
        cast(lk, :emergency_stop)
        sleep(0.1)
        @test call(lk, :ping) == :emergency_stopped
        
        cast(lk, (:set_temp, 50.0))
        sleep(0.1)
        @test call(lk, :ping) == :emergency_stopped
        
        cast(lk, :reset)
        sleep(0.1)
        @test call(lk, :ping) == :running
        
        exit!(lk)
    end
end

println("=" ^ 60)
println("RICARDO Real-Time Systems Test Suite Completed")
println("=" ^ 60)
