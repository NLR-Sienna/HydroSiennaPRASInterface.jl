"""
Test suite for HydroEnergyReservoirPRAS hydro planning overloads.
"""

import HydroSiennaPRASInterface
import PowerSystems
import SiennaPRASInterface

const PSY = PowerSystems
const SPI = SiennaPRASInterface

@testset "Hydro Planning Overloads" begin

    @testset "generator_pras_bool_overload" begin
        model_true = SPI.GeneratorPRAS(true)
        @test isa(model_true, SPI.GeneratorPRAS)

        model_false = SPI.GeneratorPRAS(false)
        @test isa(model_false, SPI.GeneratorPRAS)
    end

    @testset "generator_pras_keyword_forwarding" begin
        model_kw_true = SPI.GeneratorPRAS(true; max_active_power="max_active_POWER")
        @test isa(model_kw_true, SPI.GeneratorPRAS)

        model_kw_false = SPI.GeneratorPRAS(false; max_active_power="max_active_POWER")
        @test isa(model_kw_false, SPI.GeneratorPRAS)
    end

    @testset "hydro_energy_reservoir_bool_overload" begin
        model_true = SPI.HydroEnergyReservoirPRAS(true)
        @test isa(model_true, SPI.HydroEnergyReservoirPRAS)

        model_false = SPI.HydroEnergyReservoirPRAS(false)
        @test isa(model_false, SPI.HydroEnergyReservoirPRAS)
    end

    @testset "hydro_energy_reservoir_original_still_works" begin
        model = SPI.HydroEnergyReservoirPRAS()
        @test isa(model, SPI.HydroEnergyReservoirPRAS)
    end

    @testset "hydro_energy_reservoir_keyword_forwarding" begin
        model_kw_true = SPI.HydroEnergyReservoirPRAS(true; max_active_power="max_active_POWER")
        @test isa(model_kw_true, SPI.HydroEnergyReservoirPRAS)

        model_kw_false = SPI.HydroEnergyReservoirPRAS(false; max_active_power="max_active_POWER")
        @test isa(model_kw_false, SPI.HydroEnergyReservoirPRAS)
    end

    @testset "energy_reservoir_soc_overload_if_available" begin
        if isdefined(SPI, :EnergyReservoirSoC)
            model_true = SPI.EnergyReservoirSoC(true)
            @test isa(model_true, SPI.EnergyReservoirSoC)

            model_false = SPI.EnergyReservoirSoC(false)
            @test isa(model_false, SPI.EnergyReservoirSoC)
        else
            @test true
        end
    end

end
