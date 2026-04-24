#using Revise
using PowerSimulations
using PowerSystems
using InfrastructureSystems
using HydroPowerSimulations
using HiGHS
using TimeSeries
using Statistics

const PSI = PowerSimulations
const PSY = PowerSystems

cur_dir = (@__DIR__)
model_dir = joinpath(cur_dir, "models")
scripts_dir = joinpath(cur_dir, "scripts")
include(joinpath(scripts_dir, "hydro_dev_utils.jl"))

weekly_sys = PSY.System(joinpath(model_dir, "sys_weekly.json"))

sys = deepcopy(weekly_sys)
remove_time_series!(sys, SingleTimeSeries)

# Time Data Used for Hydro Planning
num_weeks = 104
num_days = 365*2
resolution_weekly = Week(1)
resolution_daily = Day(1)
resolution_hourly = Hour(1)

# Used Numbers
resolution = resolution_weekly
nums = num_weeks
steps_in_resolution = resolution ÷ resolution_hourly
total_steps = nums * steps_in_resolution

set_turbine_cost_to_zero!(sys)
add_fuel_cost_new_time_series!(weekly_sys, sys, steps_in_resolution, total_steps)
add_load_new_mean_time_series!(weekly_sys, sys, steps_in_resolution, total_steps; load_type = StandardLoad)
add_renewable_new_time_series!(weekly_sys, sys, steps_in_resolution, total_steps; renewable_type = RenewableDispatch)
add_renewable_new_time_series!(weekly_sys, sys, steps_in_resolution, total_steps; renewable_type = RenewableNonDispatch)
add_inflow_outflow_new_time_series!(weekly_sys, sys, steps_in_resolution, total_steps)
#add_final_target_new_time_series!(weekly_sys, sys, steps_in_resolution, total_steps)
add_hydro_target_new_time_series!(weekly_sys, sys, steps_in_resolution, total_steps)
add_reserves_new_time_series!(weekly_sys, sys, steps_in_resolution, total_steps)

transform_single_time_series!(sys, Week(25), Week(1)) 

reservoir_names = get_name.(get_components(HydroReservoir, sys))
hydro_reservoir_cost = HydroReservoirCost(5e6, 5e6, 1.0)
for reservoir_name in reservoir_names
    reservoir = get_component(HydroReservoir, sys, reservoir_name)
    set_operation_cost!(reservoir, hydro_reservoir_cost)
end

template_uc = ProblemTemplate(NetworkModel(CopperPlatePowerModel; use_slacks = true))
set_device_model!(template_uc, ThermalStandard, ThermalDispatchNoMin)
set_device_model!(template_uc, RenewableDispatch, RenewableFullDispatch)
set_device_model!(template_uc, RenewableNonDispatch, FixedOutput)
set_device_model!(template_uc, StandardLoad, StaticPowerLoad)

reservoir_model = DeviceModel(
        HydroReservoir,
        HydroWaterModelReservoir;
        attributes = Dict("hydro_target" => true, "hydro_budget" => false),
    )
set_device_model!(template_uc, reservoir_model)
set_device_model!(template_uc, HydroTurbine, HydroTurbineWaterLinearCommitment)
       
set_service_model!(
    template_uc,
    ServiceModel(VariableReserve{ReserveUp}, RangeReserve, use_slacks = true) 
)

bomba = get_component(RenewableDispatch, sys, "Bomba135")
set_available!(bomba, false)

model = DecisionModel(
        template_uc,
        sys;
        name = "UC",
        optimizer = HiGHS.Optimizer,
        store_variable_names = true,
        optimizer_solve_log_print = true,
        initialize_model = true,
        calculate_conflict = true,
)

models = SimulationModels(
        decision_models = [model],
    )

DA_sequence = SimulationSequence(
        models = models,
        ini_cond_chronology = InterProblemChronology(),
    )

sim_steps = 52
sim = Simulation(
    name = "test",
    steps = sim_steps,
    models = models,
    initial_time = DateTime("2023-01-01T00:00:00"),
    sequence = DA_sequence,
    simulation_folder = mktempdir(),
)

build!(sim)
execute!(sim)

results = SimulationResults(sim)
results_uc = get_decision_problem_results(results, "UC")

all_variable_results = read_realized_variables(results_uc)
all_parameter_results = read_realized_parameters(results_uc)
