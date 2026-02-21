#!/usr/bin/env julia
#
# Comparative benchmark runner for Actors.jl branches
# Uses IDENTICAL benchmark script for all branches
#

using Pkg
using Dates

const BRANCHES = ["GLM", "Claude", "Kimi-Muda"]
const RESULTS_DIR = "benchmark_results"

# Create results directory
mkpath(RESULTS_DIR)

println("="^60)
println("ACTORS.JL COMPARATIVE BENCHMARK RUNNER")
println("Using IDENTICAL benchmark script for all branches")
println("="^60)
println()

# Save current benchmark script to use for all branches
const BENCHMARK_SCRIPT = raw"""
using Actors
using BenchmarkTools
import Actors: spawn

echo(x) = x

results = Dict{String,Float64}()

println("Benchmarking spawn (no args)...")
b_spawn = @benchmark begin
    lk = spawn(echo)
    exit!(lk)
end samples=100 evals=3
results["spawn_no_args"] = median(b_spawn).time / 1000

println("Benchmarking single request...")
b_single = @benchmark begin
    lk = spawn(echo)
    request(lk, 42)
    exit!(lk)
end samples=100 evals=3
results["single_request"] = median(b_single).time / 1000

println("Benchmarking ping_pong_1...")
b_pp1 = @benchmark begin
    pong = spawn(echo)
    request(pong, 0)
    exit!(pong)
end samples=100 evals=3
results["ping_pong_1"] = median(b_pp1).time / 1000

println("Benchmarking ping_pong_100...")
b_pp100 = @benchmark begin
    pong = spawn(echo)
    for _ in 1:100
        request(pong, 0)
    end
    exit!(pong)
end samples=50 evals=1
results["ping_pong_100"] = median(b_pp100).time / 1000

println("Benchmarking sequential_100...")
b_seq = @benchmark begin
    lk = spawn(echo)
    for _ in 1:100
        request(lk, 0)
    end
    exit!(lk)
end samples=50 evals=1
results["sequential_100"] = median(b_seq).time / 1000

println("Benchmarking cast_100...")
b_cast100 = @benchmark begin
    lk = spawn(echo)
    for _ in 1:100
        cast(lk, 1)
    end
    call(lk, 0)
    exit!(lk)
end samples=50 evals=1
results["cast_100"] = median(b_cast100).time / 1000

println("Benchmarking cast_1000...")
b_cast1000 = @benchmark begin
    lk = spawn(echo)
    for _ in 1:1000
        cast(lk, 1)
    end
    call(lk, 0)
    exit!(lk)
end samples=20 evals=1
results["cast_1000"] = median(b_cast1000).time / 1000

println("")
println("===RESULTS_START===")
for (k, v) in results
    println(string(k, "=", v))
end
println("===RESULTS_END===")
"""

# Write benchmark script to temp file
const TEMP_BENCH_FILE = joinpath(RESULTS_DIR, "identical_benchmark.jl")
open(TEMP_BENCH_FILE, "w") do f
    write(f, BENCHMARK_SCRIPT)
end

println("Using identical benchmark script: $TEMP_BENCH_FILE")
println()

all_results = Dict{String, Dict{String, Float64}}()

for branch in BRANCHES
    println("\n" * "="^60)
    println("BRANCH: $branch")
    println("="^60)
    
    # Checkout branch
    try
        run(`git checkout $branch`)
        sleep(1)
    catch e
        println("Error checking out $branch: $e")
        all_results[branch] = Dict{String, Float64}()
        continue
    end
    
    # Setup dependencies
    println("Setting up dependencies for $branch...")
    try
        Pkg.activate(".")
        Pkg.instantiate(; allow_autoprecomp=true)
        Pkg.precompile()
        
        # Add BenchmarkTools if not present
        try
            Pkg.add("BenchmarkTools")
        catch
            println("BenchmarkTools may already be installed")
        end
    catch e
        println("Warning during dependency setup: $e")
        println("Attempting to continue...")
    end
    
    println("\nRunning IDENTICAL benchmarks on $branch...")
    println("(This may take 2-3 minutes)")
    println()
    
    # Run the SAME benchmark script
    output = ""
    try
        output = read(`julia --project=. $TEMP_BENCH_FILE`, String)
    catch e
        println("Error running benchmarks: $e")
        # Try to get partial output
        try
            output = read(`julia --project=. $TEMP_BENCH_FILE`, String)
        catch
            output = ""
        end
    end
    
    # Parse results
    branch_results = Dict{String, Float64}()
    
    if occursin("===RESULTS_START===", output) && occursin("===RESULTS_END===", output)
        m = match(r"===RESULTS_START===(.*)===RESULTS_END==="s, output)
        if m !== nothing
            for line in split(m.captures[1], "\n")
                if contains(line, "=")
                    parts = split(line, "=")
                    if length(parts) == 2
                        key = strip(parts[1])
                        try
                            value = parse(Float64, strip(parts[2]))
                            branch_results[key] = value
                        catch
                            println("Could not parse: $line")
                        end
                    end
                end
            end
        end
    else
        println("No results found in output")
        println("Output was: ", length(output), " chars")
    end
    
    all_results[branch] = branch_results
    
    if !isempty(branch_results)
        println("\nResults for $branch:")
        for (k, v) in sort(collect(branch_results))
            println("  $k: $(round(v, digits=2)) μs")
        end
    else
        println("\nNo results for $branch")
    end
    
    println("\nCompleted $branch")
