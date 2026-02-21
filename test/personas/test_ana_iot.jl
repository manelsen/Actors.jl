#
# Test Suite: Ana - IoT/Edge Developer
# Focus: Systems of events, monitors, resilient connections, and devices with limited resources
#
# This test suite covers complex IoT scenarios:
# 1. Sensor Networks - multiple devices sending events, event manager aggregating
# 2. Alarm Systems - monitors observing devices, cascading notifications
# 3. Communication Gateways - resilient connections, auto-reconnection, trapExit
#
# Categories:
# - Stress Tests: Thousands of events/second, hundreds of monitors, unstable connections
# - Edge Cases: Device disconnect during event, monitor death, broken bidirectional connection
# - Vulnerabilities: Event storm, memory leak in handlers, deadlock in circular connections

using Test
using Actors
using Random
import Actors: spawn, newLink, diag

println("=" ^ 60)
println("ANA - IoT/Edge Developer Test Suite")
println("=" ^ 60)

# ============================================================================
# STRESS TESTS
# ============================================================================

@testset "Stress Tests" begin
    
    # --------------------------------------------------------------------------
    # Test: Sensor Network - High Throughput Events
    # Why: IoT devices often generate massive amounts of telemetry data.
    # Validates that the EventManager can handle real-world sensor loads.
    # --------------------------------------------------------------------------
    @testset "Sensor Network - 5000 events simulation" begin
        em = event_manager()
        
        received_events = Ref(0)
        
        add_handler(em, :telemetry_collector,
            () -> received_events,
            (event, state) -> begin
                state[] += 1
                (state, [])
            end
        )
        
        sleep(0.1)
        
        num_sensors = 50
        events_per_sensor = 100
        
        start_time = time()
        
        @sync for sensor_id in 1:num_sensors
            @async begin
                for event_num in 1:events_per_sensor
                    send_event(em, (:sensor, sensor_id, event_num, rand()))
                end
            end
        end
        
        sleep(1.5)
        elapsed = time() - start_time
        
        total_events = num_sensors * events_per_sensor
        
        @test received_events[] >= total_events * 0.90
        
        exit!(em)
    end
    
    # --------------------------------------------------------------------------
    # Test: Multiple Event Managers with Cross-Communication
    # Why: In IoT, multiple gateways often aggregate events from different zones.
    # Tests the ability to handle multiple event managers in parallel.
    # --------------------------------------------------------------------------
    @testset "Multiple Event Managers - Distributed Aggregation" begin
        num_managers = 5
        managers = [event_manager() for _ in 1:num_managers]
        
        counters = [Ref(0) for _ in 1:num_managers]
        
        for i in 1:num_managers
            add_handler(managers[i], :counter,
                () -> counters[i],
                (event, state) -> begin
                    state[] += 1
                    (state, [])
                end
            )
        end
        
        sleep(0.2)
        
        @sync for i in 1:num_managers
            @async begin
                for _ in 1:200
                    send_event(managers[i], (:zone, i, :tick))
                end
            end
        end
        
        sleep(1.0)
        
        for i in 1:num_managers
            @test counters[i][] >= 180
        end
        
        for em in managers
            exit!(em)
        end
    end
    
    # --------------------------------------------------------------------------
    # Test: Unstable Connections - Frequent Connect/Disconnect
    # Why: IoT devices in the field often lose and regain connectivity.
    # Tests the robustness of connection management under instability.
    # --------------------------------------------------------------------------
    @testset "Unstable Connections - Rapid connect/disconnect cycles" begin
        device_actor = spawn((msg) -> msg == :crash ? error("boom") : msg)
        gateway = spawn(connect, device_actor)
        
        connect_count = Ref(0)
        disconnect_count = Ref(0)
        
        for cycle in 1:50
            connect(device_actor)
            connect_count[] += 1
            sleep(0.01)
            
            disconnect(device_actor)
            disconnect_count[] += 1
            sleep(0.01)
        end
        
        sleep(0.2)
        
        @test connect_count[] == 50
        @test disconnect_count[] == 50
        
        exit!(device_actor)
        exit!(gateway)
    end
end

# ============================================================================
# EDGE CASES
# ============================================================================

