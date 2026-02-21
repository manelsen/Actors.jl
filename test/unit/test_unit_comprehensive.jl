#
# Unit Tests - Comprehensive Coverage for Actors.jl
# Tests each function and type in isolation
#

using Test
using Actors
import Actors: spawn, newLink, diag, _ACT

println("=" ^ 60)
println("UNIT TESTS - Comprehensive Coverage")
println("=" ^ 60)

# ============================================================================
# TYPE TESTS
# ============================================================================

@testset "Type Tests" begin
    
    @testset "Link Type" begin
        ch = Channel{Any}(32)
        lk = Link(ch, 1, :default)
        
        @test lk.chn === ch
        @test lk.pid == 1
        @test lk.mode == :default
        
        @test lk isa Actors.Link
    end
    
    @testset "Bhv Type" begin
        f(x, y) = x + y
        bhv = Actors.Bhv(f, 10)
        
        @test bhv.f === f
        @test bhv.a == (10,)
        @test bhv(5) == 15
    end
    
    @testset "Args Type" begin
        args = Actors.Args(1, 2, 3; a=4, b=5)
        
        @test args.args == (1, 2, 3)
        @test args.kwargs[:a] == 4
        @test args.kwargs[:b] == 5
    end
    
    @testset "Message Types" begin
        lk = newLink()
        
        req = Actors.Request(:data, lk)
        @test req.x == :data
        @test req.from === lk
        
        resp = Actors.Response(:result, lk)
        @test resp.y == :result
        @test resp.from === lk
        
        exit_msg = Actors.Exit(:reason, nothing, nothing, nothing)
        @test exit_msg.reason == :reason
    end
    
    @testset "_ACT Type" begin
        act = _ACT(:default)
        
        @test act.mode == :default
        @test act.bhv isa Actors.Bhv
        @test act.init === nothing
        @test act.term === nothing
        @test act.self === nothing
        @test act.name === nothing
        @test act.res === nothing
        @test act.sta === nothing
        @test act.usr === nothing
        @test isempty(act.conn)
    end
end

# ============================================================================
# PRIMITIVE TESTS
# ============================================================================

@testset "Primitive Tests" begin
    
    @testset "spawn" begin
        t = Ref{Task}()
        actor = spawn((msg) -> msg, taskref=t)
        
        @test actor isa Actors.Link
        @test t[].state == :runnable
        
        exit!(actor)
    end
    
    @testset "send" begin
        me = newLink()
        actor = spawn((msg) -> send(me, msg))
        
        send(actor, :hello)
        result = receive(me)
        
        @test result == :hello
        
        exit!(actor)
    end
    
    @testset "become" begin
        actor = spawn((msg) -> begin
            if msg == :switch
                Actors.become((m) -> m * 2)
                return :switched
            end
            return msg
        end)
        
        result = call(actor, 5)
        @test result == 5
        
        result = call(actor, :switch)
        @test result == :switched
        
        result = call(actor, 5)
        @test result == 10
        
        exit!(actor)
    end
    
    @testset "self" begin
        actor = spawn(() -> Actors.self())
        
        result = call(actor)
        @test result === actor
        
        exit!(actor)
    end
    
    @testset "stop" begin
        t = Ref{Task}()
        actor = spawn(() -> Actors.stop(), taskref=t)
        
        call(actor)
        sleep(0.2)
        
        @test t[].state == :done
    end
end

# ============================================================================
# API TESTS
# ============================================================================

