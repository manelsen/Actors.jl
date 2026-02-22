# Actors.jl Benchmark Suite & Architectural Decisions (v0.3.0)

This directory contains the performance validation suite for the Actors.jl v0.3.0 modernization. These benchmarks were instrumental in shaping the architectural shift from "task-bound channels" to "decoupled channel lifecycles."

## Core Metrics

The suite measures four critical dimensions of the actor system:
1. **Actor Lifecycle**: Cost of `spawn` + `exit!`. Target: ~10 μs.
2. **Message Latency**: Round-trip time for `request`. Target: ~20 μs.
3. **Throughput**: Fire-and-forget `cast` rate. Target: >100K msgs/sec.
4. **Supervision Overhead**: The cost of detection and restart cycles.

## Architectural Trade-offs: Adopted vs. Rejected

The benchmarks revealed several "traps" in the original implementation that informed the v0.3.0 architecture.

### 1. Channel Lifecycle Decoupling
*   **Rejected:** Keeping the `Channel` strictly bound to the `Task` (via `bind(ch, task)`).
*   **Problem:** If a task crashes, the channel closes immediately. Any messages sent during the supervisor's restart window are lost, returning an `InvalidStateException`.
*   **Adopted:** Decoupling the channel from the task. The channel stays open on crash if supervised.
*   **Result:** Zero message loss during restarts. The supervisor reuses the existing channel, preserving the mailbox.

### 2. Restart Detection Mechanism
*   **Rejected:** Polling the actor with `call(lk, ...)` to verify it's back online.
*   **Problem (Deadlock):** If the dead actor's channel is full (32 slots), a new `call` will block the sender indefinitely because no one is reading from the old channel. This creates a system-wide hang.
*   **Adopted:** O(1) identity check (`lk.chn !== old_chn`).
*   **Result:** Deterministic, non-blocking detection of actor restarts regardless of mailbox state.

### 3. Error Handling in Communication
*   **Rejected:** Relying solely on a `retry` loop in `send()`.
*   **Problem:** Retries mask the symptom but don't fix the race condition where a message might be accepted by a closing channel and then dropped.
*   **Adopted:** Supervisor-level "Drain and Pre-load". The supervisor drains stale `Exit` signals from the reused channel and pre-loads it with the new `Become` behavior and `Connect` signal before scheduling the new task.
*   **Result:** A "glitch-free" transition from a failed instance to a restarted one.

## Usage

```bash
# Run the full suite
julia --project=benchmarks benchmarks/runbenchmarks.jl

# Save a baseline to detect regressions
julia --project=benchmarks benchmarks/runbenchmarks.jl save

# Compare current performance against baseline
julia --project=benchmarks benchmarks/runbenchmarks.jl compare
```

*These benchmarks were executed with up to 20,000 iterations per sample to ensure statistical significance and to expose low-probability race conditions in concurrent paths.*
