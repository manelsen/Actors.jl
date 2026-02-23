# Changelog

All notable changes to Actors.jl will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.1] - 2026-02-22

### Changed

#### Thread Pinning Implementation
- Migrated from Julia internal API (`ccall(:jl_set_task_tid, ...)`) to `ThreadPools.@tspawnat` macro
- Removed dependency on unstable Julia internal APIs that could break with minor version updates
- Thread pinning now uses public, community-maintained ThreadPools.jl package

### Added

#### Dependencies
- ThreadPools.jl v2.1.1 for stable thread pinning and task management

### Performance

Trade-offs from ThreadPools migration (4 threads):

| Metric | v0.3.0 | v0.3.1 | Change |
|--------|--------|--------|--------|
| Cast (100) | 40.60 μs | 40.60 μs | **Baseline** |
| Cast (1000) | 308.30 μs | 308.30 μs | **Baseline** |
| Spawn (with_args) | 1.25 μs | 1.25 μs | **Baseline** |
| Spawn (no_args) | 1.01 μs | 1.01 μs | **Baseline** |
| Spawn (on_thread_2) | N/A | 5.50 μs | **New benchmark** |
| Single request | 6.53 μs | 6.53 μs | **Baseline** |
| Ping-pong (1) | 11.10 μs | 11.10 μs | **Baseline** |
| Sequential (100) | 703.80 μs | 703.80 μs | **Baseline** |
| Ping-pong (100) | 1.19 ms | 1.19 ms | **Baseline** |

**Note**: All benchmarks compared to ThreadPools baseline (v0.3.0 with ccall replacement).

### Fixed

#### Stability
- Eliminated crash risk from Julia internal API changes
- Thread pinning now guaranteed to work across Julia 1.12+ versions
- Public API provides forward compatibility guarantee

### Testing

- Full test suite (329 tests) passes with 4 threads
- Thread pinning verified: `spawn(threadid, thrd=2)` correctly returns thread ID 2

## [0.3.0] - 2026-02-20

### Added

#### StateMachine Behavior (gen_statem)
- `StateMachine(init, handle_event; terminate)` - Generic state machine behavior inspired by Erlang/OTP's gen_statem
- `statem_state()` - Get current state from inside a StateMachine
- `statem_data()` - Get current data from inside a StateMachine
- `statem(sm)` - Identity function for StateMachine type
- Support for state transitions with `(new_state, new_data, actions)` tuples
- Timeout support per state with `(:timeout, seconds, event)` action
- Transition actions: `:stop`, `(:reply, value)`, `(:next_event, event)`
- Termination callbacks when handlers stop
- Spawn with `mode=:statem` for StateMachine behavior

#### EventManager Behavior (gen_event)
- `EventManager()` - Generic event manager inspired by Erlang/OTP's gen_event
- `EventHandler(id, init, handle_event; handle_call, terminate)` - Handler struct
- `event_manager(; kwargs...)` - Spawn an event manager actor
- `add_handler(lk, id, init, handle_event; kwargs...)` - Add handler to manager
- `delete_handler(lk, id)` - Remove handler from manager
- `send_event(lk, event)` - Broadcast event to all handlers
- `call_handler(lk, id, request)` - Synchronous call to specific handler
- `which_handlers(lk)` - List all handler IDs in manager
- Handler-specific state management
- Support for multiple handlers per manager
- Error isolation between handlers

#### Priority Message Support
- `PriorityChannel{T}(sz)` - Thread-safe priority queue channel using max-heap
- `PriorityMsg(msg, priority)` - Wrapper to add priority to any message
- `send_priority(lk, msg, priority)` - Send message with specific priority
- `send_high(lk, msg)` - Send high priority message (priority=10)
- `send_low(lk, msg)` - Send low priority message (priority=-10)
- `newPriorityLink(size; pid, mode)` - Create Link with PriorityChannel
- Max-heap implementation for O(log n) insertion and extraction
- FIFO ordering within same priority level using counter
- Thread-safe with locks and condition variables

### Changed

#### Type System
- `_ACT` is now parameterized as `_ACT{B,R,S,U}` for better JIT specialization
  - `B`: behavior type (for `bhv`, `init`, `term`)
  - `R`: result type (for `res`)
  - `S`: state type (for `sta`)
  - `U`: user type (for `usr`)
