#
# Integration Tests - Complete System Integration
# Tests the interaction between multiple Actors components
#

using Test
using Actors
using Random
import Actors: spawn, newLink, diag

println("=" ^ 60)
println("INTEGRATION TESTS - System Integration")
println("=" ^ 60)

# ============================================================================
# INTEGRATION: Supervisor + Checkpointing
# ============================================================================

@testset "Supervisor + Checkpointing Integration" begin
    
    @testset "Supervised actor with checkpoint recovery" begin
        cp = checkpointing(1)
        t_sv = Ref{Task}()
        
        state = Ref(0)
        
        sv = supervisor(:one_for_one, max_restarts=5, taskref=t_sv)
        
        actor = spawn((msg) -> begin
            if msg == :increment
                state[] += 1
                checkpoint(cp, :state, state[])
                return state[]
            elseif msg == :crash
                error("Intentional crash")
            end
            return state[]
        end)
        
        supervise(sv, actor, restart=:transient)
        sleep(0.3)
        
        call(actor, :increment)
        call(actor, :increment)
        call(actor, :increment)
        
        sleep(0.2)
        saved_state = restore(cp, :state)
        @test saved_state == (3,)
        
        send(actor, :crash)
        sleep(0.5)
        
        @test t_sv[].state == :runnable
        
        exit!(sv)
        exit!(cp)
    end
end

# ============================================================================
# INTEGRATION: EventManager + Monitor
# ============================================================================

@testset "EventManager + Monitor Integration" begin
    
    @testset "Monitored device with event logging" begin
        event_log = Ref{Vector{Any}}(Vector{Any}())
        
        em = Actors.event_manager()
        
        Actors.add_handler(em, :logger,
            () -> event_log,
            (event, state) -> begin
                push!(state[], event)
                (state, [])
            end
        )
        
        sleep(0.1)
        
        me = newLink()
        
        device = spawn((msg) -> begin
            if msg == :crash
                error("Device crash!")
            end
            return msg
        end)
        
        monitor_actor = spawn(Actors.Bhv(Actors.monitor, device))
        call(monitor_actor, send_event, em)
        
        sleep(0.2)
        
        send_event(em, (:device, :started, device))
        
        send(device, :crash)
        sleep(0.3)
        
        @test length(event_log[]) >= 1
        
        exit!(em)
        exit!(monitor_actor)
    end
end

# ============================================================================
# INTEGRATION: StateMachine + Supervisor
# ============================================================================

@testset "StateMachine + Supervisor Integration" begin
    
    @testset "Supervised state machine with restart" begin
        t_sv = Ref{Task}()
        t_act = Ref{Task}()
        
        sv = supervisor(:one_for_one, max_restarts=5, taskref=t_sv)
        
        counter = Ref(0)
        
        controller = spawn((msg) -> begin
            if msg == :increment
                counter[] += 1
                return counter[]
            elseif msg == :crash
                error("Controller crash!")
            end
            return counter[]
        end, taskref=t_act)
        
        supervise(sv, controller, restart=:transient)
        sleep(0.3)
        
        for _ in 1:5
            call(controller, :increment)
        end
        
        sleep(0.2)
        @test counter[] == 5
        
        send(controller, :crash)
        sleep(0.5)
        
        @test t_sv[].state == :runnable
        
        exit!(sv)
    end
end

# ============================================================================
# INTEGRATION: Connections + Registry
# ============================================================================

@testset "Connections + Registry Integration" begin
    
    @testset "Named actors with connections" begin
        t1 = Ref{Task}()
        t2 = Ref{Task}()
        
        a = spawn(Actors.connect, taskref=t1)
        b = spawn(Actors.connect, taskref=t2)
        
        register(:actor_a, a)
        register(:actor_b, b)
        
        sleep(0.1)
        
        a_from_registry = whereis(:actor_a)
        b_from_registry = whereis(:actor_b)
        
        @test a_from_registry === a
        @test b_from_registry === b
        
        send(a, b)
        sleep(0.2)
        
        a_diag = diag(a, :act)
        @test !isempty(a_diag.conn)
        
        unregister(:actor_a)
        unregister(:actor_b)
        
        exit!(a)
        exit!(b)
    end
