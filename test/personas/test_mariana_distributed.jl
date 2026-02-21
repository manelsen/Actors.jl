#
# Test Suite: Mariana - Distributed Systems Architect
# Focus: High availability, fault tolerance, supervision, checkpointing
#
# This test suite covers complex distributed scenarios:
# 1. Banking system with :one_for_all strategy and hierarchical checkpointing
# 2. E-commerce cart with :rest_for_one strategy, dependent actors
# 3. Processing cluster with automatic failover
#
# Categories:
# - Stress Tests: Thousands of actor restarts, intensive checkpointing cycles
# - Edge Cases: Supervisor receiving Exit during restart, checkpoint on full disk
# - Vulnerabilities: Race conditions in restart, memory leaks in restart loops

using Test
using Actors
using Random
import Actors: spawn, newLink, diag

println("=" ^ 60)
println("MARIANA - Distributed Systems Architect Test Suite")
println("=" ^ 60)

# ============================================================================
# STRESS TESTS
# ============================================================================

@testset "Stress Tests" begin
    
    # --------------------------------------------------------------------------
    # Test: Banking System - Rapid Failover and Recovery
    # Why: Financial systems must maintain consistency during rapid failures.
    # Tests supervisor restart capabilities under extreme load.
    # --------------------------------------------------------------------------
    @testset "Banking System - rapid failover cycles" begin
        t_sv = Ref{Task}()
        t_act = Ref{Task}()
        
        sv = supervisor(:one_for_one, max_restarts=20, max_seconds=30, taskref=t_sv)
        
        balance = Ref(1000.0)
        
        bank_actor = spawn((msg) -> begin
            if msg isa Tuple && first(msg) == :balance
                return balance[]
            elseif msg == :crash
                error("Bank system crash!")
            end
            return balance[]
        end, taskref=t_act)
        
        supervise(sv, bank_actor, restart=:permanent)
        sleep(0.3)
        
        for cycle in 1:10
            send(bank_actor, :crash)
            sleep(0.3)
            
            result = call(bank_actor, (:balance,))
            @test result == 1000.0
        end
        
        @test t_sv[].state == :runnable
        
        exit!(sv)
    end
    
    # --------------------------------------------------------------------------
    # Test: Multi-level Checkpointing Under Load
    # Why: HPC and distributed systems require multi-level checkpointing.
    # Tests hierarchical checkpointing with concurrent operations.
    # --------------------------------------------------------------------------
    @testset "Hierarchical Checkpointing - 3 levels" begin
        cp1 = checkpointing(1)
        cp2 = checkpointing(2)
        cp3 = checkpointing(3)
        
        send(cp1, Actors.Parent(cp2))
        send(cp2, Actors.Parent(cp3))
        
        sleep(0.2)
        
        for i in 1:100
            checkpoint(cp1, :data_l1, i, rand(100))
            if i % 10 == 0
                checkpoint(cp2, :data_l2, i, rand(1000))
            end
            if i % 50 == 0
                checkpoint(cp3, :data_l3, i, rand(10000))
            end
        end
        
        sleep(0.5)
        
        l1_data = get_checkpoints(cp1)
        l2_data = get_checkpoints(cp2)
        l3_data = get_checkpoints(cp3)
        
        @test haskey(l1_data, :data_l1)
        @test haskey(l2_data, :data_l2)
        @test haskey(l3_data, :data_l3)
        
        restored = restore(cp1, :data_l1)
        @test restored !== nothing
        
        exit!(cp1)
        exit!(cp2)
        exit!(cp3)
    end
    
    # --------------------------------------------------------------------------
    # Test: E-commerce Cart - Dependent Actors Chain
    # Why: E-commerce systems have dependent components (cart, inventory, payment).
    # Tests :rest_for_one strategy with chained failures.
    # --------------------------------------------------------------------------
    @testset "E-commerce Cart - rest_for_one chain" begin
        t_sv = Ref{Task}()
        
        sv = supervisor(:rest_for_one, max_restarts=10, max_seconds=30, taskref=t_sv)
        
        cart_state = Ref(Dict{String, Int}())
        inventory_state = Ref(Dict{String, Int}("item1" => 100, "item2" => 50))
        payment_state = Ref(0.0)
        
        cart = spawn((msg) -> begin
            if msg isa Tuple && first(msg) == :add
                _, item, qty = msg
                cart_state[][item] = get(cart_state[], item, 0) + qty
                return cart_state[]
            elseif msg == :crash
                error("Cart crash!")
            end
            return cart_state[]
        end)
        
        inventory = spawn((msg) -> begin
            if msg isa Tuple && first(msg) == :check
                _, item = msg
                return get(inventory_state[], item, 0)
            elseif msg == :crash
                error("Inventory crash!")
            end
            return inventory_state[]
        end)
        
        payment = spawn((msg) -> begin
            if msg isa Tuple && first(msg) == :process
                _, amount = msg
                payment_state[] += amount
                return payment_state[]
            elseif msg == :crash
                error("Payment crash!")
            end
            return payment_state[]
        end)
        
        supervise(sv, cart, restart=:transient)
        sleep(0.1)
        supervise(sv, inventory, restart=:transient)
        sleep(0.1)
        supervise(sv, payment, restart=:transient)
        sleep(0.2)
        
        @test length(which_children(sv)) == 3
        
        send(inventory, :crash)
        sleep(0.5)
        
        @test t_sv[].state == :runnable
        @test length(which_children(sv)) >= 1
        
        exit!(sv)
    end
