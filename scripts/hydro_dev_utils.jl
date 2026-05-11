# Utility functions for resampling time series from a high-resolution system (`sys`) into a
# lower-resolution system (`sys_other`). Each function iterates over the relevant components,
# slices `total_steps` worth of data from the source series, and aggregates every
# `steps_in_resolution` fine-grained steps into a single coarser step (using mean or sum as
# appropriate) before attaching the new SingleTimeSeries to the target system.

"""
Resamples the `fuel_cost` time series for all available `ThermalStandard` generators from
`sys` into `sys_other` by averaging over each coarser time step.
"""
# function add_fuel_cost_new_time_series!(sys, sys_other, steps_in_resolution, total_steps)
#     for gen in get_components(get_available, ThermalStandard, sys)
#         gen_other = get_component(ThermalStandard, sys_other, gen.name)
#         if has_time_series(gen)
#             ts_array = get_time_series_array(SingleTimeSeries, gen, "fuel_cost"; ignore_scaling_factors = true)
#             raw_vals   = values(ts_array)
#             raw_tstamps = timestamp(ts_array)
#             n_raw      = length(raw_vals)

#             # Tile values to cover two years
#             vals = repeat(raw_vals, ceil(Int, total_steps / n_raw))[1:total_steps]

#             start_time = raw_tstamps[1]
#             tstamps = [start_time + Hour(i) for i in 0:(total_steps - 1)]  # fresh 2-year hourly range
#             #vals = values(ts_array)[1:total_steps]
#             # Average the fine-resolution values within each coarse step
#             vals_other = [mean(vals[1 + (i-1)*steps_in_resolution : i*steps_in_resolution]) for i in 1:nums]
#             new_array = TimeArray(tstamp_other, vals_other)
#             ts_new = SingleTimeSeries(name = "fuel_cost", data = new_array)
#             set_fuel_cost!(sys_other, gen_other, ts_new)
#         end
#     end
# end
function add_fuel_cost_new_time_series!(sys, sys_other, steps_in_resolution, total_steps)
    for gen in get_components(get_available, ThermalStandard, sys)
        gen_other = get_component(ThermalStandard, sys_other, gen.name)

        if has_time_series(gen)
            ts_array = get_time_series_array(SingleTimeSeries, gen, "fuel_cost"; ignore_scaling_factors = true)

            raw_vals   = values(ts_array)

            raw_tstamps = timestamp(ts_array)
            n_raw      = length(raw_vals)

            # Tile values to cover two years
            vals = repeat(raw_vals, ceil(Int, total_steps / n_raw))[1:total_steps]

            # Build two-year hourly timestamps from the original start
            start_time = raw_tstamps[1]
            tstamps    = [start_time + Hour(i) for i in 0:(total_steps - 1)]

            # Subsample to daily resolution and average within each day
            tstamp_other = tstamps[1:steps_in_resolution:total_steps]
            vals_other   = [mean(vals[1 + (i-1)*steps_in_resolution : i*steps_in_resolution]) for i in 1:nums]

            new_array = TimeArray(tstamp_other, vals_other)
            ts_new    = SingleTimeSeries(name = "fuel_cost", data = new_array)
            set_fuel_cost!(sys_other, gen_other, ts_new)
        end
    end
end

# """
# Resamples the `max_active_power` time series for all loads of `load_type` from `sys` into
# `sys_other` by averaging over each coarser time step.
# """
# function add_load_new_mean_time_series!(sys, sys_other, steps_in_resolution, total_steps; load_type = StandardLoad)
#     for load in get_components(load_type, sys)
#         load_other = get_component(load_type, sys_other, load.name)
#         ts_array = get_time_series_array(SingleTimeSeries, load, "max_active_power"; ignore_scaling_factors = true)
#         tstamps = timestamp(ts_array)[1:total_steps]
#         tstamp_other = tstamps[1:steps_in_resolution:total_steps]
#         vals = values(ts_array)[1:total_steps]
#         # Average the fine-resolution values within each coarse step
#         vals_other = [mean(vals[1 + (i-1)*steps_in_resolution : i*steps_in_resolution]) for i in 1:nums]
#         new_array = TimeArray(tstamp_other, vals_other)
#         ts_new = SingleTimeSeries(name = "max_active_power", data = new_array, scaling_factor_multiplier = get_max_active_power)
#         add_time_series!(sys_other, load_other, ts_new)
#     end
# end

