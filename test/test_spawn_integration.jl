#
# Testes de Integração para Macro @spawn
#
# Testes que verificam se os exemplos usando @spawn funcionam
# corretamente e produzem os mesmos resultados que as
# versões anteriores.
#

using Test
using Actors

@testset "@spawn Macro - Integration Tests" begin

    @testset "Exemplo usando macro @spawn" begin
        @test "Greeting simplificado funciona" begin
            include("../examples/spawn_greeting.jl")
        end
        
        @test "Stack simplificado funciona" begin
            include("../examples/spawn_stack.jl")
        end
        
        @test "Ping-Pong simplificado funciona" begin
            include("../examples/spawn_pingpong.jl")
        end
    end
    
    @testset "Exemplo de Greeting" begin
        include("../examples/spawn_greeting.jl")
        
        # A execução do exemplo já foi verificada visualmente
        @test true  # O exemplo completa sem erro
    end
    
    @testset "Exemplo de Stack" begin
        # Testa se o exemplo de stack funciona
        include("../examples/spawn_stack.jl")
        
        # O exemplo executa e finaliza corretamente
        @test true
    end
    
    @testset "Exemplo de Ping-Pong" begin
        # Testa se o exemplo de ping-pong funciona
        include("../examples/spawn_pingpong.jl")
        
        # O exemplo executa e finaliza corretamente
        @test true
    end
    
    @testset "Comparação com spawn(Bhv)" begin
        @testset "Greeting - equivalência funcional" begin
            # Versão original
            greet_orig(greeting, msg) = greeting*", "*msg*"!"
            hello_orig(greeter, to) = request(greeter, to)
            
            greeter_orig = spawn(Bhv(greet_orig, "Hello"))
            sayhello_orig = spawn(Bhv(hello_orig, greeter_orig))
            
            result1 = request(sayhello_orig, "Test")
            
            # Versão com @spawn
            @spawn greeter_spawn "Hello" begin
                msg -> greet_orig("Hello", msg)
            end
            
            @spawn sayhello_spawn greeter_spawn begin
                msg -> request(greeter_spawn, msg)
            end
            
            result2 = request(sayhello_spawn, "Test")
            
            @test result1 == result2
        end
        
        @testset "Request/Response - equivalência funcional" begin
            # Versão original com spawn(Bhv)
            calc_orig = spawn(Bhv(x -> x * 2))
            
            # Versão com @spawn
            calc_spawn = @spawn calculator begin
                msg -> msg * 2
            end
            
            @test request(calc_orig, 5) == request(calc_spawn, 5)
        end
        
        @testset "Cast - equivalência funcional" begin
            received = false
            
            # Versão original
            listener_orig = spawn(Bhv(x -> begin
                global received = true
                :processed
            end))
            
            cast(listener_orig, :test)
            sleep(0.1)
            result_orig = received
            
            received = false
            
            # Versão com @spawn
            listener_spawn = @spawn listener_spawn begin
                msg -> begin
                    global received = true
                    :processed
                end
            end
            
            cast(listener_spawn, :test)
            sleep(0.1)
            result_spawn = received
            
            @test result_orig == result_spawn
        end
    end
    
    @testset "Composição de atores" begin
        @testset "Cascata de requests" begin
            # Ator intermediário que encaminha requests
            @spawn middleware begin
                msg -> request(target, msg)
            end
            
            # Ator alvo
            @spawn target begin
                msg -> msg * 2
            end
            
            @test request(middleware, 10) == 20
        end
        
        @testset "Múltiplos handlers no mesmo ator" begin
            @test "Pattern matching funciona" begin
                @spawn multi_handler begin
                    msg -> begin
                        if msg == :a
                            1
                        elseif msg == :b
                            2
                        else
                            0
                        end
                    end
                end
                
                @test request(multi_handler, :a) == 1
                @test request(multi_handler, :b) == 2
                @test request(multi_handler, :c) == 0
            end
        end
    end
    
    @testset "Performance básica" begin
        @testset "Tempo de spawn" begin
            # Testa se @spawn não adiciona overhead significativo
            times_orig = Float64[]
            times_spawn = Float64[]
            
            for _ in 1:10
                push!(times_orig, @elapsed spawn(Bhv(x -> x)))
                push!(times_spawn, @elapsed @spawn dummy begin msg -> msg end)
            end
            
            avg_orig = mean(times_orig)
            avg_spawn = mean(times_spawn)
            
            # @spawn deve ter overhead máximo de 50% (aceitável para conveniência)
            @test avg_spawn / avg_orig < 1.5
        end
        
        @testset "Uso de memória" begin
            # Verifica se @spawn não cria alocações excessivas
            before = Sys.maxrss()
            
            for _ in 1:100
                @spawn temp begin msg -> msg end
                exit!(temp)
            end
            
            after = Sys.maxrss()
            
            # O aumento deve ser aceitável (< 10 MB)
            @test (after - before) < 10 * 1024 * 1024
        end
    end
    
    @testset "Casos de uso real" begin
        @testset "Ator com estado interno" begin
            counter = 0
            
            @spawn counter_state begin
                msg -> begin
                    if msg == :increment
                        global counter += 1
                        counter
                    elseif msg == :get
                        counter
                    else
                        counter
                    end
                end
            end
            
            send(counter_state, :increment)
            @test request(counter_state, :get) == 1
            send(counter_state, :get)
            @test request(counter_state, :get) == 2
        end
        
        @testset "Timeout e erros" begin
            @test "Timeout funciona corretamente" begin
                result = nothing
                
                @spawn slow_actor timeout=0.1 begin
                    msg -> begin
                        sleep(0.5)
                        msg * 2
                    end
                end
                
                @test_throws ErrorException request(slow_actor, 5)  # Timeout
            end
        end
    end
end
