include("delays.jl")
using Actors, Test, .Threads, .Delays
import Actors: spawn, info, diag, newLink

Base.:(==)(l1::Link, l2::Link) = hash(l1) == hash(l2)
t1 = Ref{Task}()
t2 = Ref{Task}()

me = newLink()
act1 = spawn(threadid, taskref=t1)
act2 = spawn(monitor, act1, taskref=t2)
send(act2, send, me)
a1 = diag(act1, :act)
a2 = diag(act2, :act)
@test a1.conn[1] isa Actors.Monitor
@test a1.conn[1].lk == act2
@test a2.conn[1] isa Actors.Monitored
@test a2.conn[1].lk == act1
@test a2.conn[1].action.f == send
send(act1, "boom")
f1 = receive(me)
@test f1 isa MethodError
@test Actors.diag(act2, :task).state == :runnable
@test isempty(a2.conn)
act1 = spawn(threadid, taskref=t1)
become!(act2, monitor, act1)
send(act2)
sleep(0.2)
a1 = diag(act1, :act)
println("a1.conn entries: ", length(a1.conn))
@test a1.conn[1] isa Actors.Monitor
@test a1.conn[1].lk == act2
@test isempty(a2.conn)
send(act1, "boom")
sleep(0.3)
println("isempty(me.chn) = ", isempty(me.chn))
println("n_avail = ", Base.n_avail(me.chn))
@test isempty(me.chn)