# """
# Resamples the `max_active_power` time series for all loads of `load_type` from `sys` into
# `sys_other` by summing over each coarser time step, preserving total energy consumed.
# """
# function add_load_new_sum_time_series!(sys, sys_other, steps_in_resolution, total_steps; load_type = StandardLoad)
#     for load in get_component(load_type, sys)
#         load_other = get_component(load_type, sys_other, load.name)
#         ts_array = get_time_series_array(SingleTimeSeries, load, "max_active_power"; ignore_scaling_factors = true)
#         tstamps = timestamp(ts_array)[1:total_steps]
#         tstamp_other = tstamps[1:steps_in_resolution:total_steps]
#         vals = values(ts_array)[1:total_steps]
#         # Sum the fine-resolution values within each coarse step to preserve total energy
#         vals_other = [sum(vals[1 + (i-1)*steps_in_resolution : i*steps_in_resolution]) for i in 1:nums]
#         new_array = TimeArray(tstamp_other, vals_other)
#         ts_new = SingleTimeSeries(name = "max_active_power", data = new_array, scaling_factor_multiplier = get_max_active_power)
#         add_time_series!(sys_other, load_other, ts_new)
#     end
# end

# """
# Resamples the `max_active_power` time series for all renewable generators of `renewable_type`
# from `sys` into `sys_other` by averaging over each coarser time step.
# """
# function add_renewable_new_time_series!(sys, sys_other, steps_in_resolution, total_steps; renewable_type = RenewableDispatch)
#     for ren in get_components(renewable_type, sys)
#         ren_other = get_component(renewable_type, sys_other, ren.name)
#         ts_array = get_time_series_array(SingleTimeSeries, ren, "max_active_power"; ignore_scaling_factors = true)
#         tstamps = timestamp(ts_array)[1:total_steps]
#         tstamp_other = tstamps[1:steps_in_resolution:total_steps]
#         vals = values(ts_array)[1:total_steps]
#         # Average the fine-resolution values within each coarse step
#         vals_other = [mean(vals[1 + (i-1)*steps_in_resolution : i*steps_in_resolution]) for i in 1:nums]
#         new_array = TimeArray(tstamp_other, vals_other)
#         ts_new = SingleTimeSeries(name = "max_active_power", data = new_array, scaling_factor_multiplier = get_max_active_power)
#         add_time_series!(sys_other, ren_other, ts_new)
#     end
# end

# """
# Resamples both the `inflow` and `outflow` time series for all `HydroReservoir` components
# from `sys` into `sys_other` by averaging over each coarser time step.
# """
# function add_inflow_outflow_new_time_series!(sys, sys_other, steps_in_resolution, total_steps)
#     # Resample inflow series
#     for res in get_components(HydroReservoir, sys)
#         res_other = get_component(HydroReservoir, sys_other, res.name)
#         ts_array = get_time_series_array(SingleTimeSeries, res, "inflow"; ignore_scaling_factors = true)
#         tstamps = timestamp(ts_array)[1:total_steps]
#         tstamp_other = tstamps[1:steps_in_resolution:total_steps]
#         vals = values(ts_array)[1:total_steps]
#         vals_other = [mean(vals[1 + (i-1)*steps_in_resolution : i*steps_in_resolution]) for i in 1:nums]
#         new_array = TimeArray(tstamp_other, vals_other)
#         ts_new = SingleTimeSeries(name = "inflow", data = new_array)
#         add_time_series!(sys_other, res_other, ts_new)
#     end
#     # Resample outflow series
#     for res in get_components(HydroReservoir, sys)
#         res_other = get_component(HydroReservoir, sys_other, res.name)
#         ts_array = get_time_series_array(SingleTimeSeries, res, "outflow"; ignore_scaling_factors = true)
#         tstamps = timestamp(ts_array)[1:total_steps]
#         tstamp_other = tstamps[1:steps_in_resolution:total_steps]
#         vals = values(ts_array)[1:total_steps]
#         vals_other = [mean(vals[1 + (i-1)*steps_in_resolution : i*steps_in_resolution]) for i in 1:nums]
#         new_array = TimeArray(tstamp_other, vals_other)
#         ts_new = SingleTimeSeries(name = "outflow", data = new_array)
#         add_time_series!(sys_other, res_other, ts_new)
#     end
# end

