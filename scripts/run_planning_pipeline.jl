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

scripts_dir = isfile(joinpath(@__DIR__, "hydro_dev_utils.jl")) ? (@__DIR__) : joinpath(@__DIR__, "scripts")
cur_dir = dirname(scripts_dir)
model_dir = joinpath(cur_dir, "models")
results_dir = joinpath(cur_dir, "results")
data_dir = joinpath(cur_dir, "data")
include(joinpath(scripts_dir, "hydro_dev_utils.jl"))

const hydro_models_dict = Dict(
    "Energy" => HydroEnergyModelReservoir,
    "Water"  => HydroWaterModelReservoir,
)

# Models Configuration
med_term_model_type = "budget" # "target" or "budget"
hourly_model_type = "budget"   # "target" or "budget" 

save_med_term_results = true # set false to skip CSV output for med-term
hydro_model_type = "Water" # Energy or Water

output_folder = "$(hydro_model_type)_daily_$(med_term_model_type)_hourly_$(hourly_model_type)"

# MEDIUM-TERM MODEL (weekly)
@info "=== Building medium-term (weekly) system ==="

weekly_sys = PSY.System(joinpath(model_dir, "sys_weekly.json"))
med_term_sys = deepcopy(weekly_sys)
remove_time_series!(med_term_sys, SingleTimeSeries)

num_days_mt      = 365*2
resolution_hourly = Hour(1)
# resolution_weekly = Week(1)
resolution_daily  = Day(1)
steps_mt          = resolution_daily ÷ resolution_hourly
total_steps_mt    = num_days_mt * steps_mt
nums              = num_days_mt   # global used by hydro_dev_utils functions

set_turbine_cost_to_zero!(med_term_sys)
add_fuel_cost_new_time_series!(weekly_sys, med_term_sys, steps_mt, total_steps_mt)
add_load_new_mean_time_series!(weekly_sys, med_term_sys, steps_mt, total_steps_mt; load_type = StandardLoad)
add_renewable_new_time_series!(weekly_sys, med_term_sys, steps_mt, total_steps_mt; renewable_type = RenewableDispatch)
add_renewable_new_time_series!(weekly_sys, med_term_sys, steps_mt, total_steps_mt; renewable_type = RenewableNonDispatch)
add_inflow_outflow_new_time_series!(weekly_sys, med_term_sys, steps_mt, total_steps_mt)

if med_term_model_type == "target"
    add_hydro_target_new_time_series!(weekly_sys, med_term_sys, steps_mt, total_steps_mt)
    med_term_target_attribute = true
    med_term_budget_attribute = false
elseif med_term_model_type == "budget"
    budget_timeseries_df = CSV.read(joinpath(data_dir, "daily_budget.csv"), DataFrame)
    add_hydro_budget_new_time_series!(weekly_sys, med_term_sys, steps_mt, total_steps_mt, budget_timeseries_df)
    med_term_target_attribute = false
    med_term_budget_attribute = true
else
    error("Invalid med_term_model_type: $med_term_model_type")
end

add_reserves_new_time_series!(weekly_sys, med_term_sys, steps_mt, total_steps_mt)

# horizon = full year (1 solve covers all 365 days).
# interval must be the step-between-solves that PSI uses to compute coverage;
# Day(1) is the smallest valid interval for daily data.  With steps=1 only the
# first (and only) window is solved, so the choice of interval doesn't affect
# the result.
transform_single_time_series!(med_term_sys, Day(365), Day(365))

for reservoir_name in get_name.(get_components(HydroReservoir, med_term_sys))
    reservoir = get_component(HydroReservoir, med_term_sys, reservoir_name)
    set_operation_cost!(reservoir, HydroReservoirCost(5e6, 1e3, 1e3))
end

