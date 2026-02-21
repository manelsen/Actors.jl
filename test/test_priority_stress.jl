#
# Stress Test: PriorityChannel
# Tests PriorityChannel under high load
#

using Test
using Actors

@testset "PriorityChannel Stress Tests" begin
    
    @testset "High throughput (10,000 messages)" begin
        ch = PriorityChannel(10000)
        
        # Put 10,000 messages
        for i in 1:10000
            put!(ch, PriorityMsg(i, rand(-10:10)))
        end
        
        @test length(ch) == 10000
        
        # Verify priority ordering
        last_priority = Inf
        last_counter = Inf
        count = 0
        
        while !isempty(ch)
            entry = ch.data[1]
            @test entry.priority <= last_priority
            if entry.priority == last_priority
                @test entry.counter >= last_counter
            end
            last_priority = entry.priority
            last_counter = entry.counter
            _ = take!(ch)
            count += 1
        end
        
        @test count == 10000
        close(ch)
    end
    
    @testset "Concurrent producers and consumers" begin
        ch = PriorityChannel(1000)
        produced = Ref(0)
        consumed = Ref(0)
        
        # 10 producers
        producers = [@async begin
            for i in 1:1000
                put!(ch, PriorityMsg(i, rand(1:5)))
                produced[] += 1
            end
        end for _ in 1:10]
        
        # 5 consumers
        consumers = [@async begin
            while true
                try
                    take!(ch)
                    consumed[] += 1
                catch e
                    break
                end
            end
        end for _ in 1:5]
        
        wait.(producers)
        sleep(1.0)
        close(ch)
        
        @test produced[] == 10000
        @test consumed[] == 10000
    end
    
    @testset "Priority inversion scenarios" begin
        ch = PriorityChannel(100)
        
        # Fill with low priority
        for i in 1:50
            put!(ch, PriorityMsg(Symbol("low_$i"), -10))
        end
        
        # Add one high priority in the middle
        put!(ch, PriorityMsg(:urgent, 100))
        
        # Add more low priority
        for i in 51:100
            put!(ch, PriorityMsg(Symbol("low_$i"), -10))
        end
        
        # High priority should come out first
        first = take!(ch)
        @test first == :urgent
        
        close(ch)
    end
    
    @testset "Mixed priorities (all levels)" begin
        ch = PriorityChannel(1000)
        
        # Send messages at all priority levels
        for _ in 1:100
            for p in -50:50
                put!(ch, PriorityMsg(p, p))
            end
        end
        
        # Extract and verify ordering
        last_p = Inf
        while !isempty(ch)
            msg = take!(ch)
            @test msg <= last_p
            last_p = msg
        end
        
        close(ch)
    end
end

println("PriorityChannel stress tests completed!")
