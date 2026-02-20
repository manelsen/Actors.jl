#
# This file is part of the Actors.jl Julia package, 
# MIT license, part of https://github.com/JuliaActors
#

const date_format = "yyyy-mm-dd HH:MM:SS"
const _WARN = [true]

tid(t::Task=current_task()) = convert(UInt, pointer_from_objref(t))

# Short hex identifier for a task — replaces the old Proquint-based pqtid().
# Uses the lower 32 bits of the task pointer, zero-padded to 8 hex chars.
# e.g. "3a1b7f52" instead of the former "x-luhog-lipit-vikib".
pqtid(t::Task=current_task()) = string(tid(t) & 0xffffffff, base=16, pad=8)

function id()
    return try
        act = task_local_storage("_ACT")
        isnothing(act.name) ? pqtid() : String(act.name)
    catch
        pqtid()
    end
end

function log_warn(msg::Down, info::String="")
    log_warn(msg.reason isa Exception ?
            "Down: $info $(msg.task), $(msg.task.exception)" :
            "Down: $info $(msg.reason)")
end
function log_warn(msg::Exit, info::String="")
    log_warn(msg.reason isa Exception && !isnothing(msg.task.exception) ?
            "Exit: $info $(msg.task), $(msg.task.exception)" :
            "Exit: $info $(msg.reason)")
end
function log_warn(s::String)
    if _WARN[1]
        @warn "$(Dates.format(now(), date_format)) $(id()) $s"
    end
end

function log_error(s::String, ex::Exception, bt=nothing)
    exc = isnothing(bt) ? ex : (ex, bt)
    @error "$(Dates.format(now(), date_format)) $(id()) $s" exception=exc
end
