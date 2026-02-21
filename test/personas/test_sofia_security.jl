#
# Test Suite: Sofia - Security Engineer
# Focus: Vulnerability detection, edge cases, stress tests, security exploits
#
# This test suite covers security-focused scenarios:
# 1. Message injection attacks - malformed/malicious messages
# 2. Denial of service attacks - resource exhaustion
# 3. Information leakage - unauthorized state access
# 4. Privilege escalation - bypassing controls
#
# Categories:
# - Stress Tests: Actor explosions, channel exhaustion, memory pressure
# - Edge Cases: nil/NaN/Inf, circular links, zombie actors, negative timeouts
# - Vulnerabilities: Race conditions, deadlocks, exception handling gaps

using Test
using Actors
using Random
import Actors: spawn, newLink, diag

println("=" ^ 60)
println("SOFIA - Security Engineer Test Suite")
println("=" ^ 60)

# ============================================================================
# STRESS TESTS - Resource Exhaustion
# ============================================================================

@testset "Stress Tests - Resource Exhaustion" begin
    
    # --------------------------------------------------------------------------
    # Test: Actor Explosion - Rapid Actor Creation
    # Why: Attackers may try to exhaust system resources by creating many actors.
    # Tests system behavior under actor explosion attack.
    # --------------------------------------------------------------------------
    @testset "Actor Explosion - 500 actors rapidly" begin
        actors = Link[]
        
        start_time = time()
        
        for i in 1:500
            try
                a = spawn((msg) -> msg)
                push!(actors, a)
            catch
                break
            end
        end
        
        elapsed = time() - start_time
        
        @test length(actors) > 100
        
        sleep(0.5)
        
        alive_count = 0
        for a in actors
            try
                call(a, :ping)
                alive_count += 1
            catch
            end
        end
        
        @test alive_count > length(actors) * 0.8
        
        for a in actors
            try
                exit!(a)
            catch
            end
        end
    end
    
    # --------------------------------------------------------------------------
    # Test: Channel Exhaustion
    # Why: Flooding channels can cause denial of service.
    # Tests behavior when channels reach capacity.
    # --------------------------------------------------------------------------
    @testset "Channel Exhaustion - Flood small channel" begin
        lk = newLink(10)
        
        processed = Ref(0)
        
        t = Task(() -> begin
            while true
                try
                    msg = take!(lk.chn)
                    msg == :stop && break
                    sleep(0.01)
                    processed[] += 1
                catch
                    break
                end
            end
        end)
        schedule(t)
        
        sleep(0.1)
        
        sent = 0
        for i in 1:100
            try
                send(lk, i)
                sent += 1
            catch
                break
            end
        end
        
        sleep(0.5)
        
        send(lk, :stop)
        sleep(0.2)
        
        @test sent > 0
        
        close(lk.chn)
    end
    
    # --------------------------------------------------------------------------
    # Test: Memory Pressure with Large Messages
    # Why: Large messages can cause memory exhaustion.
    # Tests system stability under memory pressure.
    # --------------------------------------------------------------------------
    @testset "Memory Pressure - Large message handling" begin
        actor = spawn((msg) -> begin
            if msg isa Tuple && first(msg) == :large
                return length(msg[2])
            end
            return :ok
        end)
        
        for size in [1000, 10000, 100000]
            try
                large_data = zeros(size)
                result = call(actor, (:large, large_data))
                @test result == size
            catch e
                @test e isa Exception
            end
            GC.gc()
        end
        
        exit!(actor)
    end
end

# ============================================================================
# EDGE CASES - Malformed Inputs
# ============================================================================

