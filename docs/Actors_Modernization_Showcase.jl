### A Pluto.jl Notebook ###
# v0.4.0 - THE DEFINITIVE BENCHMARK SHOWCASE
# 
# This notebook runs the full Actors.jl benchmark suite (v0.3.0).
# It covers Lifecycle, Latency, Throughput, and Supervision.

begin
	import Pkg
	Pkg.activate("..")
	using Actors
	using BenchmarkTools
	using Plots
	using Dates
	using Statistics
end

md"""
# 🚀 Actors.jl v0.3.0: Full Performance & Reliability Suite
**Architected by manelsen**

This notebook executes the complete benchmark suite used to validate the v0.3.0 modernization. We compare the results against the system's target metrics.
"""

begin
	# Helper behavior for benchmarks
	echo(x) = x
end

# --- SECTION 1: ACTOR LIFECYCLE ---
md"""
## 1. Actor Lifecycle (Spawn + Exit)
How expensive is it to create and destroy an actor? This metric defines the "granularity" of the system.
*Target: < 15 μs*
"""

begin
	bench_spawn = @benchmark begin
		lk = spawn(echo)
		exit!(lk)
	end
	
	md"**Current Result:** $(round(median(bench_spawn).time / 1000, digits=2)) μs"
end

# --- SECTION 2: MESSAGE LATENCY ---
md"""
## 2. Message Latency (Round-trip)
The "Ping-Pong" time. This is the most critical metric for interactive and reactive systems.
*Target: < 30 μs*
"""

begin
	function latency_test()
		lk = spawn(echo)
		t = @belapsed request($lk, 42)
		exit!(lk)
		return t
	end
	
	current_latency = latency_test()
	md"**Current Result:** $(round(current_latency * 1e6, digits=2)) μs"
end

# --- SECTION 3: THROUGHPUT ---
md"""
## 3. Throughput (Fire-and-Forget)
How many messages can the system process per second? This exercises our new **Buffer Draining** optimization.
*Target: > 100,000 msgs/sec*
"""

begin
	function throughput_test(n=10000)
		lk = spawn(echo)
		start = time()
		for i in 1:n
			cast(lk, i)
		end
		call(lk, :sync) # Ensure all are processed
		duration = time() - start
		exit!(lk)
		return n / duration
	end
	
	current_tp = throughput_test()
	md"**Current Result:** $(round(current_tp, digits=0)) messages/second"
end

# --- SECTION 4: SUPERVISION OVERHEAD ---
md"""
## 4. Supervision: Restart Cycle Time
This measures the time from an actor crash to the supervisor completing the restart. 
This exercises our **Channel Reuse** architecture.
"""

begin
	function supervision_bench()
		failed = Ref(false)
		bhv = (x) -> begin
			if !failed[]
				failed[] = true
				error("Intentional")
			end
			x
		end
		sv = supervisor(:one_for_one, max_restarts=10)
		lk = start_actor(bhv, sv)
		
		old_chn = lk.chn
		start_t = time_ns()
		cast(lk, 0) # Trigger crash
		
		# Wait for restart detection (Channel Reuse Identity check)
		while lk.chn === old_chn && (time_ns() - start_t) < 1e9
			yield()
		end
		
		duration = (time_ns() - start_t) / 1e6
		exit!(sv, :shutdown)
		return duration
	end
	
	restart_time = supervision_bench()
	md"**Current Result:** $(round(restart_time, digits=2)) ms per restart cycle."
end

md"""
## 5. Summary of Improvements
The v0.3.0 modernization provides:
1. **Deterministic Latency:** Through thread pinning.
2. **High Throughput:** Through message draining.
3. **Zero Loss:** Through channel reuse in the supervisor.
"""

# Visual Summary Plot
begin
	metrics = ["Spawn (μs)", "Latency (μs)", "Restart (ms)"]
	values = [median(bench_spawn).time/1000, current_latency*1e6, restart_time]
	
	bar(metrics, values, title="v0.3.0 Key Performance Indicators", 
		ylabel="Value (lower is better)", color=:blue, legend=false)
end
