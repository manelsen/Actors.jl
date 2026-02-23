# Solução 4: Custom Thread Pool - Análise de Falha

## Implementação Tentada

Foi criado um módulo `ThreadPool` customizado em `src/threadpool.jl` com:

- `ThreadPool` struct com channels por thread
- `@tspawnat` macro para agendar tarefas em threads específicas
- `Future` type para capturar resultados
- Workers usando `@async` para processar tarefas

## Problema Fundamental

**A Solução 4 NÃO É VIÁVEL** sem usar APIs internas de Julia.

### Por que Falhou

O teste falhou porque:
```julia
act2 = spawn(threadid, thrd=2)
@test request(act2) == 2  # Esperava 2, obteve 1
```

A task foi agendada para rodar na thread 2, mas executou na thread 1.

### Causa Raiz

Julia **NÃO oferece uma API pública** para:

1. **Pinar uma task a uma thread específica**
   - `@async` distribui tasks aleatoriamente entre threads
   - `Threads.@spawn` também não permite especificar thread ID

2. **Criar workers em threads específicas**
   - Não há forma de garantir que uma task rode em uma thread específica
   - O scheduler do Julia decide onde cada task executa

### Por que ThreadPools.jl funciona

ThreadPools.jl **usa APIs internas** de Julia para fazer thread pinning:

```julia
# No código fonte do ThreadPools.jl:
ccall(:jl_set_task_tid, Cvoid, (Any, Cint), task, thread_id - 1)
```

Esta é a **mesma API interna** que estamos tentando evitar!

## Alternativas Possíveis

### ✅ Solução 1: Reverter para ccall (original)
**Vantagens:**
- Funciona e já estava testado
- Sem dependências externas
- Performance excelente

**Desvantagens:**
- Usa API interna `:jl_set_task_tid`
- Pode quebrar com atualizações Julia
- Não documentado nem estável

**Veredito:** Mais rápido, mas instável.

### ✅ Solução 5: ThreadPools.jl
**Vantagens:**
- API pública e documentada
- Mantida pela comunidade
- Sem risco de crash por updates Julia

**Desvantagens:**
- Adiciona dependência externa
- Pequena penalidade de performance
- Usa API internamente (mas isolado do código do usuário)

**Veredito:** Equilíbrio ideal entre estabilidade e funcionalidade.

### ❌ Solução 4: Custom Thread Pool
**Vantagens:**
- Controle total sobre código

**Desvantagens:**
- **IMPOSSÍVEL** sem APIs internas
- Teria que reinventar ThreadPools.jl
- Complexidade alta para manutenção

**Veredito:** NÃO VIÁVEL.

## Recomendação

**Continuar com Solução 5 (ThreadPools.jl)**

### Justificativa

1. **Solução 4 é impossível sem APIs internas**
   - Julia não oferece API pública para thread pinning
   - Qualquer implementação customizada precisaria de `ccall(:jl_set_task_tid, ...)`

2. **ThreadPools.jl é o melhor compromisso**
   - APIs públicas para o usuário
   - Usa APIs internas, mas isoladas em um pacote
   - Atualizações do pacote acompanham Julia
   - Comunidade mantém e testa

3. **Trade-off de performance aceitável**
   - Latência: 54-75% mais lento em alguns benchmarks
   - Throughput: 13-26% mais rápido em fire-and-forget
   - Ainda sub-millisecond (< 1.2ms)
   - Estabilidade >> Pequeno custo de performance

## Conclusão

**A Solução 4 (Custom Thread Pool) não é tecnicamente viável** sem usar APIs internas de Julia ou depender de ThreadPools.jl que por sua vez usa essas APIs.

**Recomenda-se manter a Solução 5 (ThreadPools.jl)** que foi implementada anteriormente.

### Próximos Passos

1. Reverter código da Solução 4
2. Restaurar código da Solução 5 (ThreadPools.jl)
3. Documentar por que a Solução 4 foi descartada
4. Considerar adicionar um modo de configuração para alternar entre:
   - `:threadpools` (padrão, estável)
   - `:unsafe` (ccall direto, não recomendado)
   - `:disabled` (sem thread pinning)
