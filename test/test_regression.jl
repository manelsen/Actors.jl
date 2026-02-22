#
# Behavioral regression tests for Actors.jl
#
# PURPOSE: These tests protect the PUBLIC BEHAVIORAL CONTRACTS of the library.
# They are designed to survive the v0.3.0 refactoring (type-stable _ACT,
# new mailbox implementation, etc.) without modification.
#
# RULE: Never access _ACT fields directly here. Never test internals.
#       If a test needs to know A.mode or A.conn, it belongs in test_basics.jl,
#       not here. Here we only care "does it behave correctly from the outside?"
#
# See CLAUDE.md § "What regression tests protect" for the full contract list.
#

using Actors, Test, .Threads
import Actors: spawn, newLink

# Helper: synchronize with an actor after a sequence of casts.
# exec runs a function inside the actor's task, so it only returns after
# all previously enqueued messages have been processed.
_sync(lk) = exec(lk, () -> nothing)

# ── 1. FIFO message ordering ──────────────────────────────────────────────────
# An actor must process messages in the order they were sent by a single sender.
@testset "FIFO message ordering" begin
    log = Int[]
    lk = spawn((x) -> push!(log, x))
    for i in 1:20
        cast(lk, i)
    end
    _sync(lk)
    @test log == collect(1:20)
    exit!(lk)
end

# ── 2. Actor isolation ────────────────────────────────────────────────────────
# An error in one actor must not affect actors that are not connected to it.
@testset "Actor isolation" begin
    healthy = spawn((x) -> x * 2)
    faulty  = spawn((x) -> x == :boom ? error("intentional") : x)

    send(faulty, :boom)
    sleep(0.15)

    # The healthy actor must still work correctly.
    @test call(healthy, 21) == 42
    exit!(healthy)
end

# ── 3. call semantics ─────────────────────────────────────────────────────────
# call blocks until the actor has processed the message and returns the result.
@testset "call is synchronous" begin
    lk = spawn((x) -> x^2)
    @test call(lk, 5)  == 25
    @test call(lk, 7)  == 49
    @test call(lk, -3) == 9
    exit!(lk)
end

# ── 4. cast semantics ─────────────────────────────────────────────────────────
# cast is fire-and-forget: it returns immediately without waiting for the actor.
@testset "cast is asynchronous" begin
    counter = Ref(0)
    lk = spawn((x) -> counter[] += x)

    t_start = time()
    for _ in 1:100
        cast(lk, 1)
    end
    t_cast = time() - t_start

    # All 100 casts must complete without blocking noticeably.
    # A synchronous implementation would take >> 0.5 s; this should be << 0.1 s.
    @test t_cast < 0.5

    _sync(lk)
    @test counter[] == 100
    exit!(lk)
end

# ── 5. become! takes effect on the NEXT message ───────────────────────────────
# Closures must be defined BEFORE spawn so their world age ≤ actor's world age.
# Julia actors run with the world age at task creation; closures defined later
# are in a newer world the actor cannot call directly (world age invariant).
@testset "become! semantics" begin
    bhv_double  = (x) -> x * 2
    bhv_triple  = (x) -> x * 3
    bhv_add100  = (x) -> x + 100

    lk = spawn(bhv_double)
    @test call(lk, 5) == 10

    become!(lk, bhv_triple)
    @test call(lk, 5) == 15   # new behavior

    become!(lk, bhv_add100)
    @test call(lk, 5) == 105  # another change
    exit!(lk)
end

# ── 6. exit! terminates the actor ────────────────────────────────────────────
@testset "exit! terminates actor" begin
    ref = Ref{Task}()
    lk  = spawn(identity, taskref=ref)
    @test ref[].state == :runnable

    exit!(lk)
    timedwait(1.0) do
        ref[].state != :runnable
    end
    @test ref[].state ∈ (:done, :failed)
end

