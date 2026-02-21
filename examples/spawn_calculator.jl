#
# Exemplo usando macro @spawn - Calculator
#
# Demonstração de atores com múltiplos argumentos e pattern matching
#

using Actors

println("=== Calculator Example with @spawn macro ===")

# Ator calculadora com múltiplas operações
@spawn calculator begin
    msg -> begin
        if msg isa Tuple
            op, a, b = msg
            if op == :add
                a + b
            elseif op == :sub
                a - b
            elseif op == :mul
                a * b
            elseif op == :div
                a / b
            else
                :unknown_operation
            end
        else
            :invalid_format
        end
    end
end

# Testar operações
println("add(5, 3) = ", request(calculator, (:add, 5, 3)))
println("sub(5, 3) = ", request(calculator, (:sub, 5, 3)))
println("mul(5, 3) = ", request(calculator, (:mul, 5, 3)))
println("div(15, 3) = ", request(calculator, (:div, 15, 3)))

# Limpeza
exit!(calculator)

println("\n=== Exemplo completo! ===")
