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
include(joinpath(scripts_dir, "hydro_dev_utils.jl"))

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────
med_term_model_type   = "target"   # "target" or "budget"
save_med_term_results = true       # set false to skip CSV output for med-term

# ─────────────────────────────────────────────────────────────────────────────
# MEDIUM-TERM MODEL (weekly)
# ─────────────────────────────────────────────────────────────────────────────
@info "=== Building medium-term (weekly) system ==="

weekly_sys = PSY.System(joinpath(model_dir, "sys_weekly.json"))
med_term_sys = deepcopy(weekly_sys)
remove_time_series!(med_term_sys, SingleTimeSeries)

num_weeks_mt      = 104
resolution_hourly = Hour(1)
resolution_weekly = Week(1)
steps_mt          = resolution_weekly ÷ resolution_hourly
total_steps_mt    = num_weeks_mt * steps_mt

set_turbine_cost_to_zero!(med_term_sys)
add_fuel_cost_new_time_series!(weekly_sys, med_term_sys, steps_mt, total_steps_mt)
add_load_new_mean_time_series!(weekly_sys, med_term_sys, steps_mt, total_steps_mt; load_type = StandardLoad)
add_renewable_new_time_series!(weekly_sys, med_term_sys, steps_mt, total_steps_mt; renewable_type = RenewableDispatch)
add_renewable_new_time_series!(weekly_sys, med_term_sys, steps_mt, total_steps_mt; renewable_type = RenewableNonDispatch)
add_inflow_outflow_new_time_series!(weekly_sys, med_term_sys, steps_mt, total_steps_mt)
add_hydro_target_new_time_series!(weekly_sys, med_term_sys, steps_mt, total_steps_mt)
add_reserves_new_time_series!(weekly_sys, med_term_sys, steps_mt, total_steps_mt)

transform_single_time_series!(med_term_sys, Week(25), Week(1))

for reservoir_name in get_name.(get_components(HydroReservoir, med_term_sys))
    reservoir = get_component(HydroReservoir, med_term_sys, reservoir_name)
    set_operation_cost!(reservoir, HydroReservoirCost(5e6, 5e6, 1.0))
end

template_mt = ProblemTemplate(NetworkModel(CopperPlatePowerModel; use_slacks = true))
set_device_model!(template_mt, ThermalStandard, ThermalDispatchNoMin)
set_device_model!(template_mt, RenewableDispatch, RenewableFullDispatch)
set_device_model!(template_mt, RenewableNonDispatch, FixedOutput)
set_device_model!(template_mt, StandardLoad, StaticPowerLoad)
set_device_model!(template_mt, DeviceModel(
    HydroReservoir,
    HydroWaterModelReservoir;
    attributes = Dict("hydro_target" => true, "hydro_budget" => false),
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

sim_mt = Simulation(
    name              = "med_term",
    steps             = 52,
    models            = SimulationModels(; decision_models = [model_mt]),
    initial_time      = DateTime("2023-01-01T00:00:00"),
    sequence          = SimulationSequence(;
        models                 = SimulationModels(; decision_models = [model_mt]),
        ini_cond_chronology    = InterProblemChronology(),
    ),
    simulation_folder = mktempdir(),
)

build!(sim_mt)
execute!(sim_mt)

results_mt    = SimulationResults(sim_mt)
results_uc_mt = get_decision_problem_results(results_mt, "UC_MedTerm")

all_variable_results_mt   = read_realized_variables(results_uc_mt)
all_parameter_results_mt  = read_realized_parameters(results_uc_mt)

if save_med_term_results
    save_results_to_csv(all_variable_results_mt,  results_dir, "weekly")
    save_results_to_csv(all_parameter_results_mt, results_dir, "weekly")
end

# Extract the DataFrames we need directly from memory
med_term_res_volume = all_variable_results_mt["HydroReservoirVolumeVariable__HydroReservoir"]
med_term_res_head   = all_variable_results_mt["HydroReservoirHeadVariable__HydroReservoir"]

if med_term_model_type == "target"
    med_term_parameter = all_parameter_results_mt["WaterTargetTimeSeriesParameter__HydroReservoir"]
elseif med_term_model_type == "budget"
    med_term_parameter = all_parameter_results_mt["WaterBudgetTimeSeriesParameter__HydroReservoir"]
else
    error("Invalid med_term_model_type: $med_term_model_type")
end

# ─────────────────────────────────────────────────────────────────────────────
# SHORT-TERM MODEL (hourly)
# ─────────────────────────────────────────────────────────────────────────────
@info "=== Building short-term (hourly) system ==="

short_term_sys = deepcopy(weekly_sys)
remove_time_series!(short_term_sys, SingleTimeSeries)

num_hours_st  = 365 * 24
steps_st      = Hour(1) ÷ resolution_hourly   # = 1
total_steps_st = num_hours_st * steps_st

set_turbine_cost_to_zero!(short_term_sys)
add_fuel_cost_new_time_series!(weekly_sys, short_term_sys, steps_st, total_steps_st)
add_load_new_mean_time_series!(weekly_sys, short_term_sys, steps_st, total_steps_st; load_type = StandardLoad)
add_renewable_new_time_series!(weekly_sys, short_term_sys, steps_st, total_steps_st; renewable_type = RenewableDispatch)
add_renewable_new_time_series!(weekly_sys, short_term_sys, steps_st, total_steps_st; renewable_type = RenewableNonDispatch)
add_inflow_outflow_new_time_series!(med_term_sys, short_term_sys, steps_st, total_steps_st)
add_reserves_new_time_series!(med_term_sys, short_term_sys, steps_st, total_steps_st)

convert_hydro_targets_med_to_short(med_term_sys, short_term_sys, steps_st, total_steps_st, med_term_parameter, "hydro_target")

transform_single_time_series!(short_term_sys, Hour(25), Hour(1))

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
    HydroWaterModelReservoir;
    attributes = Dict("hydro_target" => true, "hydro_budget" => false),
))
set_device_model!(template_st, HydroTurbine, HydroTurbineWaterLinearCommitment)
set_service_model!(template_st, ServiceModel(VariableReserve{ReserveUp}, RangeReserve; use_slacks = true))

set_available!(get_component(RenewableDispatch, short_term_sys, "Bomba135"), false)

model_st = DecisionModel(
    template_st,
    short_term_sys;
    name                       = "UC_ShortTerm",
    optimizer                  = HiGHS.Optimizer,
    store_variable_names       = true,
    optimizer_solve_log_print  = true,
    initialize_model           = true,
    calculate_conflict         = true,
)

sim_st = Simulation(
    name              = "short_term",
    steps             = 8736,
    models            = SimulationModels(; decision_models = [model_st]),
    initial_time      = DateTime("2023-01-01T00:00:00"),
    sequence          = SimulationSequence(;
        models                 = SimulationModels(; decision_models = [model_st]),
        ini_cond_chronology    = InterProblemChronology(),
    ),
    simulation_folder = mktempdir(),
)

build!(sim_st)
execute!(sim_st)

results_st    = SimulationResults(sim_st)
results_uc_st = get_decision_problem_results(results_st, "UC_ShortTerm")

all_variable_results_st  = read_realized_variables(results_uc_st)
all_parameter_results_st = read_realized_parameters(results_uc_st)

save_results_to_csv(all_variable_results_st,  results_dir, "hourly")
save_results_to_csv(all_parameter_results_st, results_dir, "hourly")

hydro_reservoir_volume = all_variable_results_st["HydroReservoirVolumeVariable__HydroReservoir"]
hydro_reservoir_head   = all_variable_results_st["HydroReservoirHeadVariable__HydroReservoir"]
