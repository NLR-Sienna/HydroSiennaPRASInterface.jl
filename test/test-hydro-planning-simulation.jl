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

    # ── Medium-term (weekly) system ───────────────────────────────────────────
    @info "=== Building medium-term (weekly) system ==="
    weekly_sys    = PSY.System(joinpath(models_dir, "sys_weekly.json"))
    med_term_sys  = deepcopy(weekly_sys)
    PSY.remove_time_series!(med_term_sys, PSY.SingleTimeSeries)

    num_weeks_mt       = 104
    resolution_hourly  = Dates.Hour(1)
    resolution_weekly  = Dates.Week(1)
    steps_mt           = resolution_weekly ÷ resolution_hourly
    total_steps_mt     = num_weeks_mt * steps_mt
    global nums        = num_weeks_mt

    set_turbine_cost_to_zero!(med_term_sys)
    add_fuel_cost_new_time_series!(weekly_sys, med_term_sys, steps_mt, total_steps_mt)
    add_load_new_mean_time_series!(weekly_sys, med_term_sys, steps_mt, total_steps_mt; load_type = PSY.StandardLoad)
    add_renewable_new_time_series!(weekly_sys, med_term_sys, steps_mt, total_steps_mt; renewable_type = PSY.RenewableDispatch)
    add_renewable_new_time_series!(weekly_sys, med_term_sys, steps_mt, total_steps_mt; renewable_type = PSY.RenewableNonDispatch)
    add_inflow_outflow_new_time_series!(weekly_sys, med_term_sys, steps_mt, total_steps_mt)
    add_hydro_target_new_time_series!(weekly_sys, med_term_sys, steps_mt, total_steps_mt)
    add_reserves_new_time_series!(weekly_sys, med_term_sys, steps_mt, total_steps_mt)

    PSY.transform_single_time_series!(med_term_sys, Dates.Week(25), Dates.Week(1))

    for reservoir_name in PSY.get_name.(PSY.get_components(PSY.HydroReservoir, med_term_sys))
        reservoir = PSY.get_component(PSY.HydroReservoir, med_term_sys, reservoir_name)
        PSY.set_operation_cost!(reservoir, PSY.HydroReservoirCost(5e6, 5e6, 1.0))
    end

    template_mt = PSI.ProblemTemplate(PSI.NetworkModel(PSI.CopperPlatePowerModel; use_slacks=true))
    PSI.set_device_model!(template_mt, PSY.ThermalStandard,       PSI.ThermalDispatchNoMin)
    PSI.set_device_model!(template_mt, PSY.RenewableDispatch,      PSI.RenewableFullDispatch)
    PSI.set_device_model!(template_mt, PSY.RenewableNonDispatch,   PSI.FixedOutput)
    PSI.set_device_model!(template_mt, PSY.StandardLoad,           PSI.StaticPowerLoad)
    PSI.set_device_model!(template_mt, PSI.DeviceModel(
        PSY.HydroReservoir,
        HPS.HydroWaterModelReservoir;
        attributes = Dict("hydro_target" => true, "hydro_budget" => false),
    ))
    PSI.set_device_model!(template_mt, PSY.HydroTurbine, HPS.HydroTurbineWaterLinearCommitment)
    PSI.set_service_model!(template_mt, PSI.ServiceModel(PSY.VariableReserve{PSY.ReserveUp}, PSI.RangeReserve; use_slacks=true))

    PSY.set_available!(PSY.get_component(PSY.RenewableDispatch, med_term_sys, "Bomba135"), false)

    model_mt = PSI.DecisionModel(
        template_mt,
        med_term_sys;
        name                      = "UC_MedTerm",
        optimizer                 = HiGHS.Optimizer,
        store_variable_names      = true,
        optimizer_solve_log_print = true,
        initialize_model          = true,
        calculate_conflict        = true,
    )
    models_mt = PSI.SimulationModels(; decision_models=[model_mt])
    sim_mt = PSI.Simulation(
        name              = "med_term",
        steps             = 52,
        models            = models_mt,
        initial_time      = Dates.DateTime("2023-01-01T00:00:00"),
        sequence          = PSI.SimulationSequence(;
            models              = models_mt,
            ini_cond_chronology = PSI.InterProblemChronology(),
        ),
        simulation_folder = mktempdir(),
    )
    PSI.build!(sim_mt)
    PSI.execute!(sim_mt)

    results_mt   = PSI.SimulationResults(sim_mt)
    results_uc_mt = PSI.get_decision_problem_results(results_mt, "UC_MedTerm")
    all_variable_results_mt  = PSI.read_realized_variables(results_uc_mt)
    all_parameter_results_mt = PSI.read_realized_parameters(results_uc_mt)

    med_term_parameter = all_parameter_results_mt["WaterTargetTimeSeriesParameter__HydroReservoir"]

    # ── Short-term (hourly) system ────────────────────────────────────────────
    @info "=== Building short-term (hourly) system ==="
    short_term_sys = deepcopy(weekly_sys)
    PSY.remove_time_series!(short_term_sys, PSY.SingleTimeSeries)

    num_hours_st   = 365 * 24
    steps_st       = Dates.Hour(1) ÷ resolution_hourly   # = 1
    total_steps_st = num_hours_st * steps_st
    global nums    = num_hours_st

    set_turbine_cost_to_zero!(short_term_sys)
    add_fuel_cost_new_time_series!(weekly_sys, short_term_sys, steps_st, total_steps_st)
    add_load_new_mean_time_series!(weekly_sys, short_term_sys, steps_st, total_steps_st; load_type = PSY.StandardLoad)
    add_renewable_new_time_series!(weekly_sys, short_term_sys, steps_st, total_steps_st; renewable_type = PSY.RenewableDispatch)
    add_renewable_new_time_series!(weekly_sys, short_term_sys, steps_st, total_steps_st; renewable_type = PSY.RenewableNonDispatch)
    add_inflow_outflow_new_time_series!(weekly_sys, short_term_sys, steps_st, total_steps_st)
    add_reserves_new_time_series!(weekly_sys, short_term_sys, steps_st, total_steps_st)

    convert_hydro_targets_med_to_short(med_term_sys, short_term_sys, steps_st, total_steps_st, med_term_parameter, "hydro_target")

    PSY.transform_single_time_series!(short_term_sys, Dates.Hour(25), Dates.Hour(1))

    for reservoir_name in PSY.get_name.(PSY.get_components(PSY.HydroReservoir, short_term_sys))
        reservoir = PSY.get_component(PSY.HydroReservoir, short_term_sys, reservoir_name)
        PSY.set_operation_cost!(reservoir, PSY.HydroReservoirCost(5e6, 5e6, 1.0))
    end

    template_st = PSI.ProblemTemplate(PSI.NetworkModel(PSI.CopperPlatePowerModel; use_slacks=true))
    PSI.set_device_model!(template_st, PSY.ThermalStandard,       PSI.ThermalDispatchNoMin)
    PSI.set_device_model!(template_st, PSY.RenewableDispatch,      PSI.RenewableFullDispatch)
    PSI.set_device_model!(template_st, PSY.RenewableNonDispatch,   PSI.FixedOutput)
    PSI.set_device_model!(template_st, PSY.StandardLoad,           PSI.StaticPowerLoad)
    PSI.set_device_model!(template_st, PSI.DeviceModel(
        PSY.HydroReservoir,
        HPS.HydroWaterModelReservoir;
        attributes = Dict("hydro_target" => true, "hydro_budget" => false),
    ))
    PSI.set_device_model!(template_st, PSY.HydroTurbine, HPS.HydroTurbineWaterLinearCommitment)
    PSI.set_service_model!(template_st, PSI.ServiceModel(PSY.VariableReserve{PSY.ReserveUp}, PSI.RangeReserve; use_slacks=true))

    PSY.set_available!(PSY.get_component(PSY.RenewableDispatch, short_term_sys, "Bomba135"), false)

    model_st = PSI.DecisionModel(
        template_st,
        short_term_sys;
        name                      = "UC_ShortTerm",
        optimizer                 = HiGHS.Optimizer,
        store_variable_names      = true,
        optimizer_solve_log_print = true,
        initialize_model          = true,
        calculate_conflict        = true,
    )
    models_st = PSI.SimulationModels(; decision_models=[model_st])
    sim_st = PSI.Simulation(
        name              = "short_term",
        steps             = 24,
        models            = models_st,
        initial_time      = Dates.DateTime("2023-01-01T00:00:00"),
        sequence          = PSI.SimulationSequence(;
            models              = models_st,
            ini_cond_chronology = PSI.InterProblemChronology(),
        ),
        simulation_folder = mktempdir(),
    )
    PSI.build!(sim_st)
    PSI.execute!(sim_st)

    results_st    = PSI.SimulationResults(sim_st)
    results_uc_st = PSI.get_decision_problem_results(results_st, "UC_ShortTerm")
    all_variable_results_st  = PSI.read_realized_variables(results_uc_st)
    all_parameter_results_st = PSI.read_realized_parameters(results_uc_st)

    return (
        med_term_sys   = med_term_sys,
        short_term_sys = short_term_sys,
        weekly_vars    = all_variable_results_mt,
        weekly_params  = all_parameter_results_mt,
        hourly_vars    = all_variable_results_st,
        hourly_params  = all_parameter_results_st,
    )