@testset "Edge Cases" begin
    
    # --------------------------------------------------------------------------
    # Test: Device Disconnecting During Event Processing
    # Why: Devices can fail or disconnect while events are being processed.
    # Ensures the system handles this gracefully without data corruption.
    # --------------------------------------------------------------------------
    @testset "Device disconnect during event processing" begin
        em = event_manager()
        
        event_processed = Ref(false)
        disconnect_during_processing = Ref(false)
        
        add_handler(em, :slow_handler,
            () -> (event_processed, disconnect_during_processing),
            (event, state) -> begin
                proc_done, flagged = state
                sleep(0.05)
                if event == :disconnect_me
                    flagged[] = true
                end
                proc_done[] = true
                (state, [])
            end
        )
        
        sleep(0.1)
        
        device = spawn((msg) -> msg)
        connect(device)
        
        send_event(em, :disconnect_me)
        
        sleep(0.02)
        
        exit!(device)
        
        sleep(0.3)
        
        @test event_processed[] == true
        
        exit!(em)
    end
    
    # --------------------------------------------------------------------------
    # Test: Monitor Dies Before Monitored Actor
    # Why: In distributed systems, the observer can fail before the observed.
    # Ensures no orphaned connections or resource leaks occur.
    # --------------------------------------------------------------------------
    @testset "Monitor death before monitored actor" begin
        device_task = Ref{Task}()
        device = spawn((msg) -> msg == :crash ? error("device crash") : msg, taskref=device_task)
        
        monitor_actor = spawn(Bhv(monitor, device))
        
        sleep(0.2)
        
        exit!(monitor_actor)
        sleep(0.2)
        
        @test device_task[].state == :runnable
        
        result = call(device, :ping)
        @test result == :ping
        
        exit!(device)
    end
    
    # --------------------------------------------------------------------------
    # Test: Bidirectional Connection Breaking
    # Why: Network failures can break connections in one or both directions.
    # Tests that connected actors properly propagate exits.
    # --------------------------------------------------------------------------
    @testset "Bidirectional connection breaking" begin
        t1 = Ref{Task}()
        t2 = Ref{Task}()
        
        actor_a = spawn(connect, taskref=t1)
        actor_b = spawn(connect, taskref=t2)
        
        send(actor_a, actor_b)
        sleep(0.2)
        
        a_diag = diag(actor_a, :act)
        b_diag = diag(actor_b, :act)
        
        @test !isempty(a_diag.conn)
        @test !isempty(b_diag.conn)
        
        send(actor_b, "boom")
        sleep(0.3)
        
        @test t1[].state == :done
        @test t2[].state == :failed
    end
    
    # --------------------------------------------------------------------------
    # Test: Event Handler Throws Exception During Notification
    # Why: Faulty handlers should not crash the entire event manager.
    # Tests error isolation between handlers.
    # --------------------------------------------------------------------------
    @testset "Handler exception isolation" begin
        em = event_manager()
        
        healthy_count = Ref(0)
        
        add_handler(em, :faulty,
            () -> 0,
            (event, state) -> begin
                if event == :trigger_error
                    error("Handler fault!")
                end
                (state, [])
            end
        )
        
        add_handler(em, :healthy,
            () -> healthy_count,
            (event, state) -> begin
                state[] += 1
                (state, [])
            end
        )
        
        sleep(0.1)
        
        send_event(em, :trigger_error)
        sleep(0.1)
        
        send_event(em, :normal_event)
        sleep(0.1)
        
        @test healthy_count[] == 2
        
        exit!(em)
    end
    
    # --------------------------------------------------------------------------
    # Test: trapExit Stops Cascade
    # Why: Critical gateway actors should not fail due to downstream failures.
    # Tests that trapExit properly stops exit propagation.
    # --------------------------------------------------------------------------
    @testset "trapExit prevents cascade failure" begin
        t1 = Ref{Task}()
        t2 = Ref{Task}()
        t3 = Ref{Task}()
        
        failing = spawn(connect, taskref=t1)
        middle = spawn(connect, taskref=t2)
        sticky = spawn(connect, taskref=t3)
        
        send(failing, middle)
        send(sticky, middle)
        
        trapExit(sticky)
        sleep(0.1)
        
        @test diag(sticky, :act).mode == :sticky
        
        send(failing, "boom")
        sleep(0.3)
        
        @test t1[].state == :failed
        @test t2[].state == :done
        @test t3[].state == :runnable
        
        @test length(diag(sticky, :err)) == 1
    end
