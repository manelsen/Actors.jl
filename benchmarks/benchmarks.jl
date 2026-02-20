#
# Actors.jl benchmark suite
#
# Measures the three metrics that matter most for the v0.3.0 modernization:
#   1. Actor lifecycle (spawn + exit)      — target: ~10 μs  (currently ~50 μs)
#   2. Message latency (request round-trip) — target: ~20 μs  (currently ~100 μs)
#   3. Throughput (fire-and-forget cast)    — target: ~100K/s (currently ~10K/s)
#
# See CLAUDE.md § "Modernization Strategy" for full context.
#
# Usage:
#   julia --project=benchmarks benchmarks/runbenchmarks.jl         # run only
#   julia --project=benchmarks benchmarks/runbenchmarks.jl save    # save baseline
#   julia --project=benchmarks benchmarks/runbenchmarks.jl compare # compare to baseline
#

using BenchmarkTools
using Actors
import Actors: spawn, newLink

const SUITE = BenchmarkGroup()

# ── Behavior functions ────────────────────────────────────────────────────────
# Defined at module level so the JIT can specialize on them.

echo(x) = x                     # returns its argument (used for call/cast sync)
accum(acc::Ref, x) = acc[] += x  # accumulates into a Ref

# ── 1. Actor lifecycle ────────────────────────────────────────────────────────
# Measures the cost of spawn + exit. This is the baseline for "how expensive is
# an actor?" — directly maps to the memory-per-actor metric.

SUITE["spawn"] = BenchmarkGroup()

SUITE["spawn"]["no_args"] = @benchmarkable begin
    lk = spawn(echo)
    exit!(lk)
end

SUITE["spawn"]["with_args"] = @benchmarkable begin
    ref = Ref(0)
    lk = spawn(accum, ref)
    exit!(lk)
end

# Spawn on a specific thread (exercises the @threads branch in spawn)
if Threads.nthreads() >= 2
    SUITE["spawn"]["on_thread_2"] = @benchmarkable begin
        lk = spawn(echo, thrd=2)
        exit!(lk)
    end
end

# ── 2. Message latency ────────────────────────────────────────────────────────
# Measures round-trip time for a single request/response exchange.
# This is the "ping-pong latency" — the most important metric for interactive
# and reactive systems.

SUITE["latency"] = BenchmarkGroup()

# Single request to a live actor (actor stays alive across iterations)
SUITE["latency"]["single_request"] = @benchmarkable(
    request(lk, 42),
    setup    = (lk = spawn(echo)),
    teardown = exit!(lk)
)

# 100 sequential requests to the same actor — shows amortized latency
# and whether the actor loop has overhead that accumulates.
SUITE["latency"]["sequential_100"] = @benchmarkable(
    (for _ in 1:100; request(lk, 0); end),
    setup    = (lk = spawn(echo)),
    teardown = exit!(lk)
)

# Two-actor ping-pong: actor A sends to actor B and waits for the reply.
# Closer to real-world patterns where actors talk to each other.
function _pingpong(n::Int)
    pong = spawn(echo)
    for _ in 1:n
        request(pong, 0)
    end
    exit!(pong)
end

SUITE["latency"]["ping_pong_1"]   = @benchmarkable _pingpong(1)
SUITE["latency"]["ping_pong_100"] = @benchmarkable _pingpong(100)

# ── 3. Throughput ─────────────────────────────────────────────────────────────
# Measures fire-and-forget message rate: how fast can we push messages into
# an actor's mailbox? Terminated with a synchronizing call so we measure
# actual processing, not just enqueueing.

SUITE["throughput"] = BenchmarkGroup()

# N casts + 1 synchronizing call
function _throughput(lk, n::Int)
    for _ in 1:n
        cast(lk, 1)
    end
    call(lk, 0)   # synchronize: returns only after all casts are processed
end

SUITE["throughput"]["cast_100"] = @benchmarkable(
    _throughput(lk, 100),
    setup    = (lk = spawn(echo)),
    teardown = exit!(lk)
)

SUITE["throughput"]["cast_1000"] = @benchmarkable(
    _throughput(lk, 1000),
    setup    = (lk = spawn(echo)),
    teardown = exit!(lk)
)

# ── 4. Supervision ────────────────────────────────────────────────────────────
# Measures the overhead of the supervisor restart cycle: actor fails → supervisor
# detects → restart. This is critical for fault-tolerant systems.
#
# Design:
# - A shared Ref{Bool} lets the actor fail exactly once.
# - The measured expression snapshots lk.chn, triggers failure via cast, and
#   waits for restart_child! (supervisor.jl:80) to update lk.chn to the new
#   actor's channel.
#
# Two non-obvious correctness requirements:
#
# 1. sleep(0.05) in setup, before cast.
#    The actor's _act loop only calls onerror (which notifies the supervisor)
#    when A.conn is non-empty. A.conn is populated when the actor processes
#    Connect(Super(sv)), which is sent by the supervisor AFTER it processes the
#    Child message from start_actor. If cast fires before that Connect is
#    processed, A.conn is empty, the error silently kills the actor without
#    notifying the supervisor, and no restart ever happens.
#    The sleep gives the Julia scheduler time to run both the supervisor task
#    (processes Child → sends Connect) and the actor task (processes Connect →
#    A.conn populated) before we trigger the failure.
#
# 2. Detect restart via lk.chn identity, NOT by polling call(lk, ...).
#    After the actor crashes, its old Channel remains open but unread.
#    Each call() enqueues a Call message into that dead channel. The channel
#    buffer holds 32 slots; on the 33rd enqueue _send! calls wait(cond_put),
#    which blocks forever because no reader drains the dead channel → deadlock.
#    Watching lk.chn !== old_chn is O(1) and never blocks.
#
# 3. evals=1: each eval needs a fresh actor (it can only fail once per Ref).

SUITE["supervision"] = BenchmarkGroup()

SUITE["supervision"]["one_restart"] = @benchmarkable(
    begin
        old_chn = lk.chn
        cast(lk, 0)
        timedwait(2.0; pollint=0.001) do
            lk.chn !== old_chn
        end
    end,
    setup = begin
        failed = Ref(false)
        bhv = (x) -> begin
            if !failed[]
                failed[] = true
                error("intentional first failure")
            end
            x * 2
        end
        sv = supervisor(:one_for_one, max_restarts=3, max_seconds=10.0)
        lk = start_actor(bhv, sv)
        sleep(0.05)  # let supervisor send Connect to actor (see note 1 above)
    end,
    teardown = begin
        exit!(sv, :shutdown)
        sleep(0.05)
    end,
    evals = 1
)