end

@Test.testset "Hydro Planning: Extract Inflow Data" begin
    """Test hydro planning functionality: extracting inflow data from UC simulations
    and using it in hydro constructors."""
    pipeline = _build_medium_term_system()
    sys_uc = pipeline.short_term_sys

    # Extract inflow data from UC simulation
    hydro_inflow_data = extract_hydro_inflow_from_simulation(sys_uc)

    # Verify we got data
    @Test.test !isempty(hydro_inflow_data)


end

@Test.testset "Hydro Planning: Constructors with Inflow Data" begin
    pipeline = _build_medium_term_system()
    sys_uc = pipeline.short_term_sys

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

@Test.testset "Hydro Planning: Turbine Active Power Matches Inflow Data by Reservoir" begin
    pipeline = _build_medium_term_system()
    sys_uc   = pipeline.short_term_sys

    # Build turbine → reservoir mapping from the system
    turbine_to_reservoir = Dict{String, String}()
    for reservoir in PSY.get_components(PSY.HydroReservoir, sys_uc)
        for turbine in reservoir.upstream_turbines
            turbine_to_reservoir[PSY.get_name(turbine)] = PSY.get_name(reservoir)
        end
    end

    # Fetch the hourly turbine active power DataFrame.
    # PSI returns this in long form: (DateTime, <component_col>, value)
    turbine_df = pipeline.hourly_vars["ActivePowerVariable__HydroTurbine"]

    # Identify columns: first is DateTime, last is value, middle is turbine name
    col_names   = names(turbine_df)
    dt_col      = col_names[1]
    value_col   = col_names[end]
    turbine_col = col_names[2]   # component name column

    long_df = DataFrame(
        :DateTime     => Dates.DateTime.(turbine_df[!, dt_col]),
        :turbine      => String.(turbine_df[!, turbine_col]),
        :active_power => Float64.(turbine_df[!, value_col]),
    )
    long_df.reservoir = [get(turbine_to_reservoir, t, missing) for t in long_df.turbine]
    long_df = DataFrames.dropmissing(long_df, :reservoir)

    grouped_df = DataFrames.sort(
        DataFrames.combine(
            DataFrames.groupby(long_df, [:DateTime, :reservoir]),
            :active_power => sum => :total_active_power,
        ),
        [:reservoir, :DateTime],
    )

    @Test.test !isempty(grouped_df)
    @Test.test "DateTime"           in names(grouped_df)
    @Test.test "reservoir"          in names(grouped_df)
    @Test.test "total_active_power" in names(grouped_df)
    @Test.test length(unique(grouped_df.reservoir)) == length(unique(values(turbine_to_reservoir)))

    # Compare grouped turbine active power against hydro_inflow_data["HydroReservoir"]
    # Both should have the same value per (DateTime, reservoir)
    hydro_inflow_data = extract_hydro_inflow_from_simulation(sys_uc)
    inflow_df = hydro_inflow_data["HydroReservoir"]  # wide: DateTime | Reservoir_A | Reservoir_B ...

    # Melt inflow_df to long form for easy comparison
    inflow_dt_col    = names(inflow_df)[1]
    inflow_res_cols  = names(inflow_df)[2:end]
    inflow_long = DataFrames.stack(inflow_df, inflow_res_cols;
        variable_name = :reservoir, value_name = :inflow_power)
    DataFrames.rename!(inflow_long, inflow_dt_col => :DateTime)
    inflow_long.DateTime = Dates.DateTime.(inflow_long.DateTime)

    # Inner join on (DateTime, reservoir) and compare values
    comparison = DataFrames.innerjoin(grouped_df, inflow_long; on = [:DateTime, :reservoir])

    @Test.test !isempty(comparison)
    for row in eachrow(comparison)
        @Test.test isapprox(row.total_active_power, row.inflow_power; atol=1e-6)
    end