template_mt = ProblemTemplate(NetworkModel(CopperPlatePowerModel; use_slacks = true))
set_device_model!(template_mt, ThermalStandard, ThermalDispatchNoMin)
set_device_model!(template_mt, RenewableDispatch, RenewableFullDispatch)
set_device_model!(template_mt, RenewableNonDispatch, FixedOutput)
set_device_model!(template_mt, StandardLoad, StaticPowerLoad)
set_device_model!(template_mt, DeviceModel(
    HydroReservoir,
    hydro_models_dict[hydro_model_type];
    attributes = Dict("hydro_target" => med_term_target_attribute, "hydro_budget" => med_term_budget_attribute),
))
set_device_model!(template_mt, HydroTurbine, HydroTurbineWaterLinearCommitment)
set_service_model!(template_mt, ServiceModel(VariableReserve{ReserveUp}, RangeReserve; use_slacks = true))

set_available!(get_component(RenewableDispatch, med_term_sys, "Bomba135"), false)

model_mt = DecisionModel(
    template_mt,
    med_term_sys;
    name                       = "UC_MedTerm",
    optimizer                  = HiGHS.Optimizer,
    store_variable_names       = true,
    optimizer_solve_log_print  = true,
    initialize_model           = true,
    calculate_conflict         = true,
)

models_mt = SimulationModels(; decision_models = [model_mt])

sim_mt = Simulation(
    name              = "med_term",
    steps             = 1,
    models            = models_mt,
    initial_time      = DateTime("2023-01-01T00:00:00"),
    sequence          = SimulationSequence(;
        models                 = models_mt,
        ini_cond_chronology    = InterProblemChronology(),
    ),
    simulation_folder = mktempdir(),
)

build!(sim_mt)
execute!(sim_mt)

results_mt = SimulationResults(sim_mt)
results_uc_mt = get_decision_problem_results(results_mt, "UC_MedTerm")

all_variable_results_mt = read_realized_variables(results_uc_mt)
all_parameter_results_mt = read_realized_parameters(results_uc_mt)

if save_med_term_results
    save_results_to_csv(all_variable_results_mt, joinpath(results_dir, output_folder, "daily"))
    save_results_to_csv(all_parameter_results_mt, joinpath(results_dir, output_folder, "daily"))
end

# Extract the DataFrames we need directly from memory
if hydro_model_type == "Energy"
    med_term_reservoir_energy = all_variable_results_mt["EnergyVariable__HydroReservoir"]
elseif hydro_model_type == "Water"
    med_term_reservoir_volume = all_variable_results_mt["HydroReservoirVolumeVariable__HydroReservoir"]
    med_term_daily_head = all_variable_results_mt["HydroReservoirHeadVariable__HydroReservoir"]
end

if med_term_model_type == "target"
    med_term_parameter = all_parameter_results_mt["$(hydro_model_type)TargetTimeSeriesParameter__HydroReservoir"]
elseif med_term_model_type == "budget"
    med_term_parameter = all_parameter_results_mt["$(hydro_model_type)BudgetTimeSeriesParameter__HydroReservoir"]
    # For hierarchical budget mode: pass the OPTIMIZED reservoir volume trajectory from med-term
    # This allows short-term to respect the daily volume profile computed by med-term optimization
    med_term_optimized_volume = med_term_reservoir_volume
else
    error("Invalid med_term_model_type: $med_term_model_type")
end

#------------------------------------------------------------------------
# SHORT-TERM MODEL (hourly)
@info "=== Building short-term (hourly) system ==="

short_term_sys = deepcopy(weekly_sys)
remove_time_series!(short_term_sys, SingleTimeSeries)

num_hours_st = 365 * 24
steps_st = Hour(1) ÷ resolution_hourly   # = 1
total_steps_st = num_hours_st * steps_st
nums = num_hours_st   # global used by hydro_dev_utils functions