end

# ============================================================================
# INTEGRATION: Priority + EventManager
# ============================================================================

@testset "Priority + EventManager Integration" begin
    
    @testset "Priority event processing" begin
        em = Actors.event_manager()
        
        high_count = Ref(0)
        normal_count = Ref(0)
        
        Actors.add_handler(em, :priority_counter,
            () -> (high_count, normal_count),
            (event, state) -> begin
                hc, nc = state
                if event isa Tuple
                    if first(event) == :high
                        hc[] += 1
                    else
                        nc[] += 1
                    end
                end
                (state, [])
            end
        )
        
        sleep(0.1)
        
        for _ in 1:100
            send_event(em, (:normal, rand()))
        end
        
        for _ in 1:10
            send_event(em, (:high, :urgent))
        end
        
        sleep(0.5)
        
        @test high_count[] == 10
        @test normal_count[] == 100
        
        exit!(em)
    end
end

# ============================================================================
# INTEGRATION: Full Stack - All Components
# ============================================================================

@testset "Full Stack Integration" begin
    
    @testset "Complete system with all components" begin
        cp = checkpointing(1)
        
        t_sv = Ref{Task}()
        sv = supervisor(:one_for_one, max_restarts=10, taskref=t_sv)
        
        em = Actors.event_manager()
        
        Actors.add_handler(em, :system_logger,
            () -> Dict{Symbol,Any}(),
            (event, state) -> begin
                if event isa Tuple
                    state[first(event)] = event[2]
                end
                (state, [])
            end
        )
        
        sleep(0.2)
        
        counter = Ref(0)
        
        worker = spawn((msg) -> begin
            if msg == :work
                counter[] += 1
                checkpoint(cp, :counter, counter[])
                send_event(em, (:counter, counter[]))
                return counter[]
            elseif msg == :crash
                error("Worker crash!")
            end
            return counter[]
        end)
        
        supervise(sv, worker, restart=:transient)
        sleep(0.3)
        
        for _ in 1:10
            call(worker, :work)
        end
        
        sleep(0.3)
        
        @test counter[] == 10
        @test restore(cp, :counter) == (10,)
        
        send(worker, :crash)
        sleep(0.5)
        
        @test t_sv[].state == :runnable
        
        restored_counter = restore(cp, :counter)
        @test restored_counter == (10,)
        
        exit!(sv)
        exit!(em)
        exit!(cp)
    end
end

# ============================================================================
# INTEGRATION: Error Propagation Chain
# ============================================================================

@testset "Error Propagation Chain" begin
    
    @testset "Cascading failure through connections" begin
        t1 = Ref{Task}()
        t2 = Ref{Task}()
        t3 = Ref{Task}()
        
        a = spawn(Actors.connect, taskref=t1)
        b = spawn(Actors.connect, taskref=t2)
        c = spawn(Actors.connect, taskref=t3)
        
        send(a, b)
        send(b, c)
        
        sleep(0.3)
        
        @test t1[].state == :runnable
        @test t2[].state == :runnable
        @test t3[].state == :runnable
        
        send(a, "boom")
        sleep(0.3)
        
        @test t1[].state == :failed
        @test t2[].state == :done
        @test t3[].state == :done
    end
    
    @testset "trapExit stops cascade" begin
        t1 = Ref{Task}()
        t2 = Ref{Task}()
        t3 = Ref{Task}()
        
        a = spawn(Actors.connect, taskref=t1)
        b = spawn(Actors.connect, taskref=t2)
        c = spawn(Actors.connect, taskref=t3)
        
        trapExit(b)
        sleep(0.1)
        
        send(a, b)
        send(c, b)
        
        sleep(0.3)
        
        send(a, "boom")
        sleep(0.3)
        
        @test t1[].state == :failed
        @test t2[].state == :runnable
        @test t3[].state == :runnable
        
        exit!(b)
        exit!(c)
    end
end

# ============================================================================
# INTEGRATION: Registry + Supervisor
# ============================================================================