# """
# Creates a `hydro_target` time series for all `HydroReservoir` components in `sys_other` where
# only the final time step carries a non-zero value (1.0), effectively encoding an end-of-horizon
# storage target.
# """
# function add_final_target_new_time_series!(sys, sys_other, steps_in_resolution, total_steps)
#     for res in get_components(HydroReservoir, sys)
#         res_other = get_component(HydroReservoir, sys_other, res.name)
#         ts_array = get_time_series_array(SingleTimeSeries, res, "hydro_target"; ignore_scaling_factors = true)
#         tstamps = timestamp(ts_array)[1:total_steps]
#         tstamp_other = tstamps[1:steps_in_resolution:total_steps]
#         vals = values(ts_array)[1:total_steps]
#         # All steps are zero except the last, which is set to 1.0 to mark the final target
#         vals_other = zeros(365)
#         vals_other[365] = get_storage_level_limits(res).max
#         #vals_other = [mean(vals[1 + (i-1)*steps_in_resolution : i*steps_in_resolution]) for i in 1:nums]
#         new_array = TimeArray(tstamp_other, vals_other)
#         ts_new = SingleTimeSeries(name = "hydro_target", data = new_array)
#         add_time_series!(sys_other, res_other, ts_new)
#     end
# end

# """
# Resamples the `requirement` time series for all reserves of `reserve_type` from `sys` into
# `sys_other` by averaging over each coarser time step.
# """
# function add_reserves_new_time_series!(sys, sys_other, steps_in_resolution, total_steps; reserve_type = VariableReserve)
#     for reserve in get_components(reserve_type, sys)
#         reserve_other = get_component(reserve_type, sys_other, reserve.name)
#         ts_array = get_time_series_array(SingleTimeSeries, reserve, "requirement"; ignore_scaling_factors = true)
#         tstamps = timestamp(ts_array)[1:total_steps]
#         tstamp_other = tstamps[1:steps_in_resolution:total_steps]
#         vals = values(ts_array)[1:total_steps]
#         # Average the fine-resolution values within each coarse step
#         vals_other = [mean(vals[1 + (i-1)*steps_in_resolution : i*steps_in_resolution]) for i in 1:nums]
#         new_array = TimeArray(tstamp_other, vals_other)
#         ts_new = SingleTimeSeries(name = "requirement", data = new_array)
#         add_time_series!(sys_other, reserve_other, ts_new)
#     end
# end

function set_turbine_cost_to_zero!(sys)
    for ht in get_components(HydroTurbine, sys)
        set_operation_cost!(ht, HydroGenerationCost(CostCurve(LinearCurve(0.0)), 0.0))
    end
end

