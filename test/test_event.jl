#
# Test EventManager (gen_event) functionality
#

using Test
using Actors
import Actors: spawn, newLink

@testset "EventManager basic" begin
    em = event_manager()
    
    events_log = []
    
    add_handler(em, :logger,
        () -> events_log,
        (event, state) -> begin
            push!(state, event)
            (state, [])
        end
    )
    
    sleep(0.05)
    
    send_event(em, :event1)
    send_event(em, :event2)
    send_event(em, :event3)
    
    sleep(0.1)
    
    @test :event1 in events_log
    @test :event2 in events_log
    @test :event3 in events_log
    
    exit!(em)
end

@testset "EventManager multiple handlers" begin
    em = event_manager()
    
    counter1 = Ref(0)
    counter2 = Ref(0)
    
    add_handler(em, :counter1,
        () -> counter1,
        (event, state) -> begin
            event == :increment && (state[] += 1)
            (state, [])
        end
    )
    
    add_handler(em, :counter2,
        () -> counter2,
        (event, state) -> begin
            event == :increment && (state[] += 10)
            (state, [])
        end
    )
    
    sleep(0.05)
    
    send_event(em, :increment)
    send_event(em, :increment)
    
    sleep(0.1)
    
    @test counter1[] == 2
    @test counter2[] == 20
    
    exit!(em)
end

@testset "EventManager call_handler" begin
    em = event_manager()
    
    add_handler(em, :stateful,
        () -> Dict{Symbol,Int}(),
        (event, state) -> begin
            if event isa Tuple && first(event) == :set
                state[event[2]] = event[3]
            end
            (state, [])
        end;
        handle_call = (request, state) -> begin
            if request isa Tuple && first(request) == :get
                key = request[2]
                (get(state, key, 0), state)
            else
                (:ok, state)
            end
        end
    )
    
    sleep(0.05)
    
    send_event(em, (:set, :a, 10))
    send_event(em, (:set, :b, 20))
    
    sleep(0.1)
    
    @test call_handler(em, :stateful, (:get, :a)) == 10
    @test call_handler(em, :stateful, (:get, :b)) == 20
    @test call_handler(em, :stateful, (:get, :c)) == 0
    
    exit!(em)
end

@testset "EventManager delete_handler" begin
    em = event_manager()
    
    counter = Ref(0)
    
    add_handler(em, :counter,
        () -> counter,
        (event, state) -> begin
            state[] += 1
            (state, [])
        end
    )
    
    sleep(0.05)
    
    send_event(em, :ping)
    sleep(0.05)
    @test counter[] == 1
    
    delete_handler(em, :counter)
    sleep(0.05)
    
    send_event(em, :ping)
    sleep(0.05)
    @test counter[] == 1
    
    exit!(em)
end

@testset "EventManager which_handlers" begin
    em = event_manager()
    
    add_handler(em, :handler1, () -> nothing, (e, s) -> (s, []))
    add_handler(em, :handler2, () -> nothing, (e, s) -> (s, []))
    add_handler(em, :handler3, () -> nothing, (e, s) -> (s, []))
    
    sleep(0.05)
    
    handlers = which_handlers(em)
    
    @test :handler1 in handlers
    @test :handler2 in handlers
    @test :handler3 in handlers
    
    exit!(em)
end

println("All EventManager tests passed!")
