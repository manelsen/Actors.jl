#
# Test Suite: Pedro - HPC Data Scientist
# Focus: Distributed computing, multi-level checkpointing, parallel processing
#
# This test suite covers complex HPC scenarios:
# 1. Distributed ML pipeline - multiple workers, periodic model checkpointing
# 2. Monte Carlo simulation - thousands of worker actors, result aggregation
# 3. Stream processing - pipeline actors, backpressure, incremental checkpointing
#
# Categories:
# - Stress Tests: Thousands of workers, GB-scale checkpointing, simultaneous node failures
# - Edge Cases: Worker death during checkpoint, corrupted checkpoint recovery
# - Vulnerabilities: Data loss in checkpoint, inconsistency between levels, distributed deadlock

using Test
using Actors
using Random
import Actors: spawn, newLink, diag

println("=" ^ 60)
println("PEDRO - HPC Data Scientist Test Suite")
println("=" ^ 60)

# ============================================================================
# STRESS TESTS
# ============================================================================

@testset "Stress Tests" begin
    
    # --------------------------------------------------------------------------
    # Test: Monte Carlo Simulation - Many Workers
    # Why: HPC simulations require massive parallelization.
    # Tests system with hundreds of worker actors.
    # --------------------------------------------------------------------------
    @testset "Monte Carlo - 200 worker actors" begin
        results = Ref(0.0)
        results_lock = ReentrantLock()
        completed = Ref(0)
        
        function worker_sim(iterations)
            count = 0
            for _ in 1:iterations
                x, y = rand(), rand()
                if x^2 + y^2 <= 1
                    count += 1
                end
            end
            return count
        end
        
        aggregator = spawn((msg) -> begin
            if msg isa Tuple && first(msg) == :result
                _, value, iter = msg
                lock(results_lock) do
                    results[] += value
                    completed[] += iter
                end
                return :ack
            elseif msg == :get_pi
                return 4.0 * results[] / completed[]
            end
            return :unknown
        end)
        
        workers = Link[]
        iterations_per_worker = 1000
        num_workers = 200
        
        for i in 1:num_workers
            w = spawn((msg) -> begin
                if msg == :run
                    result = worker_sim(iterations_per_worker)
                    send(aggregator, (:result, result, iterations_per_worker))
                    return :done
                end
                return :idle
            end)
            push!(workers, w)
        end
        
        sleep(0.5)
        
        @sync for w in workers
            @async send(w, :run)
        end
        
        sleep(2.0)
        
        pi_estimate = call(aggregator, :get_pi)
        
        @test completed[] == num_workers * iterations_per_worker
        @test abs(pi_estimate - π) < 0.1
        
        for w in workers
            exit!(w)
        end
        exit!(aggregator)
    end
    
    # --------------------------------------------------------------------------
    # Test: Checkpoint Throughput
    # Why: HPC applications need efficient checkpointing.
    # Tests checkpoint system throughput under load.
    # --------------------------------------------------------------------------
    @testset "Checkpoint throughput - 1000 checkpoints" begin
        cp = checkpointing(1)
        
        start_time = time()
        
        for i in 1:1000
            checkpoint(cp, Symbol("key_$i"), rand(100))
        end
        
        elapsed = time() - start_time
        
        sleep(0.5)
        
        data = get_checkpoints(cp)
        
        @test length(data) >= 900
        
        restored = restore(cp, :key_500)
        @test restored !== nothing
        @test length(restored) == 100
        
        exit!(cp)
    end
    
    # --------------------------------------------------------------------------
    # Test: Multi-level Checkpoint Hierarchy
    # Why: HPC applications use hierarchical checkpointing for resilience.
    # Tests 3-level checkpoint hierarchy.
    # --------------------------------------------------------------------------
    @testset "Multi-level checkpoint hierarchy" begin
        cp_l1_a = checkpointing(1)
        cp_l1_b = checkpointing(1)
        cp_l2 = checkpointing(2)
        cp_l3 = checkpointing(3)
        
        send(cp_l1_a, Actors.Parent(cp_l2))
        send(cp_l1_b, Actors.Parent(cp_l2))
        send(cp_l2, Actors.Parent(cp_l3))
        
        sleep(0.3)
        
        for i in 1:100
            checkpoint(cp_l1_a, :data_a, i, level=1)
            checkpoint(cp_l1_b, :data_b, i*2, level=1)
        end
        
        for i in 1:20
            checkpoint(cp_l2, :data_l2, i*10, level=2)
        end
        
        for i in 1:5
            checkpoint(cp_l3, :data_l3, i*100, level=3)
        end
        
        sleep(0.5)
        
        restored_l1_a = restore(cp_l1_a, :data_a)
        restored_l1_b = restore(cp_l1_b, :data_b)
        restored_l2 = restore(cp_l2, :data_l2)
        restored_l3 = restore(cp_l3, :data_l3)
        
        @test restored_l1_a !== nothing
        @test restored_l1_b !== nothing
        @test restored_l2 !== nothing
        @test restored_l3 !== nothing
        
        exit!(cp_l1_a)
        exit!(cp_l1_b)
        exit!(cp_l2)
        exit!(cp_l3)
    end
