#
# Actors.jl benchmark runner
#
# Modes:
#   (no args)  — run benchmarks, print median results
#   save       — run benchmarks, save results as baseline.json
#   compare    — run benchmarks, compare against saved baseline.json
#               exits with code 1 if any regression is detected
#
# Usage:
#   julia --project=benchmarks benchmarks/runbenchmarks.jl
#   julia --project=benchmarks benchmarks/runbenchmarks.jl save
#   julia --project=benchmarks benchmarks/runbenchmarks.jl compare
#

include("benchmarks.jl")

using BenchmarkTools

const BASELINE_FILE = joinpath(@__DIR__, "baseline.json")
const mode = length(ARGS) > 0 ? ARGS[1] : "run"

println("=" ^ 60)
println("Actors.jl Benchmark Suite")
println("Julia: ", VERSION, "  Threads: ", Threads.nthreads())
println("Mode: ", mode)
println("=" ^ 60)

println("\nTuning benchmarks (estimating sample counts)...")
BenchmarkTools.tune!(SUITE)

println("Running benchmarks...\n")
results = run(SUITE, verbose=true)

println("\n── Median results ──────────────────────────────────────────")
show(stdout, MIME("text/plain"), median(results))
println()

if mode == "save"
    BenchmarkTools.save(BASELINE_FILE, results)
    println("\nBaseline saved to: $BASELINE_FILE")
    println("Run with 'compare' after your next change to detect regressions.")

elseif mode == "compare"
    if !isfile(BASELINE_FILE)
        error("""
        No baseline found at $BASELINE_FILE.
        Run with 'save' first to establish a baseline.
        """)
    end

    baseline = BenchmarkTools.load(BASELINE_FILE)[1]
    comparison = judge(median(results), median(baseline))

    println("\n── Comparison to baseline ──────────────────────────────────")
    show(stdout, MIME("text/plain"), comparison)
    println()

    # Collect regressions (time or memory got worse)
    regressions = BenchmarkTools.regressions(comparison)

    if isempty(regressions)
        println("\n✓ No regressions detected.")
    else
        println("\n✗ Regressions detected:")
        for (keys, trial) in leaves(regressions)
            println("  - ", join(keys, "/"), ": ", trial)
        end
        exit(1)
    end
end