end

# Return to GLM
try
    run(`git checkout GLM`)
catch
end

println("\n" * "="^60)
println("GENERATING FINAL_COUNTDOWN.md")
println("="^60)

# Helper function
function get_score(data, branch)
    filtered = filter(x -> !isnan(x[2]), data)
    if isempty(filtered)
        return 0
    end
    sorted = sort(filtered, by=x->x[2])
    idx = findfirst(x -> x[1] == branch, sorted)
    return idx !== nothing ? length(sorted) - idx + 1 : 0
end

# Generate comparison document
open("FINAL_COUNTDOWN.md", "w") do f
    write(f, """
# FINAL_COUNTDOWN.md

**Actors.jl Branch Performance Comparison**

**Generated:** $(Dates.now())
**Benchmark Script:** Identical for all branches (see `benchmark_results/identical_benchmark.jl`)
**Branches Compared:** $(join(BRANCHES, ", "))

---

## Methodology

All three branches were tested using **exactly the same benchmark script** to ensure fair comparison. Each benchmark:
- Runs with adequate sample size (50-100 samples)
- Reports median time in microseconds (μs)
- Tests the same operations: spawn, request, cast, ping-pong

**Lower values = Better performance**

---

## Results

### 1. Spawn Performance (μs)

Time to create and destroy an actor.

| Branch | Time (μs) | Relative |
|--------|-----------|----------|
""")
    
    spawn_data = [(b, get(all_results[b], "spawn_no_args", NaN)) for b in BRANCHES]
    valid_spawn = filter(x -> !isnan(x[2]), spawn_data)
    if !isempty(valid_spawn)
        sort!(spawn_data, by=x->isnan(x[2]) ? Inf : x[2])
        best_spawn = spawn_data[1][2]
        
        for (branch, time) in spawn_data
            if isnan(time)
                write(f, "| $branch | FAILED | - |\n")
            else
                rel = round(time/best_spawn, digits=2)
                write(f, "| $branch | $(round(time, digits=2)) | $(rel)x |\n")
            end
        end
    else
        write(f, "| - | No valid results | - |\n")
    end
    
    write(f, """

### 2. Single Request Latency (μs)

Time for one request/response cycle.

| Branch | Time (μs) | Relative |
|--------|-----------|----------|
""")
    
    single_data = [(b, get(all_results[b], "single_request", NaN)) for b in BRANCHES]
    valid_single = filter(x -> !isnan(x[2]), single_data)
    if !isempty(valid_single)
        sort!(single_data, by=x->isnan(x[2]) ? Inf : x[2])
        best_single = single_data[1][2]
        
        for (branch, time) in single_data
            if isnan(time)
                write(f, "| $branch | FAILED | - |\n")
            else
                rel = round(time/best_single, digits=2)
                write(f, "| $branch | $(round(time, digits=2)) | $(rel)x |\n")
            end
        end
    else
        write(f, "| - | No valid results | - |\n")
    end
    
    write(f, """

### 3. Ping-Pong Latency (μs)

**Single ping-pong:**

| Branch | Time (μs) | Relative |
|--------|-----------|----------|
""")
    
    pp1_data = [(b, get(all_results[b], "ping_pong_1", NaN)) for b in BRANCHES]
    valid_pp1 = filter(x -> !isnan(x[2]), pp1_data)
    if !isempty(valid_pp1)
        sort!(pp1_data, by=x->isnan(x[2]) ? Inf : x[2])
        best_pp1 = pp1_data[1][2]
        
        for (branch, time) in pp1_data
            if isnan(time)
                write(f, "| $branch | FAILED | - |\n")
            else
                rel = round(time/best_pp1, digits=2)
                write(f, "| $branch | $(round(time, digits=2)) | $(rel)x |\n")
            end
        end
    else
        write(f, "| - | No valid results | - |\n")
    end
    
    write(f, """

**100 ping-pongs:**

| Branch | Time (μs) | Relative |
|--------|-----------|----------|
""")
    
    pp100_data = [(b, get(all_results[b], "ping_pong_100", NaN)) for b in BRANCHES]
    valid_pp100 = filter(x -> !isnan(x[2]), pp100_data)
    if !isempty(valid_pp100)
        sort!(pp100_data, by=x->isnan(x[2]) ? Inf : x[2])
        best_pp100 = pp100_data[1][2]
        
        for (branch, time) in pp100_data
            if isnan(time)
                write(f, "| $branch | FAILED | - |\n")
            else
                rel = round(time/best_pp100, digits=2)
                write(f, "| $branch | $(round(time, digits=2)) | $(rel)x |\n")
            end
        end
    else
        write(f, "| - | No valid results | - |\n")
    end
    
    write(f, """

### 4. Sequential Requests (μs)

100 sequential requests to same actor.

| Branch | Time (μs) | Relative |
|--------|-----------|----------|
""")
    
    seq_data = [(b, get(all_results[b], "sequential_100", NaN)) for b in BRANCHES]
    valid_seq = filter(x -> !isnan(x[2]), seq_data)
    if !isempty(valid_seq)
        sort!(seq_data, by=x->isnan(x[2]) ? Inf : x[2])
        best_seq = seq_data[1][2]
        
        for (branch, time) in seq_data
            if isnan(time)
                write(f, "| $branch | FAILED | - |\n")
            else
                rel = round(time/best_seq, digits=2)
                write(f, "| $branch | $(round(time, digits=2)) | $(rel)x |\n")
            end
        end
    else
        write(f, "| - | No valid results | - |\n")
    end
    
    write(f, """

### 5. Throughput - Cast (μs)

**100 casts:**

| Branch | Time (μs) | Relative |
|--------|-----------|----------|
""")
    
    cast100_data = [(b, get(all_results[b], "cast_100", NaN)) for b in BRANCHES]
    valid_cast100 = filter(x -> !isnan(x[2]), cast100_data)
    if !isempty(valid_cast100)
        sort!(cast100_data, by=x->isnan(x[2]) ? Inf : x[2])
        best_cast100 = cast100_data[1][2]
        
        for (branch, time) in cast100_data
            if isnan(time)
                write(f, "| $branch | FAILED | - |\n")
            else
                rel = round(time/best_cast100, digits=2)
                write(f, "| $branch | $(round(time, digits=2)) | $(rel)x |\n")
            end
        end
    else
        write(f, "| - | No valid results | - |\n")
    end
    
    write(f, """

**1000 casts:**

| Branch | Time (μs) | Relative |
|--------|-----------|----------|
""")
    
    cast1000_data = [(b, get(all_results[b], "cast_1000", NaN)) for b in BRANCHES]
    valid_cast1000 = filter(x -> !isnan(x[2]), cast1000_data)
    if !isempty(valid_cast1000)
        sort!(cast1000_data, by=x->isnan(x[2]) ? Inf : x[2])
        best_cast1000 = cast1000_data[1][2]
        
        for (branch, time) in cast1000_data
            if isnan(time)
                write(f, "| $branch | FAILED | - |\n")
            else
                rel = round(time/best_cast1000, digits=2)
                write(f, "| $branch | $(round(time, digits=2)) | $(rel)x |\n")
            end
        end
    else
        write(f, "| - | No valid results | - |\n")
    end
    
    # Overall scoring
    write(f, """

---

## Overall Scoring

Points per benchmark: 1st place = 3 pts, 2nd = 2 pts, 3rd = 1 pt

| Branch | Spawn | Single | PP1 | PP100 | Seq | Cast100 | Cast1000 | TOTAL |
|--------|-------|--------|-----|-------|-----|---------|----------|-------|
""")
    
    scores = Dict{String, Int}()
    for branch in BRANCHES
        scores[branch] = 0
    end
    
    for branch in BRANCHES
        s = get_score(spawn_data, branch)
        si = get_score(single_data, branch)
        p1 = get_score(pp1_data, branch)
        p100 = get_score(pp100_data, branch)
        sq = get_score(seq_data, branch)
        c100 = get_score(cast100_data, branch)
        c1000 = get_score(cast1000_data, branch)
        total = s + si + p1 + p100 + sq + c100 + c1000
        
        write(f, "| $branch | $s | $si | $p1 | $p100 | $sq | $c100 | $c1000 | **$total** |\n")
        scores[branch] = total
    end
    
    # Winner (only if we have results)
    valid_scores = filter(x -> x[2] > 0, collect(scores))
    if !isempty(valid_scores)
        winner = valid_scores[argmax([x[2] for x in valid_scores])][1]
        write(f, """

---

## Winner

**$winner** with $(scores[winner]) points

""")
    else
        write(f, """

---

## Status

**Benchmarks failed for all branches.** Check the console output for errors.

""")
    end
    
    write(f, """

---

## Technical Summary

| Branch | Key Innovation |
|--------|----------------|
| **GLM** | Type-stable _ACT{B,R,S,U}, batch processing, fast receive |
| **Claude** | Simplified types, minimal overhead |
| **Kimi-Muda** | Response channel reuse, reduced allocations |

---

*Generated by `run_all_benchmarks.jl`*
""")
end

println("\n" * "="^60)
println("DONE!")
println("="^60)
println("\nResults saved in: $RESULTS_DIR")
println("Comparison document: FINAL_COUNTDOWN.md")