@testset "Registry + Supervisor Integration" begin
    
    @testset "Supervised registered actor" begin
        t_sv = Ref{Task}()
        t_act = Ref{Task}()
        
        sv = supervisor(:one_for_one, max_restarts=5, taskref=t_sv)
        
        actor = spawn((msg) -> begin
            if msg == :crash
                error("Crash!")
            end
            return msg
        end, taskref=t_act)
        
        register(:registered_worker, actor)
        supervise(sv, actor, restart=:permanent)
        sleep(0.3)
        
        @test whereis(:registered_worker) === actor
        
        send(actor, :crash)
        sleep(0.5)
        
        @test t_sv[].state == :runnable
        
        exit!(sv)
    end
end

# ============================================================================
# INTEGRATION: Multi-threading
# ============================================================================

@testset "Multi-threading Integration" begin
    
    @testset "Actors on different threads" begin
        actor1 = spawn((msg) -> Threads.threadid(), thrd=1)
        actor2 = spawn((msg) -> Threads.threadid(), thrd=Threads.nthreads() > 1 ? 2 : 1)
        
        tid1 = call(actor1, :ping)
        tid2 = call(actor2, :ping)
        
        @test tid1 >= 1
        @test tid2 >= 1
        
        exit!(actor1)
        exit!(actor2)
    end
    
    @testset "Thread-safe registry operations" begin
        actors = Link[]
        
        @sync for i in 1:20
            @async begin
                a = spawn((msg) -> msg)
                register(Symbol("thread_actor_$i"), a)
                push!(actors, a)
            end
        end
        
        sleep(0.5)
        
        registered_count = 0
        for i in 1:20
            if whereis(Symbol("thread_actor_$i")) !== nothing
                registered_count += 1
            end
        end
        
        @test registered_count > 0
        
        for i in 1:20
            unregister(Symbol("thread_actor_$i"))
        end
        
        for a in actors
            exit!(a)
        end
    end
end

# ============================================================================
# INTEGRATION: Complex Workflow
# ============================================================================

@testset "Complex Workflow Integration" begin
    
    @testset "Pipeline with supervision and checkpointing" begin
        cp = checkpointing(1)
        t_sv = Ref{Task}()
        
        sv = supervisor(:rest_for_one, max_restarts=5, taskref=t_sv)
        
        stage1_data = Ref(0)
        stage2_data = Ref(0)
        stage3_data = Ref(0)
        
        stage1 = spawn((msg) -> begin
            if msg isa Tuple && first(msg) == :process
                _, value = msg
                stage1_data[] = value * 2
                checkpoint(cp, :stage1, stage1_data[])
                return stage1_data[]
            end
            return stage1_data[]
        end)
        
        stage2 = spawn((msg) -> begin
            if msg isa Tuple && first(msg) == :process
                _, value = msg
                stage2_data[] = value + 10
                checkpoint(cp, :stage2, stage2_data[])
                return stage2_data[]
            end
            return stage2_data[]
        end)
        
        stage3 = spawn((msg) -> begin
            if msg isa Tuple && first(msg) == :process
                _, value = msg
                stage3_data[] = value ^ 2
                checkpoint(cp, :stage3, stage3_data[])
                return stage3_data[]
            end
            return stage3_data[]
        end)
        
        supervise(sv, stage1, restart=:transient)
        supervise(sv, stage2, restart=:transient)
        supervise(sv, stage3, restart=:transient)
        
        sleep(0.3)
        
        r1 = call(stage1, (:process, 5))
        r2 = call(stage2, (:process, r1))
        r3 = call(stage3, (:process, r2))
        
        @test r1 == 10
        @test r2 == 20
        @test r3 == 400
        
        sleep(0.2)
        
        @test restore(cp, :stage1) == (10,)
        @test restore(cp, :stage2) == (20,)
        @test restore(cp, :stage3) == (400,)
        
        exit!(sv)
        exit!(cp)
    end
end

println("=" ^ 60)
println("INTEGRATION TESTS Completed")
println("=" ^ 60)
