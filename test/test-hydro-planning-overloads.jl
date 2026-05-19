"""
Test suite for HydroEnergyReservoirPRAS hydro planning overloads.
"""

import HydroSiennaPRASInterface
import PowerSystems
import SiennaPRASInterface

const PSY = PowerSystems
const SPI = SiennaPRASInterface
const HSPI = HydroSiennaPRASInterface

@testset "Hydro Planning Overloads" begin

    @testset "generator_pras_hydro_planning_kwarg" begin
        model_true = HSPI.GeneratorPRAS(; hydro_planning=true)
        @test isa(model_true, SPI.GeneratorPRAS)

        model_false = HSPI.GeneratorPRAS(; hydro_planning=false)
        @test isa(model_false, SPI.GeneratorPRAS)
    end

    @testset "generator_pras_keyword_forwarding" begin
        model_kw_true = HSPI.GeneratorPRAS(; hydro_planning=true, max_active_power="max_active_POWER")
        @test isa(model_kw_true, SPI.GeneratorPRAS)

        model_kw_false = HSPI.GeneratorPRAS(; hydro_planning=false, max_active_power="max_active_POWER")
        @test isa(model_kw_false, SPI.GeneratorPRAS)
    end

    @testset "hydro_energy_reservoir_hydro_planning_kwarg" begin
        model_true = HSPI.HydroEnergyReservoirPRAS(; hydro_planning=true)
        @test isa(model_true, SPI.HydroEnergyReservoirPRAS)

        model_false = HSPI.HydroEnergyReservoirPRAS(; hydro_planning=false)
        @test isa(model_false, SPI.HydroEnergyReservoirPRAS)
    end

    @testset "hydro_energy_reservoir_original_still_works" begin
        model = SPI.HydroEnergyReservoirPRAS()
        @test isa(model, SPI.HydroEnergyReservoirPRAS)
    end

    @testset "hydro_energy_reservoir_keyword_forwarding" begin
        model_kw_true = HSPI.HydroEnergyReservoirPRAS(; hydro_planning=true, max_active_power="max_active_POWER")
        @test isa(model_kw_true, SPI.HydroEnergyReservoirPRAS)

        model_kw_false = HSPI.HydroEnergyReservoirPRAS(; hydro_planning=false, max_active_power="max_active_POWER")
        @test isa(model_kw_false, SPI.HydroEnergyReservoirPRAS)
    end

    @testset "energy_reservoir_soc_overload_if_available" begin
        if isdefined(SPI, :EnergyReservoirSoC)
            model_true = HSPI.EnergyReservoirSoC(; hydro_planning=true)
            @test isa(model_true, SPI.EnergyReservoirSoC)

            model_false = HSPI.EnergyReservoirSoC(; hydro_planning=false)
            @test isa(model_false, SPI.EnergyReservoirSoC)
        else
            @test true
        end
    end

end
