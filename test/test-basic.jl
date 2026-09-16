@testset "Basic functionality" begin
    import HydroSiennaPRASInterface
    @test HydroSiennaPRASInterface isa Module
    @test HydroSiennaPRASInterface.greet() === nothing
end