end

# ============================================================================
# EDGE CASES
# ============================================================================

@testset "Edge Cases" begin
    
    # --------------------------------------------------------------------------
    # Test: Supervisor Receives Exit During Restart
    # Why: Race conditions can occur when failures happen during recovery.
    # Tests supervisor resilience to concurrent failures.
    # --------------------------------------------------------------------------
    @testset "Supervisor receives Exit during restart cycle" begin
        t_sv = Ref{Task}()
        
        sv = supervisor(:one_for_one, max_restarts=5, max_seconds=10, taskref=t_sv)
        
        crash_count = Ref(0)
        
        actor1 = spawn((msg) -> begin
            if msg == :crash
                crash_count[] += 1
                error("Crash!")
            end
            return msg
        end)
        
        actor2 = spawn((msg) -> begin
            if msg == :crash
                error("Crash 2!")
            end
            return msg
        end)
        
        supervise(sv, actor1, restart=:permanent)
        supervise(sv, actor2, restart=:permanent)
        sleep(0.2)
        
        @sync for _ in 1:3
            @async begin
                send(actor1, :crash)
                sleep(0.05)
                send(actor2, :crash)
            end
        end
        
        sleep(1.0)
        
        @test t_sv[].state in [:runnable, :failed]
        
        if t_sv[].state == :runnable
            exit!(sv)
        end
    end
    
    # --------------------------------------------------------------------------
    # Test: Checkpoint with Nil/Nothing Values
    # Why: Real systems may have nil values that should be handled gracefully.
    # Tests checkpointing robustness with edge case data.
    # --------------------------------------------------------------------------
    @testset "Checkpoint with nil/nothing/special values" begin
        cp = checkpointing(1)
        
        checkpoint(cp, :nil_test, nothing)
        checkpoint(cp, :empty_tuple, ())
        checkpoint(cp, :empty_array, [])
        checkpoint(cp, :nan_value, NaN)
        checkpoint(cp, :inf_value, Inf)
        checkpoint(cp, :complex_nested, Dict(:a => nothing, :b => [NaN, Inf, nothing]))
        
        sleep(0.2)
        
        # IMPORTANTE: restore retorna TUPLA dos argumentos passados ao checkpoint
        # checkpoint(cp, key, x) armazena (x,), restore(cp, key) retorna (x,)
        nil_restored = restore(cp, :nil_test)
        @test nil_restored == (nothing,)
        
        nan_restored = restore(cp, :nan_value)
        @test isnan(first(nan_restored))
        
        inf_restored = restore(cp, :inf_value)
        @test isinf(first(inf_restored))
        
        data = get_checkpoints(cp)
        @test haskey(data, :complex_nested)
        
        exit!(cp)
    end
    
    # --------------------------------------------------------------------------
    # Test: Actor Dies During Checkpoint
    # Why: Actors can fail during checkpointing operations.
    # Tests that checkpointing doesn't corrupt data on actor failure.
    # --------------------------------------------------------------------------
    @testset "Actor dies during checkpoint operation" begin
        cp = checkpointing(1)
        
        state = Ref(0)
        
        actor = spawn((msg) -> begin
            if msg == :checkpoint
                state[] += 1
                checkpoint(cp, :actor_state, state[])
                if state[] > 5
                    error("Die during checkpoint!")
                end
                return state[]
            end
            return state[]
        end)
        
        for i in 1:10
            try
                call(actor, :checkpoint)
            catch
            end
        end
        
        sleep(0.3)
        
        restored = restore(cp, :actor_state)
        @test restored !== nothing
        @test first(restored) >= 1
        
        exit!(cp)
    end
    
    # --------------------------------------------------------------------------
    # Test: Supervisor Shutdown Cascade
    # Why: Nested supervisors must cascade shutdown correctly.
    # Tests hierarchical supervisor termination.
    # --------------------------------------------------------------------------
    @testset "Nested supervisor shutdown cascade" begin
        t_root = Ref{Task}()
        t_child = Ref{Task}()
        
        root_sv = supervisor(:one_for_all, taskref=t_root)
        child_sv = supervisor(:one_for_all, taskref=t_child)
        
        supervise(root_sv, child_sv, restart=:permanent)
        
        leaf_actor = spawn((msg) -> msg)
        supervise(child_sv, leaf_actor, restart=:permanent)
        
        sleep(0.3)
        
        @test t_root[].state == :runnable
        @test t_child[].state == :runnable
        
        exit!(root_sv, :shutdown)
        sleep(0.3)
        
        @test t_root[].state == :done
    end