end

# ============================================================================
# EDGE CASES
# ============================================================================

@testset "Edge Cases" begin
    
    # --------------------------------------------------------------------------
    # Test: Worker Death During Checkpoint
    # Why: Workers can fail during checkpointing operations.
    # Tests checkpoint integrity when worker fails mid-checkpoint.
    # --------------------------------------------------------------------------
    @testset "Worker death during checkpoint" begin
        cp = checkpointing(1)
        
        worker_state = Ref(0)
        
        worker = spawn((msg) -> begin
            if msg == :work
                for i in 1:100
                    worker_state[] = i
                    checkpoint(cp, :worker_progress, i)
                    if i == 50
                        error("Worker crash at 50!")
                    end
                end
                return :done
            end
            return :idle
        end)
        
        send(worker, :work)
        sleep(0.5)
        
        restored = restore(cp, :worker_progress)
        @test restored !== nothing
        @test restored >= 1
        
        exit!(worker)
        exit!(cp)
    end
    
    # --------------------------------------------------------------------------
    # Test: Checkpoint File Persistence
    # Why: Checkpoints must persist across sessions.
    # Tests saving and loading checkpoints from file.
    # --------------------------------------------------------------------------
    @testset "Checkpoint file persistence" begin
        filename = "test_hpc_checkpoint.dat"
        
        cp1 = checkpointing(1, filename)
        
        test_data = Dict(
            :model_weights => rand(100, 100),
            :training_step => 1000,
            :loss => 0.0234,
            :config => Dict(:lr => 0.001, :epochs => 100)
        )
        
        for (k, v) in test_data
            checkpoint(cp1, k, v)
        end
        
        sleep(0.2)
        save_checkpoints(cp1)
        sleep(0.3)
        
        exit!(cp1)
        
        cp2 = checkpointing(1, filename)
        load_checkpoints(cp2, filename)
        sleep(0.3)
        
        loaded_step = restore(cp2, :training_step)
        loaded_loss = restore(cp2, :loss)
        
        @test loaded_step == 1000
        @test loaded_loss ≈ 0.0234
        
        exit!(cp2)
        rm(filename, force=true)
    end
    
    # --------------------------------------------------------------------------
    # Test: Empty Checkpoint Handling
    # Why: Systems must handle missing or empty checkpoints gracefully.
    # Tests restore of non-existent checkpoint.
    # --------------------------------------------------------------------------
    @testset "Empty/missing checkpoint handling" begin
        cp = checkpointing(1)
        
        result = restore(cp, :nonexistent_key)
        @test result === nothing
        
        checkpoint(cp, :empty_key, nothing)
        sleep(0.1)
        
        result = restore(cp, :empty_key)
        @test result === nothing
        
        exit!(cp)
    end
    
    # --------------------------------------------------------------------------
    # Test: Checkpoint Overwrite
    # Why: Checkpoints are often overwritten in training loops.
    # Tests that checkpoints can be overwritten correctly.
    # --------------------------------------------------------------------------
    @testset "Checkpoint overwrite" begin
        cp = checkpointing(1)
        
        for i in 1:10
            checkpoint(cp, :overwritten, i)
            sleep(0.05)
        end
        
        sleep(0.2)
        
        result = restore(cp, :overwritten)
        @test result == 10
        
        exit!(cp)
    end
end

