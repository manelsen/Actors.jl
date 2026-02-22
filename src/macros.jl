#
# @spawn macro - ergonomic actor creation
#

"""
    @spawn [name] [args...] [kwargs...] begin
        msg -> # processing
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
    has_name = !isempty(args) && args[1] isa Symbol
    name = has_name ? args[1] : nothing

    # Split positional args from keyword args
    if has_name
        spawn_args = args[2:end-1]  # everything except name and body
    else
        spawn_args = args[1:end-1]  # everything except body
    end

    # Separate kwargs (expressions with head :kw or :=)
    kwargs = filter(x -> x isa Expr && (x.head == :kw || x.head == :(:=)), spawn_args)
    pos_args = filter(x -> !(x isa Expr && (x.head == :kw || x.head == :(:=))), spawn_args)

    # Actor body is the last expression
    body = args[end]

    # Escape body so outer variables are captured correctly
    actor_body = esc(body)

    # Escape positional args and kwargs
    escaped_pos_args = [esc(arg) for arg in pos_args]
    escaped_kwargs = [esc(kw) for kw in kwargs]

    # Build spawn(Bhv(...)) call
    if has_name
        # Named: bind result to a variable in the caller's scope
        var_name = esc(name)
        return quote
            $var_name = Actors.spawn(
                Actors.Bhv($actor_body, $(escaped_pos_args...); $(escaped_kwargs...))
            )
        end
    else
        # Anonymous: just return the link
        return quote
            Actors.spawn(
                Actors.Bhv($actor_body, $(escaped_pos_args...); $(escaped_kwargs...))
            )
        end
    end
end