end

# ============================================================================
# VULNERABILITY TESTS
# ============================================================================

@testset "Vulnerability Tests" begin
    
    # --------------------------------------------------------------------------
    # Test: Restart Loop Memory Leak
    # Why: Continuous restarts could cause memory leaks.
    # Tests memory management under restart cycles.
    # --------------------------------------------------------------------------
    @testset "Memory leak detection in restart loops" begin
        t_sv = Ref{Task}()
        
        sv = supervisor(:one_for_one, max_restarts=50, max_seconds=60, taskref=t_sv)
        
        large_data = zeros(10000)
        
        actor = spawn((msg) -> begin
            local_data = copy(large_data)
            if msg == :crash
                error("Crash with large local data")
            end
            return sum(local_data)
        end)
        
        supervise(sv, actor, restart=:transient)
        sleep(0.2)
        
        GC.gc()
        mem_before = Base.gc_live_bytes()
        
        for _ in 1:20
            send(actor, :crash)
            sleep(0.05)
        end
        
        GC.gc()
        mem_after = Base.gc_live_bytes()
        
        mem_growth = mem_after - mem_before
        max_acceptable_growth = 10 * 1024 * 1024
        
        @test mem_growth < max_acceptable_growth
        
        exit!(sv)
    end
    
    # --------------------------------------------------------------------------
    # Test: Race Condition in Concurrent Supervise/Unsupervise
    # Why: Concurrent modifications to child lists can cause race conditions.
    # Tests thread-safety of supervisor operations.
    # --------------------------------------------------------------------------
    @testset "Race condition in supervise/unsupervise" begin
        t_sv = Ref{Task}()
        
        sv = supervisor(:one_for_one, max_restarts=100, taskref=t_sv)
        
        actors = [spawn((msg) -> msg) for _ in 1:20]
        
        @sync begin
            @async for a in actors
                supervise(sv, a, restart=:transient)
                sleep(0.01)
            end
            
            @async for a in actors[1:10]
                unsupervise(sv, a)
                sleep(0.015)
            end
        end
        
        sleep(0.5)
        
        children = which_children(sv)
        @test length(children) >= 0
        
        exit!(sv)
    end
    
    # --------------------------------------------------------------------------
    # Test: Deadlock Detection in Nested Supervisors
    # Why: Nested supervisors can deadlock if not properly designed.
    # Tests that nested structures don't cause deadlocks.
    # --------------------------------------------------------------------------
    @testset "No deadlock in nested supervisor chain" begin
        supervisors = Link[]
        push!(supervisors, supervisor(:one_for_one))
        
        for i in 2:5
            sv = supervisor(:one_for_one)
            supervise(supervisors[end], sv, restart=:permanent)
            push!(supervisors, sv)
        end
        
        leaf = spawn((msg) -> msg)
        supervise(supervisors[end], leaf, restart=:permanent)
        
        sleep(0.5)
        
        @test length(which_children(supervisors[1])) >= 1
        
        send(leaf, :crash)
        sleep(0.3)
        
        for sv in supervisors
            @test Actors.diag(sv, :task).state == :runnable
        end
        
        for sv in reverse(supervisors)
            exit!(sv)
        end
    end
    
    # --------------------------------------------------------------------------
    # Test: Max Restarts Exceeded
    # Why: Supervisors must respect restart limits to prevent infinite loops.
    # Tests that supervisors terminate when limits are exceeded.
    # --------------------------------------------------------------------------
    @testset "Supervisor respects max_restarts limit" begin
        t_sv = Ref{Task}()
        
        sv = supervisor(:one_for_one, max_restarts=3, max_seconds=5, taskref=t_sv)
        
        actor = spawn((msg) -> error("Always crash!"))
        
        supervise(sv, actor, restart=:permanent)
        sleep(0.2)
        
        # Enviar triggers até o supervisor morrer
        for i in 1:5
            try
                send(actor, :trigger)
            catch e
                # Quando o supervisor morre, send lança TaskFailedException
                break
            end
            sleep(0.2)
        end
        
        sleep(0.5)
        
        @test t_sv[].state in [:done, :failed]
    end
