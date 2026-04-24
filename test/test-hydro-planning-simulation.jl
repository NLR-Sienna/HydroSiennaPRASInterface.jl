import Dates
import HiGHS
import HydroPowerSimulations
import PowerSimulations
import PowerSystemCaseBuilder
import PowerSystems
import SiennaPRASInterface
import Test

using HydroSiennaPRASInterface

const HPS = HydroPowerSimulations
const PSI = PowerSimulations
const PSB = PowerSystemCaseBuilder
const PSY = PowerSystems
const SPI = SiennaPRASInterface

@Test.testset "Hydro Planning: Extract Inflow Data" begin
    """Test hydro planning functionality: extracting inflow data from UC simulations
    and using it in hydro constructors."""
    sys_uc = PSB.build_system(PSB.PSISystems, "5_bus_hydro_uc_sys")

    # Extract inflow data from UC simulation
    hydro_inflow_data = extract_hydro_inflow_from_simulation(sys_uc)

    # Verify we got data
    @Test.test !isempty(hydro_inflow_data)

    # Check that we have HydroDispatch and/or HydroEnergyReservoir data
    has_dispatch = haskey(hydro_inflow_data, "HydroDispatch")
    has_reservoir = haskey(hydro_inflow_data, "HydroEnergyReservoir")
    @Test.test has_dispatch || has_reservoir

    # Verify each dataset is a matrix with expected structure
    for (key, data) in hydro_inflow_data
        @Test.test data isa Matrix{Float64}
        # Should have at least one column (components)
        @Test.test size(data, 2) >= 1
        # Should have rows for each time period
        @Test.test size(data, 1) >= 1
        @info "Extracted $key: $(size(data)) matrix"
    end
end

@Test.testset "Hydro Planning: Constructors with Inflow Data" begin
    sys_uc = PSB.build_system(PSB.PSISystems, "5_bus_hydro_uc_sys")

    # Extract inflow data
    hydro_inflow_data = extract_hydro_inflow_from_simulation(sys_uc)

    # Test GeneratorPRAS with hydro_planning=true and inflow_data
    gen_pras = SPI.GeneratorPRAS(true; hydro_inflow_data=hydro_inflow_data)
    @Test.test gen_pras isa SPI.GeneratorPRAS

    # Test HydroEnergyReservoirPRAS with hydro_planning=true and inflow_data
    hydro_pras = SPI.HydroEnergyReservoirPRAS(true; hydro_inflow_data=hydro_inflow_data)
    @Test.test hydro_pras isa SPI.HydroEnergyReservoirPRAS

    # Test with hydro_planning=false
    gen_pras_no_planning = SPI.GeneratorPRAS(false)
    @Test.test gen_pras_no_planning isa SPI.GeneratorPRAS

    hydro_pras_no_planning = SPI.HydroEnergyReservoirPRAS(false)
    @Test.test hydro_pras_no_planning isa SPI.HydroEnergyReservoirPRAS
end

@Test.testset "Hydro Planning: Constructor with System Parameter" begin
    sys_uc = PSB.build_system(PSB.PSISystems, "5_bus_hydro_uc_sys")

    # Test calling with system parameter to trigger simulation
    hydro_pras = SPI.HydroEnergyReservoirPRAS(true; system=sys_uc)
    @Test.test hydro_pras isa SPI.HydroEnergyReservoirPRAS
end
