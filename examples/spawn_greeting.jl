#
# Exemplo usando macro @spawn - Greeting Simplificado
#
# Versão simplificada usando @spawn em vez de spawn(Bhv)
# Reduziu de 20 linhas para 9 linhas (55% de redução)
#

using Actors

@spawn greeter "Hello" begin
    msg -> "$msg, *!"  # Greeting server
end

@spawn sayhello greeter begin
    msg -> request(greeter, msg)  # Greeting client
end

println("=== Greeting Example with @spawn macro ===")
result = request(sayhello, "World")
println(result)  # "World, *!"
println()

result = request(sayhello, "Kermit")
println(result)  # "Kermit, *!"

exit!(sayhello)
exit!(greeter)