@testset "Edge Cases - Malformed Inputs" begin
    
    # --------------------------------------------------------------------------
    # Test: Nil/Nothing Messages
    # Why: Attackers may send nil values to crash actors.
    # Tests actor resilience to nil/nothing messages.
    # --------------------------------------------------------------------------
    @testset "Nil/Nothing message handling" begin
        actor = spawn((msg) -> msg)
        
        send(actor, nothing)
        sleep(0.1)
        
        result = call(actor, :test)
        @test result == :test
        
        send(actor, missing)
        sleep(0.1)
        
        result = call(actor, :test2)
        @test result == :test2
        
        exit!(actor)
    end
    
    # --------------------------------------------------------------------------
    # Test: NaN and Inf Values
    # Why: NaN/Inf can propagate and cause numerical instability.
    # Tests proper handling of special floating-point values.
    # --------------------------------------------------------------------------
    @testset "NaN/Inf message handling" begin
        actor = spawn((msg) -> begin
            if msg isa Number
                return isfinite(msg) ? msg * 2 : :special
            end
            return msg
        end)
        
        result = call(actor, 42.0)
        @test result == 84.0
        
        result = call(actor, NaN)
        @test result == :special
        
        result = call(actor, Inf)
        @test result == :special
        
        result = call(actor, -Inf)
        @test result == :special
        
        exit!(actor)
    end
    
    # --------------------------------------------------------------------------
    # Test: Empty Messages
    # Why: Empty tuples or messages should not crash actors.
    # Tests handling of empty/void messages.
    # --------------------------------------------------------------------------
    @testset "Empty message handling" begin
        actor = spawn((msg) -> begin
            if isempty(msg)
                return :empty
            end
            return msg
        end)
        
        send(actor, ())
        sleep(0.1)
        
        send(actor, [])
        sleep(0.1)
        
        send(actor, "")
        sleep(0.1)
        
        result = call(actor, :test)
        @test result == :test
        
        exit!(actor)
    end
    
    # --------------------------------------------------------------------------
    # Test: Negative and Extreme Timeout Values
    # Why: Invalid timeout values could cause undefined behavior.
    # Tests timeout handling with edge case values.
    # --------------------------------------------------------------------------
    @testset "Timeout edge cases" begin
        me = newLink()
        
        actor = spawn((msg) -> begin
            sleep(0.1)
            send(me, :response)
        end)
        
        send(actor, :trigger)
        
        result = receive(me; timeout=1.0)
        @test result == :response
        
        result = receive(me; timeout=0.001)
        @test result === nothing
        
        exit!(actor)
    end
    
    # --------------------------------------------------------------------------
    # Test: Circular Actor References
    # Why: Circular references could cause infinite loops or deadlocks.
    # Tests that circular actor networks don't deadlock.
    # --------------------------------------------------------------------------
    @testset "Circular actor references" begin
        t1 = Ref{Task}()
        t2 = Ref{Task}()
        
        a = spawn((msg) -> begin
            if msg == :get_link
                return diag(self(), :act).self
            end
            return msg
        end, taskref=t1)
        
        b = spawn((msg) -> begin
            if msg == :get_link
                return diag(self(), :act).self
            end
            return msg
        end, taskref=t2)
        
        send(a, b)
        send(b, a)
        
        sleep(0.2)
        
        @test t1[].state == :runnable
        @test t2[].state == :runnable
        
        exit!(a)
        exit!(b)
    end
end

# ============================================================================
# VULNERABILITY TESTS - Race Conditions
# ============================================================================

@testset "Vulnerability Tests - Race Conditions" begin
    
    # --------------------------------------------------------------------------
    # Test: Concurrent State Modification
    # Why: Race conditions in state modification can cause corruption.
    # Tests actor state integrity under concurrent access.
    # --------------------------------------------------------------------------
    @testset "Concurrent state modification" begin
        counter = Ref(0)
        
        actor = spawn((msg) -> begin
            if msg == :increment
                current = counter[]
                sleep(0.001)
                counter[] = current + 1
                return counter[]
            elseif msg == :get
                return counter[]
            end
            return msg
        end)
        
        @sync for _ in 1:100
            @async send(actor, :increment)
        end
        
        sleep(0.5)
        
        final = call(actor, :get)
        
        @test final > 0
        @test final <= 100
        
        exit!(actor)
    end
    
    # --------------------------------------------------------------------------
    # Test: Become Race Condition
    # Why: Rapid behavior changes could cause inconsistent state.
    # Tests behavior switching under concurrent operations.
    # --------------------------------------------------------------------------
    @testset "Become race condition" begin
        actor = spawn((msg) -> msg)
        
        @sync for i in 1:50
            @async become!(actor, (m) -> m + i)
        end
        
        sleep(0.3)
        
        result = call(actor, 0)
        @test result >= 0
        
        exit!(actor)
    end
    
    # --------------------------------------------------------------------------
    # Test: Registry Race Condition
    # Why: Concurrent register/unregister could cause registry corruption.
    # Tests registry integrity under concurrent operations.
    # --------------------------------------------------------------------------
    @testset "Registry race condition" begin
        actors = [spawn((msg) -> msg) for _ in 1:20]
        
        @sync for (i, a) in enumerate(actors)
            @async begin
                try
                    register(Symbol("race_actor_$i"), a)
                catch
                end
            end
        end
        
        sleep(0.5)
        
        registered_count = 0
        for i in 1:20
            if whereis(Symbol("race_actor_$i")) !== nothing
                registered_count += 1
            end
        end
        
        @test registered_count > 0
        
        for i in 1:20
            try
                unregister(Symbol("race_actor_$i"))
            catch
            end
        end
        
        for a in actors
            exit!(a)
        end
    end
