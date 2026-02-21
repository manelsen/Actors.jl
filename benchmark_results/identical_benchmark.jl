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
