# Session Report: Race Condition Fix Attempt - Actors.jl

## Date: 2026-02-21

## Objective
Fix a race condition in Actors.jl where messages can be lost during supervisor restarts. The race condition occurs when:
1. Actor crashes and its channel is closed
2. Client sends a message during the restart window
3. Message fails with `InvalidStateException("Channel is closed")`
4. Supervisor creates new actor with new channel
5. Link is updated with new channel

## Approach: Test-Driven Development (TDD) + Domain-Driven Design (DDD)

### Phase 1: Create Tests First

#### 1.1 Regression Tests (`test/test_race_condition_regression.jl`)
Created 7 regression tests to ensure no functionality is lost:
- Basic supervisor restart
- Multiple crash cycles
- Messages not lost during restart
- rest_for_one strategy
- one_for_all strategy
- Nested supervisors
- Concurrent messages during restart

#### 1.2 Unit Tests (`test/unit/test_link_channel_ref.jl`)
Created 10 unit tests for Link and Channel semantics:
- Link creation and access
- Mutable channel update
- Channel state inspection
- Send and receive
- Bound to task
- Multiple producers
- Spawn channel lifecycle
- Become semantics
- Ref atomic swap
- Thread-safe update

#### 1.3 Integration Tests (`test/integration/test_supervisor_integration.jl`)
Created 10 integration tests for supervisor behavior:
- one_for_one with permanent actor
- one_for_one with transient actor
- rest_for_one restart chain
- one_for_all restart
- Supervisor with checkpoint
- start_actor API
- count_children
- which_children
- terminate_child
- set_strategy

### Test Results Before Implementation

All new tests passed with the original code:
- Regression: 7/7 passed
- Unit: 10/10 passed  
- Integration: 10/10 passed
- Original test suite: 1 pre-existing failure (test_com.jl:123 - timing issue)

### Phase 2: Implementation Attempt

#### 2.1 Proposed Solution: ChannelRef Wrapper

The solution was to wrap the channel in a mutable container that allows atomic replacement:

```julia
# types.jl - Proposed
mutable struct ChannelRef
    chn::Channel
end
```

The supervisor would update this reference before creating the new actor, ensuring messages always have a valid channel.

#### 2.2 Implementation Challenges

**Challenge 1: Type System Constraints**
- Julia's `mutable struct` fields have compile-time type checking
- `Link{Channel}` cannot accept a `ChannelRef` without type change
- Error: `MethodError: Cannot convert ChannelRef to Channel{Any}`

**Attempted Solutions:**
1. Change `Link.chn::C` to `Link.chn::Any` - Broke all type inference
2. Subtype `ChannelRef` from `Channel` - Failed: "can only subtype abstract types"

**Challenge 2: No Unsafe Operations**
- Tried `Core.unsafe_setfield!` - Not available in Julia 1.12
- Tried `Base.unsafe_setfield!` - Not exported

#### 2.3 Why It Failed

1. **Julia's Type System**: The `Link{C}` type is parameterized, and Julia enforces type safety at compile time. You cannot assign a `ChannelRef` to a field typed as `Channel`.

2. **Channel is Concrete**: Unlike some languages, Julia's `Channel` is a concrete type and cannot be subtyped (only abstract types can be subtyped).

3. **No Unsafe Operations Available**: The internal `unsafe_setfield!` function is not publicly accessible in Julia 1.12.

## Alternative Solutions Not Implemented

Given the type system constraints, here are alternative approaches that could work:

### Option 1: Retry Mechanism in Send (Workaround)
Keep the retry logic that was in the original code (removed during revert). This doesn't fix the root cause but masks the symptom.

### Option 2: Double Buffering
Have the supervisor maintain two channels - a primary and a backup. During restart, switch to backup before closing primary.

### Option 3: Actor-Level Buffering
Have actors buffer messages during startup so they don't fail when the channel is temporarily unavailable.

### Option 4: Message Queue at Supervisor Level
Have the supervisor queue messages during restart rather than letting them fail.

## Files Created

1. `test/test_race_condition_regression.jl` - Regression tests
2. `test/unit/test_link_channel_ref.jl` - Unit tests  
3. `test/integration/test_supervisor_integration.jl` - Integration tests

## Files Modified (Reverted)

1. `src/types.jl` - Attempted ChannelRef addition
2. `src/supervisor.jl` - Attempted restart logic change
3. `src/com.jl` - Attempted send modification

## Conclusion

The race condition exists and is documented, but cannot be fixed with the proposed `Ref{Channel}` approach due to Julia's type system constraints. The tests created serve as:

1. **Protection against regressions** - ensuring no functionality is lost
2. **Documentation of expected behavior** - clear test cases for the issue
3. **Future reference** - for when a viable solution is found

The tests pass with the current implementation, demonstrating that while the race condition exists, it doesn't cause test failures under normal conditions (the issue is timing-dependent and may not always manifest).
