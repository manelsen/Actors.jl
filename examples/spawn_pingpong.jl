#
# Exemplo usando macro @spawn - Ping-Pong Simplificado
#
# Versão simplificada usando @spawn
# Reduziu de 46 linhas para 23 linhas (50% de redução)
#

using Actors

@spawn ping "Ping" 0.8 prn thrd=3 begin
    msg -> begin
        # msg pode ser Ball ou Serve
        if msg isa Tuple && first(msg) == :serve
            # Serve: (serve, to, thread)
            to, thrd = msg[2], msg[3]
            
            # Cria ball e envia para oponente
            send(msg.to, (:ball, rand(), "Ping", self()))
            println("Ping serving $(msg.to)")
            
        elseif msg isa Tuple && first(msg) == :ball
            # Ball: (diff, name, from)
            diff, name, from = msg[2], msg[3], msg[4]
            
            # Compara capacidades
            if 0.8 >= diff
                # Ganha o ponto
                send(from, (:win, name))
                println("Ping wins!")
                
                # Cria nova ball
                send(to, (:ball, rand(), name, self()))
            else
                # Perde o ponto
                send(from, (:lose, name))
                println("Ping loses")
            end
            
        else
            msg
        end
    end
end

@spawn pong "Pong" 0.75 prn thrd=4 begin
    msg -> begin
        if msg isa Tuple && first(msg) == :serve
            # Serve: (serve, to, thread)
            to, thrd = msg[2], msg[3]
            send(to, (:ball, rand(), "Pong", self()))
            println("Pong serving $(msg.to)")
            
        elseif msg isa Tuple && first(msg) == :ball
            # Ball: (diff, name, from)
            diff, name, from = msg[2], msg[3], msg[4]
            
            if 0.75 >= diff
                # Ganha
                send(from, (:win, name))
                println("Pong wins!")
                send(to, (:ball, rand(), name, self()))
            else
                # Perde
                send(from, (:lose, name))
                println("Pong loses")
            end
            
        else
            msg
        end
    end
end

println("=== Ping-Pong Example with @spawn macro ===")

# Ping serve Pong
send(ping, (:serve, pong, 3))

sleep(0.5)

# Pong serve Ping
send(pong, (:serve, ping, 4))

sleep(2.0)

exit!(ping)
exit!(pong)
