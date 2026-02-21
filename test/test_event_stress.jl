#
# Stress Test: EventManager
# Tests EventManager under high load with many handlers
#

using Test
using Actors
import Actors: spawn

@testset "EventManager Stress Tests" begin
    
    @testset "Many events (10,000 events)" begin
        count = Ref(0)
        
        em = event_manager()
        add_handler(em, :counter,
            () -> count,
            (event, state) -> begin
                state[] += 1
                (state, [])
            end
        )
        
        sleep(0.1)
        
        # Rapid events
        for _ in 1:10000
            send_event(em, :tick)
        end
        
        sleep(2.0)
        
        @test count[] == 10000
        exit!(em)
    end
    
    @testset "Many handlers (100 handlers)" begin
        em = event_manager()
        
        counters = [Ref(0) for _ in 1:100]
        
        for i in 1:100
            add_handler(em, Symbol("handler_$i"),
                () -> counters[i],
                (event, state) -> begin
                    state[] += 1
                    (state, [])
                end
            )
        end
        
        sleep(0.5)
        
        # One event should go to all 100 handlers
        send_event(em, :test)
        sleep(1.0)
        
        @test all(c -> c[] == 1, counters)
        exit!(em)
    end
    
    @testset "Rapid add/remove handlers" begin
        em = event_manager()
        
        # Add and remove handlers rapidly
        for i in 1:100
            handler_id = Symbol("temp_$i")
            add_handler(em, handler_id,
                () -> 0,
                (event, state) -> (state + 1, state)
            )
            sleep(0.001)
            delete_handler(em, handler_id)
        end
        
        sleep(0.5)
        
        # Should have no handlers left
        handlers = which_handlers(em)
        @test isempty(handlers)
        exit!(em)
    end
    
    @testset "Concurrent add/remove/send" begin
        em = event_manager()
        
        # Start with some handlers
        for i in 1:10
            add_handler(em, Symbol("base_$i"),
                () -> 0,
                (event, state) -> (state + 1, state)
            )
        end
        
        sleep(0.1)
        
        # Concurrent operations
        adder = @async begin
            for i in 1:50
                add_handler(em, Symbol("add_$i"), () -> 0, (e, s) -> (s, s))
                sleep(0.01)
            end
        end
        
        remover = @async begin
            sleep(0.2)
            for i in 1:20
                delete_handler(em, Symbol("base_$i"))
                sleep(0.01)
            end
        end
        
        sender = @async begin
            for _ in 1:100
                send_event(em, :concurrent_test)
                sleep(0.005)
            end
        end
        
        wait(adder)
        wait(remover)
        wait(sender)
        sleep(0.5)
        
        # Should still be responsive
        final_handlers = which_handlers(em)
        @test length(final_handlers) > 0
        exit!(em)
    end
end

println("EventManager stress tests completed!")