"""
Resamples the `max_active_power` time series for all loads of `load_type` from `sys` into
`sys_other` by averaging over each coarser time step.
"""
function add_load_new_mean_time_series!(sys, sys_other, steps_in_resolution, total_steps; load_type = StandardLoad)
    for load in get_components(load_type, sys)
        load_other = get_component(load_type, sys_other, load.name)
        ts_array = get_time_series_array(SingleTimeSeries, load, "max_active_power"; ignore_scaling_factors = true)

        raw_vals    = values(ts_array)
        raw_tstamps = timestamp(ts_array)
        n_raw       = length(raw_vals)

        vals       = repeat(raw_vals, ceil(Int, total_steps / n_raw))[1:total_steps]
        start_time = raw_tstamps[1]
        tstamps    = [start_time + Hour(i) for i in 0:(total_steps - 1)]

        tstamp_other = tstamps[1:steps_in_resolution:total_steps]
        vals_other   = [mean(vals[1 + (i-1)*steps_in_resolution : i*steps_in_resolution]) for i in 1:nums]
        new_array    = TimeArray(tstamp_other, vals_other)
        ts_new       = SingleTimeSeries(name = "max_active_power", data = new_array, scaling_factor_multiplier = get_max_active_power)
        add_time_series!(sys_other, load_other, ts_new)
    end
end

"""
Resamples the `max_active_power` time series for all loads of `load_type` from `sys` into
`sys_other` by summing over each coarser time step, preserving total energy consumed.
"""
function add_load_new_sum_time_series!(sys, sys_other, steps_in_resolution, total_steps; load_type = StandardLoad)
    for load in get_components(load_type, sys)  # fixed: was get_component (typo in original)
        load_other = get_component(load_type, sys_other, load.name)
        ts_array = get_time_series_array(SingleTimeSeries, load, "max_active_power"; ignore_scaling_factors = true)

        raw_vals    = values(ts_array)
        raw_tstamps = timestamp(ts_array)
        n_raw       = length(raw_vals)

        vals       = repeat(raw_vals, ceil(Int, total_steps / n_raw))[1:total_steps]
        start_time = raw_tstamps[1]
        tstamps    = [start_time + Hour(i) for i in 0:(total_steps - 1)]

        tstamp_other = tstamps[1:steps_in_resolution:total_steps]
        vals_other   = [sum(vals[1 + (i-1)*steps_in_resolution : i*steps_in_resolution]) for i in 1:nums]
        new_array    = TimeArray(tstamp_other, vals_other)
        ts_new       = SingleTimeSeries(name = "max_active_power", data = new_array, scaling_factor_multiplier = get_max_active_power)
        add_time_series!(sys_other, load_other, ts_new)
    end
end

"""
Resamples the `max_active_power` time series for all renewable generators of `renewable_type`
from `sys` into `sys_other` by averaging over each coarser time step.
"""
function add_renewable_new_time_series!(sys, sys_other, steps_in_resolution, total_steps; renewable_type = RenewableDispatch)
    for ren in get_components(renewable_type, sys)
        ren_other = get_component(renewable_type, sys_other, ren.name)
        ts_array = get_time_series_array(SingleTimeSeries, ren, "max_active_power"; ignore_scaling_factors = true)

        raw_vals    = values(ts_array)
        raw_tstamps = timestamp(ts_array)
        n_raw       = length(raw_vals)

        vals       = repeat(raw_vals, ceil(Int, total_steps / n_raw))[1:total_steps]
        start_time = raw_tstamps[1]
        tstamps    = [start_time + Hour(i) for i in 0:(total_steps - 1)]

        tstamp_other = tstamps[1:steps_in_resolution:total_steps]
        vals_other   = [mean(vals[1 + (i-1)*steps_in_resolution : i*steps_in_resolution]) for i in 1:nums]
        new_array    = TimeArray(tstamp_other, vals_other)
        ts_new       = SingleTimeSeries(name = "max_active_power", data = new_array, scaling_factor_multiplier = get_max_active_power)
        add_time_series!(sys_other, ren_other, ts_new)
    end
end

