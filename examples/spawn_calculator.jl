#
# Example: @spawn macro - Calculator
#
# Demonstrates actors with multiple arguments and pattern matching
#

using Actors

println("=== Calculator Example with @spawn macro ===")

# Calculator actor with multiple operations
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

# Test operations
println("add(5, 3) = ", request(calculator, (:add, 5, 3)))
println("sub(5, 3) = ", request(calculator, (:sub, 5, 3)))
println("mul(5, 3) = ", request(calculator, (:mul, 5, 3)))
println("div(15, 3) = ", request(calculator, (:div, 15, 3)))

# Cleanup
exit!(calculator)

println("\n=== Example complete! ===")
