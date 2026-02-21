# Personas and Test Cases Documentation - Actors.jl

## Overview

This document describes the personas created to test the Actors.jl library from multiple usage perspectives, covering complex use cases, edge cases, and potential vulnerabilities.

---

## Persona 1: Mariana - Distributed Systems Architect

### Profile
- **Experience**: 15 years in distributed systems
- **Focus**: High availability, fault tolerance, eventual consistency
- **Context**: Banking systems, e-commerce, processing clusters

### Complex Use Cases

| Case | Description | Components Tested |
|------|-------------|-------------------|
| Banking System | Data replication with automatic failover | Supervisor (:one_for_all), hierarchical Checkpointing |
| E-commerce | Shopping cart with dependents | Supervisor (:rest_for_one), multiple actors |
| Cluster | Automatic failover between nodes | Supervisor, Registry, Connections |

### Tests Created

#### Stress Tests
1. **10 rapid failover cycles** - Tests restart capabilities under load
2. **Hierarchical Checkpointing 3 levels** - Tests aggregation of checkpoints
3. **Dependent actor chain** - Tests :rest_for_one strategy

#### Edge Cases
1. **Exit during restart** - Race condition during recovery
2. **Checkpoint with nil/NaN values** - Data robustness
3. **Actor dies during checkpoint** - Data integrity
4. **Cascading shutdown** - Nested supervisors

#### Vulnerabilities
1. **Memory leak in restart loops** - Memory management
2. **Race condition in supervise/unsupervise** - Thread-safety
3. **Deadlock in nested supervisors** - Circular structures
4. **Max restarts exceeded** - Protection against infinite loops

---

## Persona 2: Ricardo - Real-Time Systems Developer

### Profile
- **Experience**: 10 years in embedded and real-time systems
- **Focus**: Low latency, determinism, prioritization
- **Context**: Air traffic control, high-frequency trading, industrial control

### Complex Use Cases

| Case | Description | Components Tested |
|------|-------------|-------------------|
| ATC | Air traffic controller | StateMachine, Priority |
| HFT | Trading system | PriorityChannel, low latency |
| Industrial | Controller with emergencies | StateMachine, timeouts, priorities |

### Tests Created

#### Stress Tests
1. **10000 state transitions** - StateMachine throughput
2. **5000 priority messages** - PriorityChannel flood
3. **5000 events/second** - EventManager throughput

#### Edge Cases
1. **Timeout during transition** - StateMachine with timeout
2. **Priority inversion** - Starvation prevention
3. **Unknown event** - StateMachine resilience
4. **Concurrent events** - Transition thread-safety

#### Vulnerabilities
1. **Invalid state injection** - Input validation
2. **Low priority starvation** - Scheduler fairness
3. **Exception isolation in handlers** - Fault tolerance
4. **Stop action** - Proper termination

---

## Persona 3: Sofia - Security Engineer

### Profile
- **Experience**: 12 years in software security
- **Focus**: Vulnerabilities, attacks, hardening
- **Context**: Penetration testing, code review, system security

### Complex Use Cases (Attacker Perspective)

| Case | Description | Components Tested |
|------|-------------|-------------------|
| Injection | Malicious messages | Protocol, onmessage |
| DoS | Resource exhaustion | Channels, Tasks |
| Leakage | Unauthorized access | Query, Diag |
| Escalation | Control bypass | Registry, Connections |

### Tests Created

#### Stress Tests
1. **Actor explosion (500)** - Mass creation
2. **Channel exhaustion** - Message flood
3. **Memory pressure** - Large messages

#### Edge Cases
1. **Nil/Nothing** - Null values
2. **NaN/Inf** - Special values
3. **Empty messages** - Empty tuples and strings
4. **Extreme timeouts** - Negative values
5. **Circular references** - Cyclic structures

#### Vulnerabilities
1. **Concurrent state modification** - Race conditions
2. **Become race condition** - Behavior swapping
3. **Registry race condition** - Concurrent registration
4. **Exception isolation** - Error propagation
5. **Stack overflow** - Infinite recursion
6. **MethodError** - Incorrect types
7. **Information exposure** - Query and Diag
8. **Connection flood** - Resources
9. **Monitor flood** - Resources

---

## Persona 4: Pedro - HPC Data Scientist