# ============================================================================
# VULNERABILITY TESTS
# ============================================================================

@testset "Vulnerability Tests" begin
    
    # --------------------------------------------------------------------------
    # Test: Checkpoint Data Corruption
    # Why: Checkpoints can become corrupted during save/load.
    # Tests handling of corrupted checkpoint data.
    # --------------------------------------------------------------------------
    @testset "Checkpoint corruption handling" begin
        filename = "test_corrupt_checkpoint.dat"
        
        cp = checkpointing(1, filename)
        
        checkpoint(cp, :valid_data, [1, 2, 3, 4, 5])
        save_checkpoints(cp)
        sleep(0.2)
        
        exit!(cp)
        
        open(filename, "a") do f
            write(f, "CORRUPT_DATA")
        end
        
        cp2 = checkpointing(1)
        
        try
            load_checkpoints(cp2, filename)
            sleep(0.2)
        catch e
            @test e isa Exception
        end
        
        exit!(cp2)
        rm(filename, force=true)
    end
    
    # --------------------------------------------------------------------------
    # Test: Large Data Checkpoint Memory
    # Why: Large checkpoints can cause memory issues.
    # Tests memory management for large checkpoints.
    # --------------------------------------------------------------------------
    @testset "Large checkpoint memory management" begin
        cp = checkpointing(1)
        
        for batch in 1:10
            large_data = rand(1000, 1000)
            checkpoint(cp, Symbol("batch_$batch"), large_data)
            large_data = nothing
            GC.gc()
        end
        
        sleep(0.5)
        
        data = get_checkpoints(cp)
        @test length(data) == 10
        
        exit!(cp)
    end
    
    # --------------------------------------------------------------------------
    # Test: Concurrent Checkpoint Operations
    # Why: Concurrent checkpoint operations can cause race conditions.
    # Tests thread-safety of checkpoint operations.
    # --------------------------------------------------------------------------
    @testset "Concurrent checkpoint operations" begin
        cp = checkpointing(1)
        
        @sync begin
            @async for i in 1:100
                checkpoint(cp, Symbol("key_$i"), i)
            end
            
            @async for i in 1:50
                restore(cp, Symbol("key_$i"))
            end
            
            @async for i in 1:10
                get_checkpoints(cp)
            end
        end
        
        sleep(0.5)
        
        data = get_checkpoints(cp)
        @test length(data) > 0
        
        exit!(cp)
    end
    
    # --------------------------------------------------------------------------
    # Test: Worker Pool Exhaustion Recovery
    # Why: Worker pools can be exhausted in HPC scenarios.
    # Tests system recovery from worker exhaustion.
    # --------------------------------------------------------------------------
    @testset "Worker pool recovery" begin
        t_sv = Ref{Task}()
        
        sv = supervisor(:one_for_one, max_restarts=20, max_seconds=10, taskref=t_sv)
        
        workers = Link[]
        for i in 1:10
            w = spawn((msg) -> begin
                if msg == :work
                    sleep(0.1)
                    return :done
                elseif msg == :crash
                    error("Worker crash!")
                end
                return :idle
            end)
            supervise(sv, w, restart=:transient)
            push!(workers, w)
        end
        
        sleep(0.3)
        
        for w in workers[1:5]
            send(w, :crash)
        end
        
        sleep(1.0)
        
        @test t_sv[].state == :runnable
        
        exit!(sv)
    end
end

# ============================================================================
# HPC SCENARIO TESTS
# ============================================================================