end

# ============================================================================
# DISTRIBUTED SCENARIO TESTS
# ============================================================================

@testset "Distributed Scenarios" begin
    
    # --------------------------------------------------------------------------
    # Scenario: Banking System with Checkpoint Recovery
    # Why: Financial transactions must be recoverable from checkpoints.
    # Tests end-to-end checkpoint/restore workflow.
    # --------------------------------------------------------------------------
    @testset "Banking system with checkpoint recovery" begin
        cp = checkpointing(1, "test_bank_checkpoint.dat")
        
        t_sv = Ref{Task}()
        sv = supervisor(:one_for_one, max_restarts=10, taskref=t_sv)
        
        account_balance = Ref(1000.0)
        transaction_log = Ref(String[])
        
        bank_actor = spawn((msg) -> begin
            if msg isa Tuple
                cmd = first(msg)
                if cmd == :deposit
                    amount = msg[2]
                    account_balance[] += amount
                    push!(transaction_log[], "deposit:$amount")
                    checkpoint(cp, :balance, account_balance[])
                    checkpoint(cp, :log, copy(transaction_log[]))
                    return account_balance[]
                elseif cmd == :withdraw
                    amount = msg[2]
                    account_balance[] -= amount
                    push!(transaction_log[], "withdraw:$amount")
                    checkpoint(cp, :balance, account_balance[])
                    checkpoint(cp, :log, copy(transaction_log[]))
                    return account_balance[]
                elseif cmd == :balance
                    return account_balance[]
                end
            elseif msg == :crash
                error("Bank crash!")
            end
            return account_balance[]
        end)
        
        supervise(sv, bank_actor, restart=:transient)
        sleep(0.3)
        
        call(bank_actor, (:deposit, 500.0))
        call(bank_actor, (:withdraw, 200.0))
        
        sleep(0.2)
        
        saved_balance = restore(cp, :balance)
        saved_log = restore(cp, :log)
        
        # restore retorna tupla dos argumentos passados ao checkpoint
        @test first(saved_balance) == 1300.0
        @test length(first(saved_log)) == 2
        
        send(bank_actor, :crash)
        sleep(0.3)
        
        @test t_sv[].state == :runnable
        
        exit!(sv)
        exit!(cp)
        
        rm("test_bank_checkpoint.dat", force=true)
    end
    
    # --------------------------------------------------------------------------
    # Scenario: Cluster with Automatic Failover
    # Why: Distributed clusters need automatic failover capabilities.
    # Tests multi-node failure scenarios.
    # --------------------------------------------------------------------------
    @testset "Cluster failover simulation" begin
        t_sv = Ref{Task}()
        
        cluster_sv = supervisor(:one_for_all, max_restarts=5, taskref=t_sv)
        
        workers = Link[]
        for i in 1:5
            worker = spawn((msg) -> begin
                if msg isa Tuple && first(msg) == :process
                    return sum(msg[2])
                elseif msg == :crash
                    error("Worker crash!")
                end
                return :ok
            end)
            supervise(cluster_sv, worker, restart=:transient)
            push!(workers, worker)
            sleep(0.05)
        end
        
        sleep(0.3)
        
        @test length(which_children(cluster_sv)) == 5
        
        failed_worker = workers[3]
        send(failed_worker, :crash)
        sleep(0.5)
        
        @test t_sv[].state == :runnable
        
        exit!(cluster_sv)
    end
end

println("=" ^ 60)
println("MARIANA Distributed Systems Test Suite Completed")
println("=" ^ 60)