end

@Test.testset "Hydro Planning: Apply Inflow Data to System" begin
    pipeline = _build_medium_term_system()
    sys_uc   = pipeline.short_term_sys

    # Build turbine → reservoir mapping
    turbine_to_reservoir = Dict{String, String}()
    for reservoir in PSY.get_components(PSY.HydroReservoir, sys_uc)
        for turbine in reservoir.upstream_turbines
            turbine_to_reservoir[PSY.get_name(turbine)] = PSY.get_name(reservoir)
        end
    end

    # Build hydro_inflow_data["HydroReservoir"] from pipeline.hourly_vars
    turbine_df  = pipeline.hourly_vars["ActivePowerVariable__HydroTurbine"]
    col_names   = names(turbine_df)
    dt_col      = col_names[1]
    value_col   = col_names[end]
    turbine_col = col_names[2]

    long_df = DataFrame(
        :DateTime     => Dates.DateTime.(turbine_df[!, dt_col]),
        :turbine      => String.(turbine_df[!, turbine_col]),
        :active_power => Float64.(turbine_df[!, value_col]),
    )
    long_df.reservoir = [get(turbine_to_reservoir, t, missing) for t in long_df.turbine]
    long_df = DataFrames.dropmissing(long_df, :reservoir)

    agg_df = DataFrames.combine(
        DataFrames.groupby(long_df, [:DateTime, :reservoir]),
        :active_power => sum => :active_power,
    )
    inflow_wide = DataFrames.sort(
        DataFrames.unstack(agg_df, :DateTime, :reservoir, :active_power; fill=0.0),
        :DateTime,
    )

    hydro_inflow_data = Dict{String, Any}("HydroReservoir" => inflow_wide)

    reservoirs = collect(PSY.get_components(PSY.HydroReservoir, sys_uc))

    apply_hydro_inflow_to_system!(sys_uc, hydro_inflow_data)

    # Extract "inflow" SingleTimeSeries from sys_uc and compare only the replaced timestamps
    inflow_wide = hydro_inflow_data["HydroReservoir"]
    dt_col_name    = names(inflow_wide)[1]
    reservoir_cols = names(inflow_wide)[2:end]
    replaced_timestamps = Set(Dates.DateTime.(inflow_wide[!, dt_col_name]))

    for res_name in reservoir_cols
        reservoir = PSY.get_component(PSY.HydroReservoir, sys_uc, res_name)
        @Test.test !isnothing(reservoir)
        @Test.test PSY.has_time_series(reservoir, PSY.SingleTimeSeries, "inflow")

        ts      = PSY.get_time_series(PSY.SingleTimeSeries, reservoir, "inflow")
        ts_data = PSY.get_data(ts)
        ts_ta   = TimeSeries.TimeArray(ts_data)   # TimeArray with timestamps

        # Build a lookup from timestamp → value for the full series
        ts_map = Dict(zip(TimeSeries.timestamp(ts_ta), TimeSeries.values(ts_ta)))

        # Compare only the rows that apply_hydro_inflow_to_system! touched
        expected_df = inflow_wide[!, [dt_col_name, res_name]]
        for row in eachrow(expected_df)
            t   = Dates.DateTime(row[dt_col_name])
            exp = Float64(row[res_name])
            @Test.test haskey(ts_map, t)
            if haskey(ts_map, t)
                @Test.test isapprox(ts_map[t], exp; atol=1e-6)
            end
        end
    end
end
