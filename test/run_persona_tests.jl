#
# Persona Test Runner
# Runs all persona-based test suites
#
# Each persona represents a different use case perspective:
# - Mariana: Distributed Systems Architect
# - Ricardo: Real-Time Systems Developer
# - Sofia: Security Engineer
# - Pedro: HPC Data Scientist
# - Ana: IoT/Edge Developer
#

using Test
using SafeTestsets

println("=" ^ 70)
println("  ACTORS.JL - PERSONA-BASED TEST SUITE")
println("  Testing from Multiple Expert Perspectives")
println("=" ^ 70)
println()

# ============================================================================
# PERSONA TESTS
# ============================================================================

println("Running PERSONA tests...")
println("-" ^ 50)

@safetestset "Mariana - Distributed Systems" begin 
    include("personas/test_mariana_distributed.jl") 
end

@safetestset "Ricardo - Real-Time Systems" begin 
    include("personas/test_ricardo_realtime.jl") 
end

@safetestset "Sofia - Security Engineering" begin 
    include("personas/test_sofia_security.jl") 
end

@safetestset "Pedro - HPC Data Science" begin 
    include("personas/test_pedro_hpc.jl") 
end

@safetestset "Ana - IoT/Edge Development" begin 
    include("personas/test_ana_iot.jl") 
end

println()
println("=" ^ 70)
println("  ALL PERSONA TESTS COMPLETED")
println("=" ^ 70)