@testset "API Tests" begin
    
    @testset "call" begin
        actor = spawn((msg) -> msg * 2)
        
        result = call(actor, 5)
        @test result == 10
        
        exit!(actor)
    end
    
    @testset "cast" begin
        state = Ref(0)
        actor = spawn((msg) -> state[] = msg)
        
        cast(actor, 42)
        sleep(0.2)
        
        @test state[] == 42
        
        exit!(actor)
    end
    
    @testset "exec" begin
        triple(x) = x * 3
        actor = spawn((msg) -> msg)
        
        result = exec(actor, triple, 7)
        @test result == 21
        
        exit!(actor)
    end
    
    @testset "query" begin
        actor = spawn((msg) -> msg)
        
        mode = query(actor, :mode)
        @test mode == :default
        
        exit!(actor)
    end
    
    @testset "update!" begin
        state = Ref(0)
        actor = spawn((msg) -> begin
            state[] += msg
            return state[]
        end)
        
        call(actor, 1)
        call(actor, 1)
        
        result = call(actor, 1)
        @test result == 3
        
        exit!(actor)
    end
    
    @testset "become!" begin
        actor = spawn((msg) -> msg)
        
        result = call(actor, 5)
        @test result == 5
        
        become!(actor, (m) -> m * 3)
        
        result = call(actor, 5)
        @test result == 15
        
        exit!(actor)
    end
    
    @testset "init!" begin
        init_called = Ref(false)
        
        actor = spawn((msg) -> msg)
        init!(actor, () -> init_called[] = true)
        
        sleep(0.2)
        
        exit!(actor)
    end
    
    @testset "term!" begin
        term_called = Ref(false)
        
        actor = spawn((msg) -> msg)
        term!(actor, (reason) -> term_called[] = true)
        
        exit!(actor)
        sleep(0.2)
    end
    
    @testset "exit!" begin
        t = Ref{Task}()
        actor = spawn((msg) -> msg, taskref=t)
        
        @test t[].state == :runnable
        
        exit!(actor, :shutdown)
        sleep(0.2)
        
        @test t[].state == :done
    end
    
    @testset "info" begin
        actor = spawn((msg) -> msg, thrd=1)
        
        i = Actors.info(actor)
        
        @test i.mode == :default
        @test i.pid == 1
        @test i.thrd >= 1
        @test i.task isa UInt
        @test i.name === nothing
        
        exit!(actor)
    end
end

# ============================================================================
# RECEIVE/REQUEST TESTS
# ============================================================================

@testset "Receive/Request Tests" begin
    
    @testset "receive basic" begin
        me = newLink()
        
        send(me, :test_message)
        result = receive(me)
        
        @test result == :test_message
    end
    
    @testset "receive with timeout" begin
        me = newLink()
        
        result = receive(me; timeout=0.1)
        @test result isa Actors.Timeout
        
        send(me, :delayed)
        result = receive(me; timeout=1.0)
        @test result == :delayed
    end
    
    @testset "request basic" begin
        actor = spawn((msg) -> msg * 2)
        
        result = Actors.request(actor, 21)
        @test result == 42
        
        exit!(actor)
    end
end

# ============================================================================
# CONNECTION TESTS
# ============================================================================

@testset "Connection Tests" begin
    
    @testset "connect/disconnect" begin
        t1 = Ref{Task}()
        t2 = Ref{Task}()
        
        a = spawn(Actors.connect, taskref=t1)
        b = spawn(Actors.connect, taskref=t2)
        
        send(a, b)
        sleep(0.2)
        
        a_diag = diag(a, :act)
        b_diag = diag(b, :act)
        
        @test !isempty(a_diag.conn)
        @test !isempty(b_diag.conn)
        
        disconnect(a)
        disconnect(b)
        sleep(0.2)
        
        exit!(a)
        exit!(b)
    end
    
    @testset "trapExit" begin
        t = Ref{Task}()
        
        actor = spawn((msg) -> msg, taskref=t)
        trapExit(actor)
        
        sleep(0.1)
        
        act = diag(actor, :act)
        @test act.mode == :sticky
        
        exit!(actor)
    end
end

# ============================================================================
# MONITOR TESTS
# ============================================================================

@testset "Monitor Tests" begin
    
    @testset "monitor basic" begin
        t1 = Ref{Task}()
        t2 = Ref{Task}()
        
        monitored = spawn((msg) -> msg, taskref=t1)
        me = newLink()
        
        monitor(monitored, send, me)
        sleep(0.2)
        
        m_diag = diag(monitored, :act)
        @test !isempty(m_diag.conn)
        
        send(monitored, "boom")
        sleep(0.2)
        
        exit!(monitored)
    end
    
    @testset "demonitor" begin
        t1 = Ref{Task}()
        
        monitored = spawn((msg) -> msg, taskref=t1)
        me = newLink()
        
        monitor(monitored, send, me)
        sleep(0.2)
        
        demonitor(monitored)
        sleep(0.2)
        
        m_diag = diag(monitored, :act)
        @test isempty(m_diag.conn)
        
        exit!(monitored)
    end
