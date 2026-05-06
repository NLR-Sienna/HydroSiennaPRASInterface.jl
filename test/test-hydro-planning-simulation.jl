import Dates
import HiGHS
import HydroPowerSimulations
import PowerSimulations
import PowerSystemCaseBuilder
import PowerSystems
import SiennaPRASInterface
import Statistics
import Test
import TimeSeries
import DataFrames
using PowerSystems
using Statistics
using TimeSeries
using Revise
using HydroSiennaPRASInterface

const HPS = HydroPowerSimulations
const PSI = PowerSimulations
const PSB = PowerSystemCaseBuilder
const PSY = PowerSystems
const SPI = SiennaPRASInterface
const DataFrame = DataFrames.DataFrame

const SCRIPTS_DIR = joinpath(dirname(@__DIR__), "scripts")
include(joinpath(SCRIPTS_DIR, "hydro_dev_utils.jl"))

function _build_medium_term_system()
    models_dir = joinpath(dirname(@__DIR__), "models")

    weekly_sys = PSY.System(joinpath(models_dir, "sys_weekly.json"))
    sys = deepcopy(weekly_sys)
    PSY.remove_time_series!(sys, PSY.SingleTimeSeries)

    num_weeks = 104
    resolution_weekly = Dates.Week(1)
    resolution_hourly = Dates.Hour(1)
    steps_in_resolution = resolution_weekly ÷ resolution_hourly
    total_steps = num_weeks * steps_in_resolution
    global nums = num_weeks

    set_turbine_cost_to_zero!(sys)
    add_fuel_cost_new_time_series!(weekly_sys, sys, steps_in_resolution, total_steps)
    add_load_new_mean_time_series!(weekly_sys, sys, steps_in_resolution, total_steps; load_type = PSY.StandardLoad)
    add_renewable_new_time_series!(weekly_sys, sys, steps_in_resolution, total_steps; renewable_type = PSY.RenewableDispatch)
    add_renewable_new_time_series!(weekly_sys, sys, steps_in_resolution, total_steps; renewable_type = PSY.RenewableNonDispatch)
    add_inflow_outflow_new_time_series!(weekly_sys, sys, steps_in_resolution, total_steps)
    add_hydro_target_new_time_series!(weekly_sys, sys, steps_in_resolution, total_steps)
    add_reserves_new_time_series!(weekly_sys, sys, steps_in_resolution, total_steps)

    PSY.transform_single_time_series!(sys, Dates.Week(25), Dates.Week(1))
    return sys
end

@Test.testset "Hydro Planning: Extract Inflow Data" begin
    """Test hydro planning functionality: extracting inflow data from UC simulations
    and using it in hydro constructors."""
    sys_uc = _build_medium_term_system()

    # Extract inflow data from UC simulation
    hydro_inflow_data = extract_hydro_inflow_from_simulation(sys_uc)

    # Verify we got data
    @Test.test !isempty(hydro_inflow_data)


end

@Test.testset "Hydro Planning: Constructors with Inflow Data" begin
    sys_uc = _build_medium_term_system()

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
    sys_uc = _build_medium_term_system()

    # Test calling with system parameter to trigger simulation
    hydro_pras = SPI.HydroEnergyReservoirPRAS(true; system=sys_uc)
    @Test.test hydro_pras isa SPI.HydroEnergyReservoirPRAS
end
