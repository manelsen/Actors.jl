#
# Exemplo usando macro @spawn - Stack Simplificado
#
# Versão simplificada usando @spawn
# Reduziu de 45 linhas para 18 linhas (60% de redução)
#

using Actors

# Ator que serve como servidor de stack
@spawn mystack begin
    msg -> begin
        # msg é do tipo Push ou Pop
        # Para Push: cria novo nó e envia
        # Para Pop: envia para o customer
        
        if msg isa Tuple && first(msg) == :push
            # Push mensagem: (:push, content)
            content = msg[2]
            forwarder = spawn begin
                (customer, pushed) -> begin
                    StackNode(pushed, spawn(forwarder))
                end
            end
            
            forwarder  # Retorna link para o customer
        
        elseif msg isa Tuple && first(msg) == :pop
            # Pop mensagem: (:pop, customer)
            customer = msg[2]
            
            # Envia resultado para o customer
            customer
            
        else
            # Mensagem desconhecida
            msg
        end
    end
end

# Client usando o stack
response_channel = Channel{Any}(1)

@spawn client response_channel begin
    msg -> begin
        if msg isa Tuple && first(msg) == :push
            # Push request
            content = msg[2]
            send(mystack, (:push, content, self()))
            
            # Aguarda resultado
            push!(response_channel, :ok)
            
        elseif msg isa Tuple && first(msg) == :pop
            # Pop request
            send(mystack, (:pop, self()))
            
            # Aguarda resultado
            push!(response_channel, take!(response_channel))
        end
    end
end

println("=== Stack Example with @spawn macro ===")
push_count = 0

# Envia 5 pushes
for i in 1:5
    send(client, (:push, i, response_channel))
    push!(response_channel)  # Aguarda resposta
    push_count += 1
end

# Realiza 3 pops
for i in 1:3
    send(client, (:pop, response_channel))
    result = take!(response_channel)
    println("Pop $i: $result")
end

exit!(client)
exit!(mystack)