end

# ============================================================================
# SUPERVISOR TESTS
# ============================================================================

@testset "Supervisor Tests" begin
    
    @testset "supervisor creation" begin
        t = Ref{Task}()
        
        sv = supervisor(:one_for_one, taskref=t)
        
        @test t[].state == :runnable
        
        sv_diag = diag(sv, :act)
        @test sv_diag.mode == :supervisor
        @test sv_diag.bhv isa Actors.Supervisor
        
        exit!(sv)
    end
    
    @testset "supervise" begin
        t_sv = Ref{Task}()
        t_act = Ref{Task}()
        
        sv = supervisor(taskref=t_sv)
        actor = spawn((msg) -> msg, taskref=t_act)
        
        supervise(sv, actor)
        sleep(0.2)
        
        children = which_children(sv)
        @test length(children) == 1
        
        exit!(sv)
    end
    
    @testset "unsupervise" begin
        t_sv = Ref{Task}()
        
        sv = supervisor(taskref=t_sv)
        actor = spawn((msg) -> msg)
        
        supervise(sv, actor)
        sleep(0.2)
        
        unsupervise(sv, actor)
        sleep(0.2)
        
        children = which_children(sv)
        @test isempty(children)
        
        exit!(sv)
    end
    
    @testset "count_children" begin
        t_sv = Ref{Task}()
        
        sv = supervisor(taskref=t_sv)
        
        for _ in 1:5
            actor = spawn((msg) -> msg)
            supervise(sv, actor)
        end
        
        sleep(0.3)
        
        counts = count_children(sv)
        @test counts.all == 5
        
        exit!(sv)
    end
    
    @testset "terminate_child" begin
        t_sv = Ref{Task}()
        t_act = Ref{Task}()
        
        sv = supervisor(taskref=t_sv)
        actor = spawn((msg) -> msg, taskref=t_act)
        
        supervise(sv, actor)
        sleep(0.2)
        
        terminate_child(sv, actor)
        sleep(0.2)
        
        @test t_act[].state == :done
        
        children = which_children(sv)
        @test isempty(children)
        
        exit!(sv)
    end
end

# ============================================================================
# REGISTRY TESTS
# ============================================================================

@testset "Registry Tests" begin
    
    @testset "register/unregister" begin
        actor = spawn((msg) -> msg)
        
        register(:test_actor, actor)
        sleep(0.1)
        
        found = whereis(:test_actor)
        @test found === actor
        
        unregister(:test_actor)
        sleep(0.1)
        
        found = whereis(:test_actor)
        @test found === missing
        
        exit!(actor)
    end
    
    @testset "registered" begin
        actors = Link[]
        
        for i in 1:5
            a = spawn((msg) -> msg)
            register(Symbol("reg_test_$i"), a)
            push!(actors, a)
        end
        
        sleep(0.2)
        
        names = registered()
        @test length(names) >= 5
        
        for i in 1:5
            unregister(Symbol("reg_test_$i"))
        end
        
        for a in actors
            exit!(a)
        end
    end
end

# ============================================================================
# CHECKPOINT TESTS
# ============================================================================

@testset "Checkpoint Tests" begin
    
    @testset "checkpoint/restore" begin
        cp = checkpointing(1)
        
        checkpoint(cp, :test_key, 42)
        sleep(0.1)
        
        result = restore(cp, :test_key)
        @test result == (42,)
        
        exit!(cp)
    end
    
    @testset "get_checkpoints" begin
        cp = checkpointing(1)
        
        checkpoint(cp, :a, 1)
        checkpoint(cp, :b, 2)
        checkpoint(cp, :c, 3)
        
        sleep(0.2)
        
        data = get_checkpoints(cp)
        
        @test haskey(data, :a)
        @test haskey(data, :b)
        @test haskey(data, :c)
        
        exit!(cp)
    end
    
    @testset "save/load checkpoints" begin
        filename = "unit_test_checkpoint.dat"
        
        cp = checkpointing(1, filename)
        
        checkpoint(cp, :saved, :value)
        sleep(0.2)
        
        data = get_checkpoints(cp)
        @test haskey(data, :saved)
        
        save_checkpoints(cp)
        sleep(0.3)
        
        @test isfile(filename)
        
        exit!(cp)
        rm(filename, force=true)
    end