### Profile
- **Experience**: 8 years in high-performance computing
- **Focus**: Parallel processing, checkpointing, aggregation
- **Context**: ML pipelines, Monte Carlo simulations, streaming

### Complex Use Cases

| Case | Description | Components Tested |
|------|-------------|-------------------|
| ML Pipeline | Training with checkpointing | Periodic checkpointing |
| Monte Carlo | Mass simulation | Multiple workers, aggregation |
| Streaming | Pipeline with backpressure | Flow control |

### Tests Created

#### Stress Tests
1. **200 Monte Carlo workers** - Massive parallelism
2. **1000 checkpoints** - Checkpointing throughput
3. **3-level hierarchy** - Multi-level checkpointing

#### Edge Cases
1. **Worker dies during checkpoint** - Integrity
2. **File persistence** - Save/Load
3. **Empty checkpoint** - Error handling
4. **Checkpoint overwrite** - Update

#### Vulnerabilities
1. **Corrupted checkpoint** - Recovery
2. **Memory in large checkpoints** - Management
3. **Concurrent operations** - Thread-safety
4. **Worker pool exhaustion** - Recovery

---

## Persona 5: Ana - IoT/Edge Developer

### Profile
- **Experience**: 6 years in embedded and IoT systems
- **Focus**: Events, resilient connections, limited resources
- **Context**: Sensor networks, gateways, alarms

### Complex Use Cases

| Case | Description | Components Tested |
|------|-------------|-------------------|
| Sensors | Device network | EventManager |
| Alarms | Monitoring system | Monitor, connections |
| Gateway | Resilient communication | trapExit, Connections |

### Tests Created

#### Stress Tests
1. **5000 sensor events** - Throughput
2. **Multiple EventManagers** - Distribution
3. **Unstable connections** - Connect/disconnect cycles

#### Edge Cases
1. **Device disconnects during event** - Resilience
2. **Monitor dies before monitored** - Cleanup
3. **Broken bidirectional connection** - Propagation
4. **Exception in handler** - Isolation
5. **trapExit for cascade** - Firewall

#### Vulnerabilities
1. **Event storm (10000 events)** - Flood
2. **Memory leak in handlers** - Management
3. **Circular connections** - Deadlock
4. **Race in add/delete handlers** - Thread-safety
5. **Handler limit** - Resources

---

## Total Test Coverage

| Category | Mariana | Ricardo | Sofia | Pedro | Ana | Total |
|----------|---------|---------|-------|-------|-----|-------|
| Stress Tests | 3 | 3 | 3 | 3 | 3 | 15 |
| Edge Cases | 4 | 4 | 5 | 4 | 5 | 22 |
| Vulnerabilities | 4 | 4 | 9 | 4 | 5 | 26 |
| Scenarios | 2 | 3 | 3 | 3 | 3 | 14 |
| **Total** | **13** | **14** | **20** | **14** | **16** | **77** |

## Components Tested by Persona

- **Mariana**: Supervisor, Checkpointing, Connections, Registry
- **Ricardo**: StateMachine, PriorityChannel, EventManager
- **Sofia**: All components (security perspective)
- **Pedro**: Checkpointing, Supervisor, Distributed Workers
- **Ana**: EventManager, Monitor, Connections, trapExit

---

## Key Discoveries

### Critical Bug Fix: Race Condition in Communication Layer

**Problem:**
When an actor crashes and is being restarted by its supervisor, there is a window where messages are lost or exceptions are thrown.

**Fix:**
Added automatic retry mechanism in `src/com.jl`:

```julia
function _send_with_retry!(lk::Link, msg; retries::Int=20, delay::Real=0.02)
    for attempt in 1:retries
        try
            return _send!(lk.chn, msg)
        catch e
            if (e isa InvalidStateException && e.state == :closed) || e isa TaskFailedException
                if attempt < retries
                    sleep(delay)
                else
                    rethrow()
                end
            else
                rethrow()
            end
        end
    end
end
```

### Behavior Discovery: `restore()` Returns Tuple

```julia
checkpoint(cp, :value, 42)
restore(cp, :value)  # Returns (42,) not 42

checkpoint(cp, :position, x, y, z)
restore(cp, :position)  # Returns (x, y, z)
```

This is **correct behavior** for multi-value checkpoints, but tests must account for it.

---

*Documentation generated: 2026-02-21*
*Library: Actors.jl v0.3.0*
*Julia: 1.12+*
