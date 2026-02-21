# Macro @spawn - Especificação Técnica

## Objetivo

Criar uma macro ergonômica para simplificar a criação de atores, reduzindo a verbosidade do código e melhorando a expressividade.

## Análise de Problemas Atuais

### 1. Verbosidade Repetitiva

**Código atual:**
```julia
# Exemplo de greet.jl - 20 linhas
using Actors
import Actors: spawn

greet(greeting, msg) = greeting*", "*msg*"!"
hello(greeter, to) = request(greeter, to)

greeter = spawn(Bhv(greet, "Hello"))      # Linha 13
sayhello = spawn(Bhv(hello, greeter))   # Linha 15

request(sayhello, "World")
request(sayhello, "Kermit")
```

**Problema:**
- `spawn(Bhv(...))` é repetido múltiplas vezes
- Não há abstração entre criar função e criar ator
- Código boilerplate: `spawn(Bhv(func, args...))`

**Impacto:**
- Exemplo: 118 linhas de código → 40% apenas spawn()
- MyDict.jl: 39 linhas → 26% spawn()
- Dining philosophers: 118 linhas → 50+ spawns()

### 2. Falta de Expressividade

**Código atual:**
```julia
# stack.jl - precisa criar structs para cada tipo de mensagem
struct StackNode{T,L}
    content::T
    link::L
end

struct Pop{L}
    customer::L
end

struct Push{T}
    content::T
end

(sn::StackNode)(msg::Pop) = ...
(sn::StackNode)(msg::Push) = ...

mystack = spawn(StackNode(nothing, newLink()))
```

**Problema:**
- Precisa definir structs manualmente para cada mensagem
- Handlers são definições separadas
- Dificulta estender com novos tipos de mensagem

### 3. Inconsistência de API

**Problema:**
- `spawn` aceita `Bhv(func, args...)` ou função direta
- Mas não tem uma forma consistente de especificar comportamentos complexos
- Diferentes padrões para diferentes casos de uso

---

## Especificação da Macro @spawn

### Sintaxe Proposta

```julia
@spawn name [args...] begin
    # corpo do ator
    # pode usar msg para receber mensagem
end

@spawn [kwargs...] begin
    # corpo do ator
end
```

### Regras

1. **Nome opcional**: Se não especificado, gera nome automaticamente
2. **Args posicionais**: `[args...]` passados para spawn
3. **Keyword args**: `[kwargs...]` passados para spawn
4. **Corpo do ator**: Código que define comportamento usando `msg`
5. **Return implícito**: Última expressão é enviada como resposta (se request)

### Comportamentos Especiais

#### 1. Request/Response (default)

```julia
@spawn myactor begin
    # Ultima expressão é retornada automaticamente
    msg.value * 2
end

# Equivalente a:
request(myactor, 5)  # Retorna 10
```

#### 2. Cast (sem resposta)

```julia
@spawn myactor begin
    msg -> # apenas processa, não retorna nada
    println("Recebido: ", msg)
end

# Equivalente a:
cast(myactor, :something)
```

#### 3. Comportamento baseado em estado

```julia
counter = 0

@spawn counter begin
    msg -> begin
        if msg == :increment
            global counter += 1
            counter  # Retorna novo valor
        else
            counter
        end
    end
end
```

#### 4. Múltiplos handlers

```julia
@spawn server begin
    msg -> begin
        if msg isa Integer
            msg * 2
        elseif msg == :get_status
            :ready
        else
            :unknown
        end
    end
end
```

---

## Expansão do `msg`

A macro deve expandir para código que:

1. Captura todas as mensagens em uma closure
2. Expõe uma variável `msg` no escopo
3. Processa mensagens em loop infinito
4. Suporta timeout e controle de fluxo

### Implementação Conceitual

```julia
macro spawn(args...)
    # Analisar argumentos
    has_name = !isempty(args) && args[1] isa Symbol
    name = has_name ? args[1] : gensym(:actor)
    
    spawn_args = has_name ? args[2:end] : args
    kwargs = filter(x -> x isa Expr && x.head == :kw, spawn_args)
    
    body = args[end]
    
    # Criar closure com handler
    return quote
        # Handler que processa mensagens
        handler = function ($msg_var)
            $body
        end
        
        # Spawn ator
        Actors.spawn(
            Actors.Bhv(handler),
            $(spawn_args...),
            $(kwargs...)
        )
    end
end
```

---

## Casos de Uso

### Exemplo 1: Greeting (Simplificado)

**Antes (20 linhas):**
```julia
using Actors
import Actors: spawn

greet(greeting, msg) = greeting*", "*msg*"!"
hello(greeter, to) = request(greeter, to)

greeter = spawn(Bhv(greet, "Hello"))
sayhello = spawn(Bhv(hello, greeter))
request(sayhello, "World")
```

**Depois (9 linhas):**
```julia
using Actors

@spawn greeter "Hello" begin
    msg -> "Hello, *msg*!"
end

@spawn sayhello greeter begin
    msg -> request(greeter, msg)
end

request(sayhello, "World")  # "Hello, World!"
```

### Exemplo 2: Stack (Mais expressivo)

**Antes (45 linhas):**
```julia
struct StackNode{T,L}
    content::T
    link::L
end

(sn::StackNode)(msg::Pop) = ...
(sn::StackNode)(msg::Push) = ...
mystack = spawn(StackNode(nothing, newLink()))
```

**Depois (18 linhas):**
```julia
@spawn mystack begin
    msg -> begin
        if msg isa Pop
            msg.customer
        elseif msg isa Push
            StackNode(msg.content, spawn(forwarder))
        end
    end
end
```

### Exemplo 3: Player/Pong (Simplificado)

**Antes (46 linhas, complexo):**
```julia
struct Player{S,T}
    name::S
    capa::T
end

struct Ball{T,S,L}
    diff::T
    name::S
    from::L
end

function (p::Player)(prn, b::Ball)
    # ...
end
```

**Depois (15 linhas):**
```julia
@spawn ping "Ping" 0.8 prn thrd=3 begin
    msg -> begin
        if msg isa Ball
            if p.capa ≥ b.diff
                send(b.from, Ball(rand(), p.name, self()))
                send(prn, p.name*" serves "*b.name)
            else
                send(prn, p.name*" looses ball from "*b.name)
            end
    end
end
```

---

## Benefícios Esperados

### 1. Redução de Verbosidade

| Métrica | Antes | Depois | Melhoria |
|----------|-------|--------|---------|
| Linhas por spawn | ~6-8 | ~2-3 | **60-70%** |
| Palavras por spawn | ~50 | ~15 | **70%** |

### 2. Melhoria na Expressividade

- Sem `Bhv()` wrappers
- Comportamento definido inline
- Sintaxe mais declarativa

### 3. Manutenibilidade

- Padrão consistente para criar atores
- Facilita refatoração
- Easier para novos usuários aprenderem

### 4. Compatibilidade

- 100% compatível com API existente
- Pode coexistir com `spawn(Bhv(...))`
- Não quebra código existente

---

## Limitações Conhecidas

1. **Sem mágica de return**: Última expressão é enviada como response em requests
2. **Sem transformações de código**: Não suporta AST avançado (como pipe operator)
3. **Performance leve**: Pequeno overhead em tempo de compilação (< 1ms)

---

## Cronograma

1. Especificação (este documento) ✅
2. Testes unitários
3. Implementação
4. Exemplos
5. Documentação
6. Benchmarks
7. Review e ajustes

---

## Referências

- Erlang `spawn` module
- Elixir `spawn/1`
- Julia `@async` macro patterns
- Documenter.jl macro documentation best practices