"""
Resamples both the `inflow` and `outflow` time series for all `HydroReservoir` components
from `sys` into `sys_other` by averaging over each coarser time step.
"""
function add_inflow_outflow_new_time_series!(sys, sys_other, steps_in_resolution, total_steps)
    for series_name in ("inflow", "outflow")
        for res in get_components(HydroReservoir, sys)
            res_other = get_component(HydroReservoir, sys_other, res.name)
            ts_array = get_time_series_array(SingleTimeSeries, res, series_name; ignore_scaling_factors = true)

            raw_vals    = values(ts_array)
            raw_tstamps = timestamp(ts_array)
            n_raw       = length(raw_vals)

            vals       = repeat(raw_vals, ceil(Int, total_steps / n_raw))[1:total_steps]
            start_time = raw_tstamps[1]
            tstamps    = [start_time + Hour(i) for i in 0:(total_steps - 1)]

            tstamp_other = tstamps[1:steps_in_resolution:total_steps]
            vals_other   = [mean(vals[1 + (i-1)*steps_in_resolution : i*steps_in_resolution]) for i in 1:nums]
            new_array    = TimeArray(tstamp_other, vals_other)
            ts_new       = SingleTimeSeries(name = series_name, data = new_array)
            add_time_series!(sys_other, res_other, ts_new)
        end
    end
end

"""
Creates a `hydro_target` time series for all `HydroReservoir` components in `sys_other` where
only the final time step carries a non-zero value (1.0), effectively encoding an end-of-horizon
storage target.
"""
function add_final_target_new_time_series!(sys, sys_other, steps_in_resolution, total_steps)
    for res in get_components(HydroReservoir, sys)
        res_other = get_component(HydroReservoir, sys_other, res.name)
        ts_array = get_time_series_array(SingleTimeSeries, res, "hydro_target"; ignore_scaling_factors = true)

        raw_tstamps = timestamp(ts_array)
        start_time  = raw_tstamps[1]
        tstamps     = [start_time + Hour(i) for i in 0:(total_steps - 1)]

        tstamp_other = tstamps[1:steps_in_resolution:total_steps]

        # All steps zero except the last, which marks the final storage target
        vals_other         = zeros(nums)   # fixed: was hardcoded 365
        vals_other[104]    = get_storage_level_limits(res).max

        new_array = TimeArray(tstamp_other, vals_other)
        ts_new    = SingleTimeSeries(name = "hydro_target", data = new_array)
        add_time_series!(sys_other, res_other, ts_new)
    end
end

"""
Resamples the `requirement` time series for all reserves of `reserve_type` from `sys` into
`sys_other` by averaging over each coarser time step.
"""
function add_reserves_new_time_series!(sys, sys_other, steps_in_resolution, total_steps; reserve_type = VariableReserve)
    for reserve in get_components(reserve_type, sys)
        reserve_other = get_component(reserve_type, sys_other, reserve.name)
        ts_array = get_time_series_array(SingleTimeSeries, reserve, "requirement"; ignore_scaling_factors = true)

        raw_vals    = values(ts_array)
        raw_tstamps = timestamp(ts_array)
        n_raw       = length(raw_vals)

        vals       = repeat(raw_vals, ceil(Int, total_steps / n_raw))[1:total_steps]
        start_time = raw_tstamps[1]
        tstamps    = [start_time + Hour(i) for i in 0:(total_steps - 1)]

        tstamp_other = tstamps[1:steps_in_resolution:total_steps]
        vals_other   = [mean(vals[1 + (i-1)*steps_in_resolution : i*steps_in_resolution]) for i in 1:nums]
        new_array    = TimeArray(tstamp_other, vals_other)
        ts_new       = SingleTimeSeries(name = "requirement", data = new_array)
        add_time_series!(sys_other, reserve_other, ts_new)
    end
end

function hourly_to_daily_last(hourly::Vector)
    @assert length(hourly) == 8760 "Input must have 8760 elements"
    return [hourly[i*24] for i in 1:365]
end