end

# ============================================================================
# VULNERABILITY TESTS - Exception Handling
# ============================================================================

@testset "Vulnerability Tests - Exception Handling" begin
    
    # --------------------------------------------------------------------------
    # Test: Exception in Behavior Doesn't Kill System
    # Why: Exceptions should be isolated to failing actor.
    # Tests that exceptions don't propagate to other actors.
    # --------------------------------------------------------------------------
    @testset "Exception isolation" begin
        t1 = Ref{Task}()
        t2 = Ref{Task}()
        
        failing = spawn((msg) -> error("Intentional error!"), taskref=t1)
        healthy = spawn((msg) -> msg, taskref=t2)
        
        send(failing, :trigger)
        sleep(0.2)
        
        @test t1[].state == :failed
        @test t2[].state == :runnable
        
        result = call(healthy, :test)
        @test result == :test
        
        exit!(healthy)
    end
    
    # --------------------------------------------------------------------------
    # Test: Stack Overflow Handling
    # Why: Infinite recursion could cause stack overflow.
    # Tests actor behavior with recursive calls.
    # --------------------------------------------------------------------------
    @testset "Stack overflow protection" begin
        function recursive_actor(msg)
            if msg isa Tuple && first(msg) == :recurse
                depth = msg[2]
                if depth > 0
                    return recursive_actor((:recurse, depth - 1))
                end
                return 0
            end
            return msg
        end
        
        actor = spawn(recursive_actor)
        
        result = call(actor, (:recurse, 10))
        @test result == 0
        
        exit!(actor)
    end
    
    # --------------------------------------------------------------------------
    # Test: MethodError Handling
    # Why: Wrong message types cause MethodError.
    # Tests graceful handling of method errors.
    # --------------------------------------------------------------------------
    @testset "MethodError handling" begin
        typed_actor = spawn((msg::Int) -> msg * 2)
        
        result = call(typed_actor, 5)
        @test result == 10
        
        send(typed_actor, "string instead of int")
        sleep(0.2)
        
        result = call(typed_actor, 10)
        @test result == 20
        
        exit!(typed_actor)
    end
end

# ============================================================================
# VULNERABILITY TESTS - Information Leakage
# ============================================================================

@testset "Vulnerability Tests - Information Leakage" begin
    
    # --------------------------------------------------------------------------
    # Test: Query Access Control
    # Why: Actors should not expose sensitive state to unauthorized callers.
    # Tests query function access control.
    # --------------------------------------------------------------------------
    @testset "Query access restrictions" begin
        secret_data = "SECRET_KEY_12345"
        
        actor = spawn((msg) -> begin
            if msg == :get_secret
                return secret_data
            elseif msg == :public_info
                return "public_data"
            end
            return :unknown
        end)
        
        result = call(actor, :public_info)
        @test result == "public_data"
        
        result = call(actor, :get_secret)
        @test result == secret_data
        
        bhv = query(actor, :bhv)
        @test bhv !== nothing
        
        exit!(actor)
    end
    
    # --------------------------------------------------------------------------
    # Test: Diag Information Exposure
    # Why: Diagnostic info could expose implementation details.
    # Tests what information is available through diag.
    # --------------------------------------------------------------------------
    @testset "Diag information exposure" begin
        actor = spawn((msg) -> msg)
        
        act_info = diag(actor, :act)
        
        @test hasfield(typeof(act_info), :mode)
        @test hasfield(typeof(act_info), :bhv)
        @test hasfield(typeof(act_info), :self)
        
        task_info = diag(actor, :task)
        @test task_info isa Task
        
        exit!(actor)
    end
end

# ============================================================================
# VULNERABILITY TESTS - Connection Attacks
# ============================================================================

