#
# Exemplo usando macro @spawn - Greeting Simplificado
#

using Actors

println("=== Greeting Example with @spawn macro ===")

# Criar ator greeter
@spawn greeter begin
    (greeting, msg) -> string(greeting, ", ", msg, "!")
end

# Criar ator sayhello que usa greeter
@spawn sayhello begin
    msg -> request(greeter, "Hello", msg)
end

# Testar
result1 = request(sayhello, "World")
println("request(sayhello, \"World\") = \"", result1, "\"")

result2 = request(sayhello, "Kermit")
println("request(sayhello, \"Kermit\") = \"", result2, "\"")

# Limpeza
exit!(greeter)
exit!(sayhello)

println("\n=== Exemplo completo! ===")