"""
Resamples the `hydro_target` time series for all reservoirs of type `HydroReservoir`
from `sys` into `sys_other` by taking the last value of each resolution period.
"""
function add_hydro_target_new_time_series!(sys, sys_other, steps_in_resolution, total_steps)
    nums = total_steps ÷ steps_in_resolution

    for res in get_components(HydroReservoir, sys)
        res_other    = get_component(HydroReservoir, sys_other, res.name)
        ts_array     = get_time_series_array(SingleTimeSeries, res, "hydro_target"; ignore_scaling_factors = true)
        raw_tstamps  = timestamp(ts_array)
        max_level    = get_storage_level_limits(res).max

        # Fill all steps with max_level (no repeat/slice arithmetic needed)
        vals = fill(max_level, total_steps)

        start_time   = raw_tstamps[1]
        tstamps      = [start_time + Hour(i) for i in 0:(total_steps - 1)]
        tstamp_other = tstamps[1:steps_in_resolution:total_steps]
        vals_other   = [last(vals[1 + (i-1)*steps_in_resolution : i*steps_in_resolution]) for i in 1:nums]

        new_array = TimeArray(tstamp_other, vals_other)
        ts_new    = SingleTimeSeries(name = "hydro_target", data = new_array)
        add_time_series!(sys_other, res_other, ts_new)
    end
end

function resample_weekly_to_hourly(weekly_vals::Vector{Float64}, total_hours::Int=8760)
    @assert length(weekly_vals) == 52 "Expected 52 weekly values, got $(length(weekly_vals))"
    
    hourly_vals  = Float64[]
    hours_per_week = 168  # 7 * 24

    for val in weekly_vals
        hours_remaining = total_hours - length(hourly_vals)
        n_hours = min(hours_per_week, hours_remaining)
        append!(hourly_vals, fill(val, n_hours))
        length(hourly_vals) >= total_hours && break
    end

    # last week gets remaining hours (192 for the final week)
    if length(hourly_vals) < total_hours
        append!(hourly_vals, fill(last(weekly_vals), total_hours - length(hourly_vals)))
    end

    @assert length(hourly_vals) == total_hours "Expected $total_hours hourly values, got $(length(hourly_vals))"
    return hourly_vals
end

function save_results_to_csv(results_dict, results_dir, sys_prefix = "")
    for key in keys(results_dict)
        @info "Storing $key"
        df = results_dict[key]
        store_key = replace(key, "__" => "_")
        save_path = joinpath(results_dir, sys_prefix)
        isdir(save_path) || mkpath(save_path)
        CSV.write(joinpath(save_path, "$(store_key).csv"), df)
    end
end

function convert_hydro_targets_med_to_short(med_term_sys, short_term_sys, steps_in_resolution, total_steps, med_term_data, model_type)
    nums = total_steps ÷ steps_in_resolution
    nums_med_term = Int(size(med_term_data, 1) / length(get_components(HydroReservoir, med_term_sys)))
    convertion_steps = nums ÷ nums_med_term

    for res in get_components(HydroReservoir, med_term_sys)
        @info "Converting $(res.name) from med-term to short-term with $convertion_steps steps per med-term step"
        short_term_res    = get_component(HydroReservoir, short_term_sys, res.name)
        med_term_res_data = filter(row -> row.name == res.name, med_term_data)[:, :value]
        med_tstamps  = filter(row -> row.name == res.name, med_term_data)[:, :DateTime]
        max_level    = get_storage_level_limits(res).max

        short_term_res_data = repeat(med_term_res_data, inner = convertion_steps)
        missing_steps = total_steps - length(short_term_res_data)
        if missing_steps > 0
            @info "Filling missing steps with max level for $(missing_steps) missing steps"
            short_term_res_data = vcat(short_term_res_data, fill(max_level, missing_steps))
        end

        tstamps = [first(med_tstamps) + Hour(i) for i in 0:(total_steps - 1)]
        short_tstamps = tstamps[1:steps_in_resolution:total_steps]

        new_array = TimeArray(short_tstamps, short_term_res_data)
        ts_new    = SingleTimeSeries(name = model_type, data = new_array)
        add_time_series!(short_term_sys, short_term_res, ts_new)
    end
end