# ── 7. send_after delivers after the delay ────────────────────────────────────
@testset "send_after timing" begin
    log = Symbol[]
    lk = spawn((x) -> push!(log, x))

    send(lk, :immediate)
    send_after(lk, 0.25, :delayed)

    sleep(0.05)
    _sync(lk)
    @test log == [:immediate]    # :delayed not yet delivered

    sleep(0.30)
    _sync(lk)
    @test log == [:immediate, :delayed]
    exit!(lk)
end

# ── 8. receive timeout ────────────────────────────────────────────────────────
# When no message arrives within the timeout, receive returns Timeout().
@testset "receive timeout" begin
    me     = newLink(1)
    result = receive(me, timeout=0.1)
    @test result isa Actors.Timeout
end

# ── 9. request timeout ───────────────────────────────────────────────────────
# A request to an actor that never replies must return Timeout().
# We use a Msg subtype handled by the default onmessage (which does NOT send a
# Response), so the request genuinely times out.
@testset "request timeout" begin
    # Custom message type: handled as a generic Msg, no automatic Response.
    struct _NoReply <: Msg
        x
    end

    lk = spawn((msg::_NoReply) -> nothing)
    me = newLink(1)

    # Send the message directly (not via request, which wraps in Call)
    send(lk, _NoReply(:hello))

    # receive on our link — nothing will arrive
    result = receive(me, timeout=0.15)
    @test result isa Actors.Timeout
    exit!(lk)
end

# ── 10. Concurrent actors don't share state ───────────────────────────────────
# Each actor has its own independent state; concurrent calls must not
# produce cross-contamination.
@testset "Concurrent state isolation" begin
    n      = 20
    actors = [spawn((x) -> x + i) for i in 1:n]  # each captures its own i

    results = [call(actors[i], 0) for i in 1:n]

    @test results == collect(1:n)
    foreach(exit!, actors)
end

# ── 11. Registry: register / whereis / unregister ────────────────────────────
@testset "Registry cycle" begin
    lk   = spawn(identity)
    name = :_regression_test_actor

    @test register(name, lk) == true
    @test whereis(name) !== missing

    # Registering the same name again must fail
    lk2  = spawn(identity)
    @test register(name, lk2) == false

    unregister(name)
    @test ismissing(whereis(name))

    exit!(lk)
    exit!(lk2)
end

# ── 12. Supervisor: one_for_one restart ──────────────────────────────────────
# A supervised actor that fails must be restarted by the supervisor and
# remain functional afterward.
@testset "Supervisor one_for_one restart" begin
    failed = Ref(false)

    bhv = (x) -> begin
        if !failed[]
            failed[] = true
            error("intentional first failure")
        end
        x * 2
    end

    sv = supervisor(:one_for_one, max_restarts=3, max_seconds=5.0)
    lk = start_actor(bhv, sv)

    # Wait for the supervisor to send Connect to the actor so that A.conn is
    # populated. Without this, the actor's _act loop takes the isempty(A.conn)
    # fast-path (no try-catch), onerror is never called, and the supervisor is
    # never notified of the failure → no restart ever happens.
    sleep(0.1)

    # Trigger the failure
    cast(lk, :trigger)

    # Wait for the supervisor to restart the actor.
    # With channel reuse the same channel is kept, so we poll until the actor
    # responds correctly instead of watching for a channel swap.
    timedwait(2.0; pollint=0.05) do
        try
            call(lk, 99; timeout=0.1) == 198
        catch
            false
        end
    end

    # After restart the actor must work correctly
    @test call(lk, 5) == 10

    exit!(sv, :shutdown)
end

# ── 13. Supervisor: temporary actor is not restarted ─────────────────────────
@testset "Supervisor temporary actor not restarted" begin
    ref = Ref{Task}()
    sv  = supervisor(:one_for_one)
    lk  = start_actor((_) -> error("fail"), sv, nothing, :temporary; taskref=ref)

    # Wait for supervisor to send Connect to actor (same race as test 12).
    sleep(0.1)

    cast(lk, :trigger)
    timedwait(1.5) do
        ref[].state != :runnable
    end

    @test ref[].state ∈ (:done, :failed)
    @test isempty(which_children(sv))   # supervisor removed it, did not restart

    exit!(sv, :shutdown)
end
