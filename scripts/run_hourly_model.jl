#using Revise
using PowerSimulations
using PowerSystems
using InfrastructureSystems
using HydroPowerSimulations
using HiGHS
using TimeSeries
using Statistics
using CSV
using DataFrames

const PSI = PowerSimulations
const PSY = PowerSystems

cur_dir = (@__DIR__)
model_dir = joinpath(cur_dir, "models")
scripts_dir = joinpath(cur_dir, "scripts")
results_dir = joinpath(cur_dir, "results")
include(joinpath(scripts_dir, "hydro_dev_utils.jl"))

med_term_resolution_name = "weekly"
med_term_model_type = "target"
med_term_sys = PSY.System(joinpath(model_dir, "sys_$(med_term_resolution_name).json"))
med_term_results_dir = joinpath(results_dir, med_term_resolution_name)
if isdir(med_term_results_dir)
    @info "Med-term resutls found"
else
    @warn "Med-term results not found"
end

short_term_resolution_name = "hourly"
short_term_model_type = "target"

short_term_sys = deepcopy(med_term_sys)
remove_time_series!(short_term_sys, SingleTimeSeries)

# Time Data Used for Hydro Planning
num_weeks = 52
num_days = 365*1
num_hours = num_days * 24
resolution_weekly = Week(1)
resolution_daily = Day(1)
resolution_hourly = Hour(1)

# Used Numbers
resolution = resolution_hourly
nums = num_hours
steps_in_resolution = resolution ÷ resolution_hourly
total_steps = nums * steps_in_resolution

# Setting up the hourly system - weekly parameters
set_turbine_cost_to_zero!(short_term_sys)
add_fuel_cost_new_time_series!(med_term_sys, short_term_sys, steps_in_resolution, total_steps)
add_load_new_mean_time_series!(med_term_sys, short_term_sys, steps_in_resolution, total_steps; load_type = StandardLoad)
add_renewable_new_time_series!(med_term_sys, short_term_sys, steps_in_resolution, total_steps; renewable_type = RenewableDispatch)
add_renewable_new_time_series!(med_term_sys, short_term_sys, steps_in_resolution, total_steps; renewable_type = RenewableNonDispatch)

med_term_res_head = CSV.read(joinpath(med_term_results_dir, "HydroReservoirHeadVariable_HydroReservoir.csv"), DataFrame)
med_term_res_volume = CSV.read(joinpath(med_term_results_dir, "HydroReservoirVolumeVariable_HydroReservoir.csv"), DataFrame)

med_term_parameter = CSV.read(joinpath(med_term_results_dir,
                     "Water$(uppercasefirst(med_term_model_type))TimeSeriesParameter_HydroReservoir.csv"), DataFrame)

# # Weekly targets/budgets
add_inflow_outflow_new_time_series!(med_term_sys, short_term_sys, steps_in_resolution, total_steps)
add_reserves_new_time_series!(med_term_sys, short_term_sys, steps_in_resolution, total_steps)

convert_hydro_targets_med_to_short(med_term_sys, short_term_sys, steps_in_resolution, total_steps, med_term_parameter, med_term_model_type)

# add_final_target_new_time_series!(med_term_sys, sys, steps_in_resolution, total_steps)
# add_hydro_target_new_time_series!(med_term_sys, sys, steps_in_resolution, total_steps)

transform_single_time_series!(short_term_sys, Hour(25), Hour(1)) 

reservoir_names = get_name.(get_components(HydroReservoir, short_term_sys))
hydro_reservoir_cost = HydroReservoirCost(5e6, 5e6, 1.0)
for reservoir_name in reservoir_names
    reservoir = get_component(HydroReservoir, short_term_sys, reservoir_name)
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

bomba = get_component(RenewableDispatch, short_term_sys, "Bomba135")
set_available!(bomba, false)

model = DecisionModel(
        template_uc,
        short_term_sys;
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

sim_steps = 8736
sim = Simulation(
    name = "short_term",
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


save_results_to_csv(all_variable_results, results_dir, "hourly")
save_results_to_csv(all_parameter_results, results_dir, "hourly")

hydro_reservoir_volume = all_variable_results["HydroReservoirVolumeVariable__HydroReservoir"]
hydro_reservoir_head = all_variable_results["HydroReservoirHeadVariable__HydroReservoir"]