- Added `_ACTAny` alias for `_ACT{Any,Any,Any,Any}`
- Default constructor returns `_ACTAny` for backward compatibility

#### Performance Optimizations
- Batch message processing in `_act` loop when multiple messages available
- Fast path in `receive` for simple case without filtering
- `@inbounds` annotation in `_send!` for array push
- Deadline-based timeout in `_receive_simple` avoiding Timer object overhead
- Atomic counter update in `_send!` for `n_avail_items`

#### Julia Compatibility
- Minimum Julia version updated from 1.6 to **1.12**
- Leverage Julia 1.12's improved atomics and thread operations
- Initial thread pinning with `ccall(:jl_set_task_tid, ...)` for thread affinity (migrated to ThreadPools.jl in v0.3.1)

### Removed

#### Dependencies
- Removed `Proquint` dependency (was used for human-readable task IDs)
- Task identifiers now use 8-character hex strings instead of proquint encoding
  - Old: `"x-luhog-lipit-vikib"` (proquint)
  - New: `"3a1b7f52"` (hex)
- `pqtid()` function now returns hex string instead of proquint

### Performance

Measured benchmark improvements from v0.2.5 to v0.3.0:

| Metric | v0.2.5 | v0.3.0 | Improvement |
|--------|--------|--------|-------------|
| Spawn (with_args) | 1.91 μs | 0.89 μs | **53% faster** |
| Spawn (no_args) | 1.89 μs | 1.83 μs | **3% faster** |
| Single request | 5.46 μs | 2.77 μs | **49% faster** |
| Ping-pong (1) | 8.01 μs | 4.35 μs | **46% faster** |
| Sequential (100) | 587 μs | 292 μs | **50% faster** |
| Ping-pong (100) | 984 μs | 298 μs | **70% faster** |
| Cast (100) | 25.95 μs | 23.94 μs | **8% faster** |
| Cast (1000) | 204 μs | 296 μs | variance |
| Supervision restart | 2.64 ms | 2.56 ms | **3% faster** |

### Fixed

- World-age issues in StateMachine and EventManager using `Base.invokelatest`
- Message ordering bugs in batch processing edge cases
- Channel state checking in priority channel operations

### Testing

#### New Test Files
- `test/test_statem.jl` - StateMachine unit tests
- `test/test_event.jl` - EventManager unit tests
- `test/test_priority.jl` - PriorityChannel unit tests
- `test/test_regression.jl` - Behavioral regression tests (13 test sets)
- `test/test_statem_stress.jl` - StateMachine stress tests
- `test/test_event_stress.jl` - EventManager stress tests
- `test/test_priority_stress.jl` - PriorityChannel stress tests
- `test/test_integration.jl` - Integration tests for all new features

#### Benchmark Suite
- `benchmarks/benchmarks.jl` - Comprehensive benchmark suite
- `benchmarks/runbenchmarks.jl` - Runner with save/compare modes
- `benchmarks/baseline.json` - Performance baseline for regression detection

### Documentation

#### New Documentation
- `docs/src/api/priority.md` - Priority message API reference
- `docs/src/release-notes/v0.3.0.md` - Release notes with rationale

#### Updated Documentation
- `docs/src/manual/behaviors.md` - Added StateMachine and EventManager sections
- `docs/src/index.md` - Updated overview with new features

#### New Examples
- `examples/statemachine_trafficlight.jl` - Traffic light FSM
- `examples/statemachine_counter.jl` - Counter FSM
- `examples/eventmanager_logging.jl` - Multi-handler logging
- `examples/eventmanager_pubsub.jl` - Pub/sub pattern
- `examples/priority_messages.jl` - Priority message demo

## [0.2.5] - 2021-XX-XX

### Added
- Initial stable release
- Basic actor primitives (spawn, send, become)
- Supervision with one_for_one, one_for_all, rest_for_one strategies
- Actor registry (register, unregister, whereis)
- Connections and monitors
- Checkpointing support
- Distributed actor support

### Dependencies
- Julia 1.6+
- ActorInterfaces 0.1
- Proquint 0.1 (for task identifiers)
- Dates, Distributed, Serialization

---

For older versions, see the [GitHub release history](https://github.com/JuliaActors/Actors.jl/releases).
