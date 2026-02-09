using HydroSiennaPRASInterface
using Test

@testset "HydroSiennaPRASInterface.jl" begin
    @testset "Basic functionality" begin
        # Test that the module loads
        @test HydroSiennaPRASInterface isa Module
        
        # Test the greet function
        @test greet() === nothing
    end
end
