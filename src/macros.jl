#
# Macro @spawn - Implementação Ergonômica
#
# Macro para criar atores com sintaxe simplificada
#

"""
    @spawn [name] [args...] [kwargs...] begin
        msg -> # processamento
    end

Ergonomic macro for spawning actors with reduced verbosity.

# Examples
```julia
# Simple actor:
lk = @spawn begin
    msg -> msg * 2
end
request(lk, 5)  # returns 10

# With name and args:
@spawn greeter "Hello" begin
    (greeting, msg) -> "\$greeting, \$msg!"
end
request(greeter, "World")  # returns "Hello, World!"

# Before (verbose):
greeter = spawn(Bhv(greet, "Hello"))

# After (ergonomic):
@spawn greeter "Hello" begin
    (greeting, msg) -> "\$greeting, \$msg!"
end
```
"""
macro spawn(args...)
    # Analisar argumentos
    has_name = !isempty(args) && args[1] isa Symbol
    name = has_name ? args[1] : nothing
    
    # Separar args posicionais e kwargs
    if has_name
        spawn_args = args[2:end-1]  # tudo exceto nome e corpo
    else
        spawn_args = args[1:end-1]  # tudo exceto corpo
    end
    
    # Separar kwargs (expressões com head = :kw ou :=)
    kwargs = filter(x -> x isa Expr && (x.head == :kw || x.head == :(:=)), spawn_args)
    pos_args = filter(x -> !(x isa Expr && (x.head == :kw || x.head == :(:=))), spawn_args)
    
    # O corpo do ator é a última expressão
    body = args[end]
    
    # Escapar o corpo para que variáveis externas sejam capturadas
    actor_body = esc(body)
    
    # Escapar argumentos posicionais e kwargs
    escaped_pos_args = [esc(arg) for arg in pos_args]
    escaped_kwargs = [esc(kw) for kw in kwargs]
    
    # Construir chamada para spawn(Bhv(...))
    if has_name
        # Se tem nome, criar variável no escopo do chamador
        var_name = esc(name)
        return quote
            $var_name = Actors.spawn(
                Actors.Bhv($actor_body, $(escaped_pos_args...); $(escaped_kwargs...))
            )
        end
    else
        # Se não tem nome, apenas retornar o link
        return quote
            Actors.spawn(
                Actors.Bhv($actor_body, $(escaped_pos_args...); $(escaped_kwargs...))
            )
        end
    end
end
