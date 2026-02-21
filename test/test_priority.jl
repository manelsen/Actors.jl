#
# Test Priority Messages functionality
#

using Test
using Actors
import Actors: spawn, newLink

@testset "PriorityChannel basic" begin
    ch = PriorityChannel(10)
    
    put!(ch, :normal)
    put!(ch, PriorityMsg(:high, 5))
    put!(ch, PriorityMsg(:urgent, 10))
    put!(ch, PriorityMsg(:low, -5))
    
    @test take!(ch) == :urgent
    @test take!(ch) == :high
    @test take!(ch) == :normal
    @test take!(ch) == :low
    
    close(ch)
end

@testset "PriorityChannel FIFO within same priority" begin
    ch = PriorityChannel(10)
    
    put!(ch, PriorityMsg(:first, 5))
    put!(ch, PriorityMsg(:second, 5))
    put!(ch, PriorityMsg(:third, 5))
    
    @test take!(ch) == :first
    @test take!(ch) == :second
    @test take!(ch) == :third
    
    close(ch)
end

@testset "PriorityChannel mixed priorities" begin
    ch = PriorityChannel(20)
    
    for i in 1:5
        put!(ch, PriorityMsg(Symbol("low_$i"), -1))
    end
    for i in 1:5
        put!(ch, PriorityMsg(Symbol("high_$i"), 1))
    end
    for i in 1:5
        put!(ch, PriorityMsg(Symbol("normal_$i"), 0))
    end
    
    high_msgs = Symbol[]
    for _ in 1:5
        push!(high_msgs, take!(ch))
    end
    @test all(m -> startswith(string(m), "high_"), high_msgs)
    
    normal_msgs = Symbol[]
    for _ in 1:5
        push!(normal_msgs, take!(ch))
    end
    @test all(m -> startswith(string(m), "normal_"), normal_msgs)
    
    low_msgs = Symbol[]
    for _ in 1:5
        push!(low_msgs, take!(ch))
    end
    @test all(m -> startswith(string(m), "low_"), low_msgs)
    
    close(ch)
end

@testset "send_priority functions" begin
    ch = PriorityChannel(10)
    
    send_high(Link(ch, 1, :priority), :high_msg)
    send_low(Link(ch, 1, :priority), :low_msg)
    send_priority(Link(ch, 1, :priority), :urgent_msg, 100)
    
    @test take!(ch) == :urgent_msg
    @test take!(ch) == :high_msg
    @test take!(ch) == :low_msg
    
    close(ch)
end

@testset "PriorityChannel with actor" begin
    processed = Symbol[]
    
    lk = newPriorityLink(32)
    t = Task(() -> begin
        while true
            msg = take!(lk.chn)
            msg == :stop && break
            push!(processed, msg)
        end
    end)
    schedule(t)
    
    sleep(0.1)
    
    put!(lk.chn, :normal1)
    send_priority(lk, :urgent, 10)
    put!(lk.chn, :normal2)
    send_low(lk, :background)
    put!(lk.chn, :normal3)
    
    sleep(0.3)
    
    put!(lk.chn, :stop)
    sleep(0.1)
    
    @test first(processed) == :urgent
    @test last(processed) == :background
    @test length(processed) == 5
    
    close(lk.chn)
end

@testset "newPriorityLink" begin
    lk = newPriorityLink(16)
    
    @test lk.chn isa PriorityChannel
    @test lk.mode == :priority
    
    close(lk.chn)
end

println("All Priority Messages tests passed!")