end

# ============================================================================
# STATE MACHINE TESTS
# ============================================================================

@testset "StateMachine Tests" begin
    
    @testset "basic state machine" begin
        function init()
            return (:initial, 0)
        end
        
        function handle_event(state, event, data)
            if state == :initial && event == :start
                return (:running, data + 1, [])
            elseif state == :running && event == :stop
                return (:stopped, data, [])
            end
            return (state, data, [])
        end
        
        sm = Actors.StateMachine(init, handle_event)
        lk = spawn(sm, mode=:statem)
        
        current = call(lk, :ping)
        @test current == :initial
        
        cast(lk, :start)
        sleep(0.1)
        
        current = call(lk, :ping)
        @test current == :running
        
        cast(lk, :stop)
        sleep(0.1)
        
        current = call(lk, :ping)
        @test current == :stopped
        
        exit!(lk)
    end
end

# ============================================================================
# EVENT MANAGER TESTS
# ============================================================================

@testset "EventManager Tests" begin
    
    @testset "basic event manager" begin
        em = Actors.event_manager()
        
        counter = Ref(0)
        
        Actors.add_handler(em, :counter,
            () -> counter,
            (event, state) -> begin
                state[] += 1
                (state, [])
            end
        )
        
        sleep(0.1)
        
        send_event(em, :tick)
        send_event(em, :tick)
        send_event(em, :tick)
        
        sleep(0.3)
        
        @test counter[] == 3
        
        exit!(em)
    end
    
    @testset "multiple handlers" begin
        em = Actors.event_manager()
        
        counter_a = Ref(0)
        counter_b = Ref(0)
        
        Actors.add_handler(em, :handler_a,
            () -> counter_a,
            (event, state) -> begin
                state[] += 1
                (state, [])
            end
        )
        
        Actors.add_handler(em, :handler_b,
            () -> counter_b,
            (event, state) -> begin
                state[] += 10
                (state, [])
            end
        )
        
        sleep(0.1)
        
        send_event(em, :event)
        
        sleep(0.3)
        
        @test counter_a[] == 1
        @test counter_b[] == 10
        
        handlers = which_handlers(em)
        @test :handler_a in handlers
        @test :handler_b in handlers
        
        exit!(em)
    end
    
    @testset "delete_handler" begin
        em = Actors.event_manager()
        
        counter = Ref(0)
        
        Actors.add_handler(em, :to_delete,
            () -> counter,
            (event, state) -> begin
                state[] += 1
                (state, [])
            end
        )
        
        sleep(0.1)
        
        delete_handler(em, :to_delete)
        sleep(0.1)
        
        handlers = which_handlers(em)
        @test !(:to_delete in handlers)
        
        exit!(em)
    end
end

# ============================================================================
# PRIORITY TESTS
# ============================================================================

@testset "Priority Tests" begin
    
    @testset "PriorityChannel" begin
        ch = Actors.PriorityChannel(10)
        
        put!(ch, :normal)
        put!(ch, Actors.PriorityMsg(:high, 5))
        put!(ch, Actors.PriorityMsg(:urgent, 10))
        
        @test take!(ch) == :urgent
        @test take!(ch) == :high
        @test take!(ch) == :normal
        
        close(ch)
    end
    
    @testset "send_priority" begin
        lk = Actors.newPriorityLink(10)
        
        send_low(lk, :low)
        send_high(lk, :high)
        send_priority(lk, :urgent, 100)
        
        @test take!(lk.chn) == :urgent
        @test take!(lk.chn) == :high
        @test take!(lk.chn) == :low
        
        close(lk.chn)
    end
end

println("=" ^ 60)
println("UNIT TESTS Completed")
println("=" ^ 60)