@testset "HPC Scenarios" begin
    
    # --------------------------------------------------------------------------
    # Scenario: ML Pipeline with Model Checkpointing
    # Why: ML training requires periodic model checkpointing.
    # Tests complete ML pipeline with checkpointing.
    # --------------------------------------------------------------------------
    @testset "ML Pipeline with model checkpointing" begin
        cp = checkpointing(1, "ml_model_checkpoint.dat")
        
        model_state = Ref(Dict(
            :weights => rand(10, 10),
            :bias => rand(10),
            :step => 0,
            :loss => Inf
        ))
        
        function training_step(model, step)
            model[:weights] .+= rand(10, 10) .* 0.01
            model[:bias] .+= rand(10) .* 0.01
            model[:step] = step
            model[:loss] = 1.0 / (step + 1)
            return model
        end
        
        trainer = spawn((msg) -> begin
            if msg isa Tuple && first(msg) == :train
                _, num_steps = msg
                for step in 1:num_steps
                    model_state[] = training_step(model_state[], step)
                    
                    if step % 10 == 0
                        checkpoint(cp, :model_weights, model_state[][:weights])
                        checkpoint(cp, :model_bias, model_state[][:bias])
                        checkpoint(cp, :training_step, step)
                        checkpoint(cp, :current_loss, model_state[][:loss])
                    end
                end
                return :trained
            elseif msg == :get_model
                return model_state[]
            end
            return :unknown
        end)
        
        call(trainer, (:train, 50))
        sleep(0.3)
        
        saved_step = restore(cp, :training_step)
        saved_loss = restore(cp, :current_loss)
        
        @test saved_step == 50
        @test saved_loss < 1.0
        
        recovered_weights = restore(cp, :model_weights)
        @test size(recovered_weights) == (10, 10)
        
        exit!(trainer)
        exit!(cp)
        rm("ml_model_checkpoint.dat", force=true)
    end
    
    # --------------------------------------------------------------------------
    # Scenario: Distributed Aggregation Pattern
    # Why: Map-reduce patterns are common in HPC.
    # Tests distributed aggregation with multiple workers.
    # --------------------------------------------------------------------------
    @testset "Distributed map-reduce aggregation" begin
        partial_results = Dict{Int, Float64}()
        results_lock = ReentrantLock()
        
        aggregator = spawn((msg) -> begin
            if msg isa Tuple && first(msg) == :partial
                _, worker_id, value = msg
                lock(results_lock) do
                    partial_results[worker_id] = value
                end
                return :ack
            elseif msg == :get_results
                return copy(partial_results)
            elseif msg == :get_sum
                return sum(values(partial_results))
            end
            return :unknown
        end)
        
        num_mappers = 20
        
        mappers = Link[]
        for i in 1:num_mappers
            mapper = spawn((msg) -> begin
                if msg == :map
                    result = sum(rand(1000))
                    send(aggregator, (:partial, i, result))
                    return :done
                end
                return :idle
            end)
            push!(mappers, mapper)
        end
        
        sleep(0.3)
        
        @sync for m in mappers
            @async send(m, :map)
        end
        
        sleep(1.0)
        
        results = call(aggregator, :get_results)
        total = call(aggregator, :get_sum)
        
        @test length(results) >= num_mappers * 0.8
        @test total > 0
        
        for m in mappers
            exit!(m)
        end
        exit!(aggregator)
    end
    
    # --------------------------------------------------------------------------
    # Scenario: Stream Processing with Backpressure
    # Why: Stream processing systems need backpressure handling.
    # Tests pipeline with backpressure mechanism.
    # --------------------------------------------------------------------------
    @testset "Stream processing with backpressure" begin
        processed_count = Ref(0)
        buffer = Vector{Any}()
        buffer_lock = ReentrantLock()
        max_buffer = 50
        
        function can_accept()
            lock(buffer_lock) do
                return length(buffer) < max_buffer
            end
        end
        
        source = spawn((msg) -> begin
            if msg isa Tuple && first(msg) == :produce
                _, count = msg
                produced = 0
                for i in 1:count
                    while !can_accept()
                        sleep(0.01)
                    end
                    lock(buffer_lock) do
                        push!(buffer, i)
                    end
                    produced += 1
                end
                return produced
            end
            return :idle
        end)
        
        sink = spawn((msg) -> begin
            if msg == :consume
                while true
                    item = nothing
                    lock(buffer_lock) do
                        if !isempty(buffer)
                            item = popfirst!(buffer)
                        end
                    end
                    
                    if item !== nothing
                        processed_count[] += 1
                    else
                        sleep(0.01)
                    end
                end
            end
            return :idle
        end)
        
        send(sink, :consume)
        sleep(0.1)
        
        produced = call(source, (:produce, 100))
        sleep(1.0)
        
        @test produced > 0
        @test processed_count[] > 0
        
        exit!(source)
        exit!(sink)
    end
end

println("=" ^ 60)
println("PEDRO HPC Data Scientist Test Suite Completed")
println("=" ^ 60)
