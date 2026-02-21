#
# Testes Unitários para Macro @spawn
#
# Testes unitários focados em verificar que a macro @spawn se comporta
# corretamente em diferentes cenários.
#

using Test
using Actors
using ..Actors  # Acesso ao módulo principal (será ajustado na integração)

@testset "@spawn Macro - Unit Tests" begin

    @testset "Sintaxe básica" begin
        @testset "Spawn sem nome" begin
            @test "Cria ator com função anônima" begin
                lk = @spawn begin
                    x -> x + 1
                end
                
                result = request(lk, 5)
                @test result == 6
            end
            
            @test "Suporta argumentos posicionais" begin
                lk = @spawn begin
                    (a, b) -> a + b
                end
                
                result = request(lk, 3, 7)
                @test result == 10
            end
            
            @test "Suporta keyword arguments" begin
                lk = @spawn timeout=5.0 begin
                    (x,) -> x * 2
                end
                
                result = request(lk, 4)
                @test result == 8
            end
        end
        
        @testset "Spawn com nome" begin
            @test "Usa nome especificado" begin
                lk = @spawn myactor begin
                    msg -> msg * 2
                end
                
                @test lk.mode == :default  # Verifica se link foi criado corretamente
                result = request(lk, 5)
                @test result == 10
            end
            
            @test "Suporta args posicionais com nome" begin
                lk = @spawn myactor 42 begin
                    (x,) -> x + 1
                end
                
                result = request(lk, 41)
                @test result == 42
            end
        end
    end
    
    @testset "Comportamentos especiais" begin
        @testset "Request/Response automático" begin
            @test "Última expressão retornada como response" begin
                lk = @spawn calculator begin
                    msg -> msg * msg  # msg^2
                end
                
                @test request(lk, 5) == 25
                @test request(lk, 3) == 9
            end
        end
        
        @testset "Cast (sem resposta)" begin
            @test "Não bloqueia em cast" begin
                processed = false
                
                lk = @spawn listener begin
                    msg -> begin
                        global processed = true
                        :processed
                    end
                end
                
                cast(lk, :test)
                sleep(0.1)
                @test processed === true  # cast deve continuar executando
            end
        end
        
        @testset "Múltiplos handlers" begin
            @test "Pattern matching em função anônima" begin
                lk = @spawn matcher begin
                    msg -> begin
                        if msg isa Integer
                            msg * 2
                        elseif msg == :hello
                            :hi_there
                        else
                            :unknown
                        end
                    end
                end
                
                @test request(lk, 10) == 20
                @test request(lk, :hello) == :hi_there
                @test request(lk, :test) == :unknown
            end
        end
    end
    
    @testset "Variável msg" begin
        @testset "msg está disponível no corpo" begin
            @test "Pode acessar msg diretamente" begin
                captured_msg = nothing
                
                lk = @spawn begin
                    global captured_msg = msg
                end
                
                send(lk, :test)
                sleep(0.1)
                @test captured_msg == :test
            end
            
            @test "msg contém mensagem completa" begin
                lk = @spawn begin
                    msg -> (msg isa Integer) ? msg * 2 : :not_int
                end
                
                @test request(lk, 5) == 10
                @test request(lk, "hello") == :not_int
            end
        end
    end
    
    @testset "Escopo de variáveis" begin
        @testset "Closure captura variáveis corretamente" begin
            @test "Captura argumentos externos" begin
                multiplier = 3
                
                lk = @spawn multiplier begin
                    msg -> msg * multiplier
                end
                
                @test request(lk, 5) == 15
            end
            
            @test "Não polui escopo global" begin
                # Verifica se macro não cria poluição global desnecessária
                before = length(names(Main))
                
                lk = @spawn local_test begin
                    msg -> msg
                end
                
                exit!(lk)
                
                after = length(names(Main))
                @test before == after
            end
        end
    end
    
    @testset "Compatibilidade com spawn(Bhv)" begin
        @testset "Resultado equivalente" begin
            @test "@spawn produces same result as spawn(Bhv)" begin
                # Criar dois atores equivalentes
                lk1 = @spawn actor1 begin
                    msg -> msg * 2
                end
                
                lk2 = spawn(Bhv(x -> x * 2))
                
                @test request(lk1, 7) == request(lk2, 7)
            end
        end
    end
    
    @testset "Casos de borda" begin
        @testset "Mensagens de diferentes tipos" begin
            @test "Suporta Symbol" begin
                lk = @spawn begin
                    msg -> msg == :test
                end
                
                @test request(lk, :test) == true
            end
            
            @test "Suporta String" begin
                lk = @spawn begin
                    msg -> "echo: " * msg
                end
                
                @test request(lk, "hello") == "echo: hello"
            end
            
            @test "Suporta Complex types" begin
                struct MyMsg
                    value::Int
                end
                
                lk = @spawn begin
                    msg -> msg isa MyMsg
                end
                
                @test request(lk, MyMsg(42)) === true
            end
        end
        
        @testset "Sem mensagem inicial" begin
            @test "Ator funciona sem receber mensagem" begin
                count = 0
                
                lk = @spawn counter begin
                    msg -> begin
                        global count += 1
                        count
                    end
                end
                
                sleep(0.1)
                @test count == 0  # Nenhuma mensagem foi enviada ainda
            end
        end
    end
end