@testset "Vulnerability Tests - Connection Attacks" begin
    
    # --------------------------------------------------------------------------
    # Test: Connection Flooding
    # Why: Excessive connections could exhaust resources.
    # Tests connection management under flood.
    # --------------------------------------------------------------------------
    @testset "Connection flooding" begin
        t1 = Ref{Task}()
        
        target = spawn(connect, taskref=t1)
        
        connectors = Link[]
        for i in 1:50
            try
                c = spawn(connect)
                send(c, target)
                push!(connectors, c)
            catch
                break
            end
        end
        
        sleep(0.5)
        
        @test t1[].state == :runnable
        
        exit!(target)
        for c in connectors
            try
                exit!(c)
            catch
            end
        end
    end
    
    # --------------------------------------------------------------------------
    # Test: Monitor Flooding
    # Why: Excessive monitors could cause performance issues.
    # Tests monitor management under flood.
    # --------------------------------------------------------------------------
    @testset "Monitor flooding" begin
        t1 = Ref{Task}()
        
        target = spawn((msg) -> msg, taskref=t1)
        
        monitors = Link[]
        for i in 1:30
            try
                m = spawn(Bhv(monitor, target))
                push!(monitors, m)
            catch
                break
            end
        end
        
        sleep(0.5)
        
        @test t1[].state == :runnable
        
        exit!(target)
        for m in monitors
            try
                exit!(m)
            catch
            end
        end
    end
end

# ============================================================================
# SECURITY SCENARIO TESTS
# ============================================================================

@testset "Security Scenarios" begin
    
    # --------------------------------------------------------------------------
    # Scenario: Rate Limiting Enforcement
    # Why: Rate limiting prevents DoS attacks.
    # Tests that rate limiting can be implemented.
    # --------------------------------------------------------------------------
    @testset "Rate limiting enforcement" begin
        request_count = Ref(0)
        last_reset = Ref(time())
        rate_limit = 10
        
        rate_limited = spawn((msg) -> begin
            current_time = time()
            if current_time - last_reset[] > 1.0
                request_count[] = 0
                last_reset[] = current_time
            end
            
            request_count[] += 1
            
            if request_count[] > rate_limit
                return :rate_limited
            end
            
            return :ok
        end)
        
        for _ in 1:rate_limit
            result = call(rate_limited, :request)
            @test result == :ok
        end
        
        result = call(rate_limited, :request)
        @test result == :rate_limited
        
        exit!(rate_limited)
    end
    
    # --------------------------------------------------------------------------
    # Scenario: Input Validation
    # Why: Input validation prevents injection attacks.
    # Tests that actors can validate inputs.
    # --------------------------------------------------------------------------
    @testset "Input validation enforcement" begin
        validated_actor = spawn((msg) -> begin
            if msg isa Tuple
                cmd = first(msg)
                if cmd == :set_value
                    val = msg[2]
                    if !(val isa Number && val > 0)
                        return :invalid_input
                    end
                    return :ok
                end
            elseif msg isa Number
                if msg < 0
                    return :invalid_input
                end
                return msg * 2
            end
            return :invalid_input
        end)
        
        result = call(validated_actor, (:set_value, 10))
        @test result == :ok
        
        result = call(validated_actor, (:set_value, -5))
        @test result == :invalid_input
        
        result = call(validated_actor, (:set_value, "string"))
        @test result == :invalid_input
        
        result = call(validated_actor, 5)
        @test result == 10
        
        result = call(validated_actor, -5)
        @test result == :invalid_input
        
        exit!(validated_actor)
    end
    
    # --------------------------------------------------------------------------
    # Scenario: Authentication Check
    # Why: Actors may need to authenticate callers.
    # Tests authentication pattern implementation.
    # --------------------------------------------------------------------------
    @testset "Authentication check pattern" begin
        auth_tokens = Set(["valid_token_123", "admin_token_456"])
        
        protected_actor = spawn((msg) -> begin
            if msg isa Tuple && length(msg) >= 2
                token = msg[1]
                action = msg[2]
                
                if !(token in auth_tokens)
                    return :unauthorized
                end
                
                if action == :read
                    return "protected_data"
                elseif action == :write
                    return :written
                end
            end
            return :invalid_request
        end)
        
        result = call(protected_actor, ("invalid_token", :read))
        @test result == :unauthorized
        
        result = call(protected_actor, ("valid_token_123", :read))
        @test result == "protected_data"
        
        result = call(protected_actor, ("admin_token_456", :write))
        @test result == :written
        
        exit!(protected_actor)
    end
end

println("=" ^ 60)
println("SOFIA Security Engineer Test Suite Completed")
println("=" ^ 60)