set_turbine_cost_to_zero!(short_term_sys)
add_fuel_cost_new_time_series!(weekly_sys, short_term_sys, steps_st, total_steps_st)
add_load_new_mean_time_series!(weekly_sys, short_term_sys, steps_st, total_steps_st; load_type = StandardLoad)
add_renewable_new_time_series!(weekly_sys, short_term_sys, steps_st, total_steps_st; renewable_type = RenewableDispatch)
add_renewable_new_time_series!(weekly_sys, short_term_sys, steps_st, total_steps_st; renewable_type = RenewableNonDispatch)
add_inflow_outflow_new_time_series!(weekly_sys, short_term_sys, steps_st, total_steps_st)
add_reserves_new_time_series!(weekly_sys, short_term_sys, steps_st, total_steps_st)

if hourly_model_type == "target"
    convert_hydro_targets_med_to_short(med_term_sys, short_term_sys, steps_st, total_steps_st, med_term_daily_head, "hydro_target")
    hourly_target_attribute = true
    hourly_budget_attribute = false
elseif hourly_model_type == "budget"
    # HIERARCHICAL: Pass optimized volume trajectory from med-term (not just static input budget)
    convert_hydro_budgets_med_to_short(med_term_sys, short_term_sys, steps_st, total_steps_st, med_term_optimized_volume, "hydro_budget")
    hourly_target_attribute = false
    hourly_budget_attribute = true
else
    error("Invalid hourly_model_type: $hourly_model_type")
end 

# Transform must happen after ALL SingleTimeSeries are added
# Use a horizon of exactly 1 week (168 h) with a 1-week step so that t_end in
# each solve is the last realized hour of the week.  The WaterTargetConstraint
# fires at time_steps[end], which is then the actual end-of-week output.
transform_single_time_series!(short_term_sys, Hour(24), Hour(24))

for reservoir_name in get_name.(get_components(HydroReservoir, short_term_sys))
    reservoir = get_component(HydroReservoir, short_term_sys, reservoir_name)
    set_operation_cost!(reservoir, HydroReservoirCost(5e6, 5e6, 1.0))
end

template_st = ProblemTemplate(NetworkModel(CopperPlatePowerModel; use_slacks = true))
set_device_model!(template_st, ThermalStandard, ThermalDispatchNoMin)
set_device_model!(template_st, RenewableDispatch, RenewableFullDispatch)
set_device_model!(template_st, RenewableNonDispatch, FixedOutput)
set_device_model!(template_st, StandardLoad, StaticPowerLoad)
set_device_model!(template_st, DeviceModel(
    HydroReservoir,
    hydro_models_dict[hydro_model_type];
    attributes = Dict("hydro_target" => hourly_target_attribute, "hydro_budget" => hourly_budget_attribute),
))
set_device_model!(template_st, HydroTurbine, HydroTurbineWaterLinearCommitment)
set_service_model!(template_st, ServiceModel(VariableReserve{ReserveUp}, RangeReserve; use_slacks = true))

set_available!(get_component(RenewableDispatch, short_term_sys, "Bomba135"), false)

model_st = DecisionModel(
    template_st,
    short_term_sys;
    name = "UC_ShortTerm",
    optimizer = HiGHS.Optimizer,
    store_variable_names = true,
    optimizer_solve_log_print  = true,
    initialize_model = true,
    calculate_conflict = true,
)

models_st = SimulationModels(; decision_models = [model_st])

sim_st = Simulation(
    name              = "short_term",
    steps             = 365,  # 364 daily solves
    models            = models_st,
    initial_time      = DateTime("2023-01-01T00:00:00"),
    sequence          = SimulationSequence(;
        models                 = models_st,
        ini_cond_chronology    = InterProblemChronology(),
    ),
    simulation_folder = mktempdir(),
)

build!(sim_st)
execute!(sim_st)

results_st = SimulationResults(sim_st)
results_uc_st = get_decision_problem_results(results_st, "UC_ShortTerm")

all_variable_results_st = read_realized_variables(results_uc_st)
all_parameter_results_st = read_realized_parameters(results_uc_st)

save_results_to_csv(all_variable_results_st, joinpath(results_dir, output_folder, "hourly"))
save_results_to_csv(all_parameter_results_st, joinpath(results_dir, output_folder, "hourly"))