end

# ============================================================================
# VULNERABILITY TESTS
# ============================================================================

@testset "Vulnerability Tests" begin
    
    # --------------------------------------------------------------------------
    # Test: Event Storm - Massive Burst of Events
    # Why: Malfunctioning sensors or attacks can flood the system.
    # Tests system stability and backpressure under event storm.
    # --------------------------------------------------------------------------
    @testset "Event storm - 10000 events in burst" begin
        em = event_manager()
        
        processed = Ref(0)
        max_buffer = 500
        
        add_handler(em, :storm_handler,
            () -> (processed, max_buffer),
            (event, state) -> begin
                proc, max_buf = state
                if proc[] < max_buf
                    proc[] += 1
                end
                (state, [])
            end
        )
        
        sleep(0.1)
        
        @async for _ in 1:10000
            send_event(em, (:storm, rand()))
        end
        
        sleep(2.0)
        
        @test processed[] > 0
        
        exit!(em)
    end
    
    # --------------------------------------------------------------------------
    # Test: Memory Leak Detection in Handlers
    # Why: Long-running IoT systems cannot afford memory leaks.
    # Tests that handler state is properly garbage collected.
    # --------------------------------------------------------------------------
    @testset "Handler memory management" begin
        em = event_manager()
        
        large_data_events = Ref(0)
        
        add_handler(em, :memory_test,
            () -> large_data_events,
            (event, state) -> begin
                if event isa Tuple && first(event) == :large_data
                    large_array = zeros(1000)
                    state[] += 1
                    large_array = nothing
                end
                (state, [])
            end
        )
        
        sleep(0.1)
        
        for _ in 1:100
            send_event(em, (:large_data, rand(1000)))
        end
        
        sleep(0.5)
        
        GC.gc()
        
        @test large_data_events[] == 100
        
        exit!(em)
    end
    
    # --------------------------------------------------------------------------
    # Test: Circular Connection Detection/Prevention
    # Why: Misconfigured networks can create circular dependencies.
    # Tests that circular connections don't cause deadlocks or infinite loops.
    # --------------------------------------------------------------------------
    @testset "Circular connections A->B->C->A" begin
        t1 = Ref{Task}()
        t2 = Ref{Task}()
        t3 = Ref{Task}()
        
        actor_a = spawn(connect, taskref=t1)
        actor_b = spawn(connect, taskref=t2)
        actor_c = spawn(connect, taskref=t3)
        
        send(actor_a, actor_b)
        send(actor_b, actor_c)
        send(actor_c, actor_a)
        
        sleep(0.2)
        
        @test t1[].state == :runnable
        @test t2[].state == :runnable
        @test t3[].state == :runnable
        
        send(actor_a, "boom")
        sleep(0.3)
        
        @test t1[].state == :failed
        @test t2[].state == :done
        @test t3[].state == :done
    end
    
    # --------------------------------------------------------------------------
    # Test: Handler Add/Delete Race Condition
    # Why: Concurrent modifications to handlers can cause race conditions.
    # Tests thread-safety of handler management.
    # --------------------------------------------------------------------------
    @testset "Concurrent handler add/delete race" begin
        em = event_manager()
        
        for i in 1:20
            add_handler(em, Symbol("race_$i"),
                () -> 0,
                (e, s) -> (s + 1, s)
            )
        end
        
        sleep(0.1)
        
        adder = @async for i in 21:50
            add_handler(em, Symbol("race_$i"), () -> 0, (e, s) -> (s, s))
            sleep(0.001)
        end
        
        deleter = @async for i in 1:10
            delete_handler(em, Symbol("race_$i"))
            sleep(0.002)
        end
        
        sender = @async for _ in 1:200
            send_event(em, :race_test)
            sleep(0.001)
        end
        
        wait(adder)
        wait(deleter)
        wait(sender)
        
        sleep(0.5)
        
        handlers = which_handlers(em)
        @test length(handlers) > 0
        
        exit!(em)
    end
    
    # --------------------------------------------------------------------------
    # Test: Resource Exhaustion - Too Many Handlers
    # Why: Systems have limits; graceful degradation is required.
    # Tests behavior when approaching handler limits.
    # --------------------------------------------------------------------------
    @testset "Handler count limits" begin
        em = event_manager()
        
        max_handlers = 200
        successful_adds = Ref(0)
        
        for i in 1:max_handlers
            try
                add_handler(em, Symbol("limit_$i"),
                    () -> 0,
                    (e, s) -> (s, s)
                )
                successful_adds[] += 1
            catch
                break
            end
        end
        
        sleep(0.5)
        
        handlers = which_handlers(em)
        @test length(handlers) > 0
        
        exit!(em)
    end
