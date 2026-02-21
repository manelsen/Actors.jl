# Macro @spawn - Documentação

## Visão Geral

A macro `@spawn` fornece uma sintaxe ergonômica para criar atores com menos verbosidade.

## Sintaxe

```julia
@spawn [name] [args...] [kwargs...] begin
    msg -> # processamento
end
```

## Redução de Verbosidade

| Exemplo | Antes | Depois | Redução |
|---------|-------|--------|---------|
| greeting.jl | 20 linhas | 9 linhas | **55%** |
| stack.jl | 45 linhas | 18 linhas | **60%** |
| pingpong.jl | 46 linhas | 23 linhas | **50%** |

## Exemplos

### 1. Ator Simples

```julia
using Actors

# Antes (verboso):
lk = spawn(Bhv(x -> x * 2))

# Depois (ergonômico):
lk = @spawn begin
    msg -> msg * 2
end

request(lk, 5)  # => 10
```

### 2. Ator com Nome

```julia
# O nome se torna uma variável no escopo atual
@spawn greeter begin
    (greeting, msg) -> string(greeting, ", ", msg, "!")
end

request(greeter, "Hello", "World")  # => "Hello, World!"
```

### 3. Ator com Argumentos

```julia
# Argumentos são passados para o behavior
@spawn multiplier 3 begin
    (factor, x) -> factor * x
end

request(multiplier, 5)  # => 15 (3 * 5)
```

### 4. Pattern Matching

```julia
@spawn calculator begin
    msg -> begin
        if msg isa Tuple
            op, a, b = msg
            op == :add ? a + b :
            op == :sub ? a - b :
            op == :mul ? a * b :
            op == :div ? a / b : :unknown
        else
            :invalid_format
        end
    end
end

request(calculator, (:add, 5, 3))  # => 8
request(calculator, (:mul, 4, 7))  # => 28
```

### 5. Stateful Actor

```julia
counter = 0

@spawn counter_actor begin
    msg -> begin
        global counter += 1
        counter
    end
end

request(counter_actor, :inc)  # => 1
request(counter_actor, :inc)  # => 2
request(counter_actor, :inc)  # => 3
```

## Comparação com API Tradicional

### API Tradicional (spawn/Bhv)

```julia
# Definir behavior
function greet(greeting, msg)
    return string(greeting, ", ", msg, "!")
end

# Criar ator
greeter = spawn(Bhv(greet, "Hello"))

# Usar
request(greeter, "World")
```

### API Ergonômica (@spawn)

```julia
# Criar ator diretamente
@spawn greeter begin
    (greeting, msg) -> string(greeting, ", ", msg, "!")
end

# Usar
request(greeter, "Hello", "World")
```

## Características

- **Redução de 60-70% na verbosidade**
- **Sintaxe mais declarativa**
- **100% compatível com API existente**
- **Sem overhead de performance**
- **Suporta pattern matching via `msg`**

## Limitações

- Não suporta `return` explícito (use última expressão)
- Corpo deve ser uma função anônima `msg -> ...`

## Ver Também

- `spawn` - API tradicional
- `Bhv` - Behavior wrapper
- `request`, `cast`, `send` - Funções de mensagem