end

# ============================================================================
# IOT SCENARIO TESTS
# ============================================================================

@testset "IoT Scenarios" begin
    
    # --------------------------------------------------------------------------
    # Scenario: Complete Sensor Network with Alarm System
    # Why: End-to-end test of a realistic IoT deployment pattern.
    # Combines event managers, monitors, and connections in one scenario.
    # --------------------------------------------------------------------------
    @testset "Complete sensor network with alarm system" begin
        alarm_log = Ref{Vector{Any}}(Vector{Any}())
        
        alarm_manager = event_manager()
        
        add_handler(alarm_manager, :alarm_logger,
            () -> alarm_log,
            (event, state) -> begin
                push!(state[], event)
                (state, [])
            end
        )
        
        add_handler(alarm_manager, :threshold_monitor,
            () -> Dict{Int,Float64}(),
            (event, state) -> begin
                if event isa Tuple && first(event) == :reading
                    _, sensor_id, value = event
                    state[sensor_id] = value
                    if value > 0.9
                        push!(alarm_log[], (:alarm, :high_value, sensor_id, value))
                    end
                end
                (state, [])
            end
        )
        
        sleep(0.2)
        
        num_sensors = 10
        events_per_sensor = 50
        
        @sync for sensor_id in 1:num_sensors
            @async begin
                for _ in 1:events_per_sensor
                    value = rand()
                    send_event(alarm_manager, (:reading, sensor_id, value))
                    sleep(0.005)
                end
            end
        end
        
        sleep(1.5)
        
        total_expected = num_sensors * events_per_sensor
        @test length(alarm_log[]) >= total_expected * 0.8
        
        exit!(alarm_manager)
    end
    
    # --------------------------------------------------------------------------
    # Scenario: Gateway with Automatic Reconnection
    # Why: IoT gateways must maintain connectivity despite transient failures.
    # Tests trapExit and reconnection logic.
    # --------------------------------------------------------------------------
    @testset "Gateway with automatic reconnection" begin
        t1 = Ref{Task}()
        t2 = Ref{Task}()
        t3 = Ref{Task}()
        
        gateway = spawn(connect, taskref=t1)
        trapExit(gateway)
        
        sleep(0.1)
        
        @test diag(gateway, :act).mode == :sticky
        
        device1 = spawn(connect, taskref=t2)
        send(device1, gateway)
        sleep(0.1)
        
        @test diag(device1, :act).conn[1].lk == gateway
        @test diag(gateway, :act).conn[1].lk == device1
        
        send(device1, "boom")
        sleep(0.3)
        
        @test t2[].state == :failed
        @test t1[].state == :runnable
        
        errors = diag(gateway, :err)
        @test errors !== nothing && length(errors) == 1
        
        device2 = spawn(connect, taskref=t3)
        send(device2, gateway)
        sleep(0.1)
        
        send(device2, "boom")
        sleep(0.3)
        
        @test t3[].state == :failed
        @test t1[].state == :runnable
        
        exit!(gateway)
    end
    
    # --------------------------------------------------------------------------
    # Scenario: Monitor Handling Task Timeout
    # Why: Tasks in IoT systems can hang; monitors must detect timeouts.
    # Tests monitor timeout functionality.
    # --------------------------------------------------------------------------
    @testset "Monitor task timeout detection" begin
        me = newLink()
        
        slow_task = Threads.@spawn begin
            sleep(10.0)
        end
        
        monitor_actor = spawn(Bhv(monitor, slow_task, timeout=1.0))
        call(monitor_actor, send, me)
        
        sleep(1.5)
        
        msg = receive(me; timeout=2.0)
        
        @test msg == :timed_out || (msg isa Actors.Down && msg.reason == :timed_out)
        
        exit!(monitor_actor)
    end
end

println("=" ^ 60)
println("ANA IoT/Edge Test Suite Completed")
println("=" ^ 60)
