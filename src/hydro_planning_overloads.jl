"""
hydro_planning_overloads.jl

Method overloads and utilities to extend hydro-focused SiennaPRASInterface constructors
with hydro planning capabilities. Includes functions to extract hydro inflow data from
UC simulations for use in multi-stage RA planning.
"""

"""
    SPI.GeneratorPRAS(hydro_planning::Bool; system=nothing, hydro_inflow_data=nothing, kwargs...)

Hydro-planning overload for `GeneratorPRAS` that extracts inflow data from UC simulation.
When `hydro_planning=true` and `system` is provided, runs a UC simulation to extract
hydro active power data for use as inflow time series.

# Arguments
- `hydro_planning::Bool`: Whether to run hydro planning simulation
- `system::PSY.System`: Optional system for UC simulation (will be modified in place)
- `hydro_inflow_data::Dict`: Precomputed inflow data from `extract_hydro_inflow_from_simulation`
- Other kwargs forwarded to base `GeneratorPRAS` constructor
"""
function SPI.GeneratorPRAS(hydro_planning::Bool; system=nothing, hydro_inflow_data=nothing, kwargs...)
    if hydro_planning
        if !isnothing(system) && isnothing(hydro_inflow_data)
            @info "GeneratorPRAS: Running UC simulation for hydro planning..."
            hydro_inflow_data = extract_hydro_inflow_from_simulation(system)
        end
        if !isnothing(hydro_inflow_data) && !isnothing(system)
            @info "GeneratorPRAS: Applying hydro inflow data to system for PRAS conversion"
            apply_hydro_inflow_to_system!(system, hydro_inflow_data)
        end
    end

    return SPI.GeneratorPRAS(; kwargs...)
end

"""
    SPI.HydroEnergyReservoirPRAS(hydro_planning::Bool; system=nothing, hydro_inflow_data=nothing, kwargs...)

Hydro-planning overload for `HydroEnergyReservoirPRAS` that extracts inflow data from UC simulation.
When `hydro_planning=true` and `system` is provided, runs a UC simulation to extract
hydro active power data for use as inflow time series.

# Arguments
- `hydro_planning::Bool`: Whether to run hydro planning simulation
- `system::PSY.System`: Optional system for UC simulation (will be modified in place)
- `hydro_inflow_data::Dict`: Precomputed inflow data from `extract_hydro_inflow_from_simulation`
- Other kwargs forwarded to base `HydroEnergyReservoirPRAS` constructor

# Example
```julia
hydro_inflow_data = extract_hydro_inflow_from_simulation(system)
SPI.HydroEnergyReservoirPRAS(true, system=system; max_active_power="max_active_power")
```
"""
function SPI.HydroEnergyReservoirPRAS(hydro_planning::Bool; system=nothing, hydro_inflow_data=nothing, kwargs...)
    if hydro_planning
        if !isnothing(system) && isnothing(hydro_inflow_data)
            @info "HydroEnergyReservoirPRAS: Running UC simulation for hydro planning..."
            hydro_inflow_data = extract_hydro_inflow_from_simulation(system)
        end
        if !isnothing(hydro_inflow_data) && !isnothing(system)
            @info "HydroEnergyReservoirPRAS: Applying hydro inflow data to system for PRAS conversion"
            apply_hydro_inflow_to_system!(system, hydro_inflow_data)
        end
    end

    return SPI.HydroEnergyReservoirPRAS(; kwargs...)
end

if isdefined(SPI, :EnergyReservoirSoC)
    """
        SPI.EnergyReservoirSoC(hydro_planning::Bool; system=nothing, hydro_inflow_data=nothing, kwargs...)

    Hydro-planning overload for `EnergyReservoirSoC` (only defined when
    `SiennaPRASInterface` exposes this constructor in the current version).
    """
    @eval function SPI.EnergyReservoirSoC(hydro_planning::Bool; system=nothing, hydro_inflow_data=nothing, kwargs...)
        if hydro_planning
            if !isnothing(system) && isnothing(hydro_inflow_data)
                @info "EnergyReservoirSoC: Running UC simulation for hydro planning..."
                hydro_inflow_data = extract_hydro_inflow_from_simulation(system)
            end
            if !isnothing(hydro_inflow_data) && !isnothing(system)
                @info "EnergyReservoirSoC: Applying hydro inflow data to system for PRAS conversion"
                apply_hydro_inflow_to_system!(system, hydro_inflow_data)
            end
        end

        return SPI.EnergyReservoirSoC(; kwargs...)
    end
end

"""
    extract_hydro_inflow_from_simulation(system::PSY.System; template=nothing, optimizer=HiGHS.Optimizer)

Run a UC simulation to extract hydro active power data for use as inflow time series in multi-stage RA planning.

# Arguments
- `system::PSY.System`: Power system to simulate
- `template::PSI.ProblemTemplate`: Optional custom UC template (defaults to standard UC with hydro)
- `optimizer`: Optimizer for UC problem (default: HiGHS.Optimizer)

# Returns
- `Dict{String, Matrix{Float64}}`: Dictionary mapping hydro component names to their active power time series.
  Each value is a matrix with columns [timestamp, component1_power, component2_power, ...]

# Example
```julia
sys = PSB.build_system(PSB.PSISystems, "5_bus_hydro_uc_sys")
hydro_data = extract_hydro_inflow_from_simulation(sys)
```
"""
function extract_hydro_inflow_from_simulation(
    system::PSY.System;
    template::Union{Nothing, PSI.ProblemTemplate}=nothing,
    optimizer=HiGHS.Optimizer,
)
    # Create default UC template if not provided
    if isnothing(template)
        template = PSI.ProblemTemplate(PSI.CopperPlatePowerModel)
        PSI.set_device_model!(template, PSY.ThermalStandard, PSI.ThermalBasicUnitCommitment)
        PSI.set_device_model!(template, PSY.PowerLoad, PSI.StaticPowerLoad)
        if isdefined(PSY, :HydroDispatch)
            PSI.set_device_model!(template, PSY.HydroDispatch, HPS.HydroDispatchRunOfRiver)
        end
        if isdefined(PSY, :HydroEnergyReservoir)
            PSI.set_device_model!(template, PSY.HydroEnergyReservoir, HPS.HydroCommitmentReservoirStorage)
        end
    end

    # Build and execute UC simulation
    models = PSI.SimulationModels([
        PSI.DecisionModel(
            template,
            system;
            name = "HydroPlanning",
            initialize_model = false,
            system_to_file = false,
            optimizer = optimizer,
        ),
    ])

    sequence = PSI.SimulationSequence(;
        models = models,
        ini_cond_chronology = PSI.InterProblemChronology(),
    )

    sim = PSI.Simulation(;
        name = "hydro_planning_sim",
        steps = 1,
        models = models,
        sequence = sequence,
        simulation_folder = mktempdir(; cleanup = true),
    )

    @info "Building UC simulation for hydro planning..."
    PSI.build!(sim; serialize = false)

    @info "Executing UC simulation for hydro planning..."
    PSI.execute!(sim; enable_progress_bar = false)

    results = PSI.SimulationResults(sim; ignore_status = true)
    r = PSI.get_decision_problem_results(results, "HydroPlanning")

    # Extract realized variables into a dict
    inflow_dict = Dict{String, Matrix{Float64}}()

    # HydroDispatch active power
    if isdefined(PSY, :HydroDispatch)
        try
            hy_dispatch_df = PSI.read_realized_variable(r, "ActivePowerVariable__HydroDispatch")
            # Convert to matrix, excluding timestamp column (column 1) 
            inflow_dict["HydroDispatch"] = Matrix(hy_dispatch_df[!, 2:end])
            @info "Extracted $(size(hy_dispatch_df, 2)-1) HydroDispatch components from UC results"
        catch e
            @warn "Could not extract HydroDispatch data: $(e)"
        end
    end

    # HydroEnergyReservoir active power
    if isdefined(PSY, :HydroEnergyReservoir)
        try
            hy_reservoir_df = PSI.read_realized_variable(r, "ActivePowerVariable__HydroEnergyReservoir")
            # Convert to matrix, excluding timestamp column (column 1)
            inflow_dict["HydroEnergyReservoir"] = Matrix(hy_reservoir_df[!, 2:end])
            @info "Extracted $(size(hy_reservoir_df, 2)-1) HydroEnergyReservoir components from UC results"
        catch e
            @warn "Could not extract HydroEnergyReservoir data: $(e)"
        end
    end

    return inflow_dict
end

"""
    apply_hydro_inflow_to_system!(system::PSY.System, hydro_inflow_data::Dict{String, Matrix{Float64}}; time_series_name::String="inflow")

Apply extracted hydro inflow data to a system by creating and attaching time series to components.
This integrates with SiennaPRASInterface's PRAS conversion pipeline, which expects time series
with the name specified in the HydroEnergyReservoirPRAS formulation (default: "inflow").

# Arguments
- `system::PSY.System`: System to modify (mutated in place)
- `hydro_inflow_data::Dict{String, Matrix{Float64}}`: Output from `extract_hydro_inflow_from_simulation`
- `time_series_name::String`: Name for the time series (default: "inflow", must match HydroEnergyReservoirPRAS formulation)

# Returns
- `system::PSY.System`: The modified system with inflow time series attached

# Example
```julia
sys = PSB.build_system(PSB.PSISystems, "5_bus_hydro_uc_sys")
hydro_data = extract_hydro_inflow_from_simulation(sys)
apply_hydro_inflow_to_system!(sys, hydro_data)
```
"""
function apply_hydro_inflow_to_system!(
    system::PSY.System,
    hydro_inflow_data::Dict{String, Matrix{Float64}};
    time_series_name::String="inflow",
)
    if isempty(hydro_inflow_data)
        @warn "No hydro inflow data provided"
        return system
    end

    function _build_timestamps(n_rows::Int)
        if n_rows <= 0
            return DateTime[]
        end
        try
            init_times = PSY.get_forecast_initial_times(system)
            if !isempty(init_times)
                init_time = first(init_times)
                return collect(init_time:Hour(1):(init_time + Hour(n_rows - 1)))
            end
        catch
        end
        start_time = DateTime(2020, 1, 1)
        return collect(start_time:Hour(1):(start_time + Hour(n_rows - 1)))
    end

    function _to_series_dataframe(ts_data, ts_name::String)
        df = DataFrame(ts_data)
        cols = names(df)
        if isempty(cols)
            return DataFrame(:timestamp => DateTime[], Symbol(ts_name) => Float64[])
        end

        timestamp_idx = findfirst(c -> lowercase(String(c)) in ("timestamp", "datetime", "time"), cols)
        timestamp_col = isnothing(timestamp_idx) ? cols[1] : cols[timestamp_idx]

        value_col = if Symbol(ts_name) in cols
            Symbol(ts_name)
        else
            first(filter(c -> c != timestamp_col, cols))
        end

        return DataFrame(
            :timestamp => DateTime.(df[!, timestamp_col]),
            Symbol(ts_name) => Float64.(df[!, value_col]),
        )
    end

    function _merge_matching_timestamps(existing_df::DataFrame, new_df::DataFrame, ts_name::String)
        val_col = Symbol(ts_name)
        new_map = Dict(new_df.timestamp .=> new_df[!, val_col])
        merged_vals = copy(existing_df[!, val_col])
        replaced = 0

        for i in eachindex(merged_vals)
            t = existing_df.timestamp[i]
            if haskey(new_map, t)
                merged_vals[i] = new_map[t]
                replaced += 1
            end
        end

        return DataFrame(:timestamp => existing_df.timestamp, val_col => merged_vals), replaced
    end

    function _remove_existing_single_time_series!(component)
        if !PSY.has_time_series(component, PSY.SingleTimeSeries, time_series_name)
            return true
        end

        if isdefined(PSY, :DeterministicSingleTimeSeries) &&
           PSY.has_time_series(component, PSY.DeterministicSingleTimeSeries, time_series_name)
            try
                PSY.remove_time_series!(
                    system,
                    PSY.DeterministicSingleTimeSeries,
                    component,
                    time_series_name,
                )
            catch e
                @warn "Could not remove dependent deterministic series $(time_series_name) on $(PSY.get_name(component))" exception=(e, catch_backtrace())
            end
        end

        try
            PSY.remove_time_series!(system, PSY.SingleTimeSeries, component, time_series_name)
        catch e
            @warn "Could not remove existing $(time_series_name) series on $(PSY.get_name(component))" exception=(e, catch_backtrace())
            return false
        end

        removed = !PSY.has_time_series(component, PSY.SingleTimeSeries, time_series_name)
        if !removed
            @warn "Existing $(time_series_name) series still present after removal attempt on $(PSY.get_name(component))"
        end
        return removed
    end
    
    # Process HydroDispatch components
    if haskey(hydro_inflow_data, "HydroDispatch") && isdefined(PSY, :HydroDispatch)
        inflow_matrix = hydro_inflow_data["HydroDispatch"]
        hydro_dispatch_list = collect(PSY.get_components(PSY.HydroDispatch, system))
        n_components = min(size(inflow_matrix, 2), length(hydro_dispatch_list))
        
        if n_components > 0
            @info "Attaching inflow time series to $(n_components) HydroDispatch components"
            for (i, component) in enumerate(hydro_dispatch_list[1:n_components])
                data = inflow_matrix[:, i]
                timestamps = _build_timestamps(length(data))
                ts_df = DataFrame(
                    :timestamp => timestamps,
                    Symbol(time_series_name) => data,
                )
                target_df = ts_df
                if PSY.has_time_series(component, PSY.SingleTimeSeries, time_series_name)
                    existing_ts = PSY.get_time_series(PSY.SingleTimeSeries, component, time_series_name)
                    existing_df = _to_series_dataframe(PSY.get_data(existing_ts), time_series_name)

                    full_match =
                        size(existing_df, 1) == size(ts_df, 1) &&
                        all(existing_df.timestamp .== ts_df.timestamp)

                    if !full_match
                        merged_df, replaced = _merge_matching_timestamps(existing_df, ts_df, time_series_name)
                        if replaced == 0
                            @warn "No matching timestamps found for $(PSY.get_name(component)); keeping original series"
                            continue
                        end
                        @info "Partially replaced $(replaced)/$(size(existing_df, 1)) points for $(PSY.get_name(component)) due to length/timestamp mismatch"
                        target_df = merged_df
                    end

                    if !_remove_existing_single_time_series!(component)
                        @warn "Skipping replacement for $(PSY.get_name(component)) because existing series could not be removed"
                        continue
                    end
                end
                ts = PSY.SingleTimeSeries(time_series_name, target_df)
                PSY.add_time_series!(system, component, ts)
                @debug "Added $(time_series_name) time series to $(PSY.get_name(component))"
            end
        end
    end

    # Process HydroEnergyReservoir components
    if haskey(hydro_inflow_data, "HydroEnergyReservoir") && isdefined(PSY, :HydroEnergyReservoir)
        inflow_matrix = hydro_inflow_data["HydroEnergyReservoir"]
        hydro_reservoir_list = collect(PSY.get_components(PSY.HydroEnergyReservoir, system))
        n_components = min(size(inflow_matrix, 2), length(hydro_reservoir_list))
        
        if n_components > 0
            @info "Attaching inflow time series to $(n_components) HydroEnergyReservoir components"
            for (i, component) in enumerate(hydro_reservoir_list[1:n_components])
                data = inflow_matrix[:, i]
                timestamps = _build_timestamps(length(data))
                ts_df = DataFrame(
                    :timestamp => timestamps,
                    Symbol(time_series_name) => data,
                )
                target_df = ts_df
                if PSY.has_time_series(component, PSY.SingleTimeSeries, time_series_name)
                    existing_ts = PSY.get_time_series(PSY.SingleTimeSeries, component, time_series_name)
                    existing_df = _to_series_dataframe(PSY.get_data(existing_ts), time_series_name)

                    full_match =
                        size(existing_df, 1) == size(ts_df, 1) &&
                        all(existing_df.timestamp .== ts_df.timestamp)

                    if !full_match
                        merged_df, replaced = _merge_matching_timestamps(existing_df, ts_df, time_series_name)
                        if replaced == 0
                            @warn "No matching timestamps found for $(PSY.get_name(component)); keeping original series"
                            continue
                        end
                        @info "Partially replaced $(replaced)/$(size(existing_df, 1)) points for $(PSY.get_name(component)) due to length/timestamp mismatch"
                        target_df = merged_df
                    end

                    if !_remove_existing_single_time_series!(component)
                        @warn "Skipping replacement for $(PSY.get_name(component)) because existing series could not be removed"
                        continue
                    end
                end
                ts = PSY.SingleTimeSeries(time_series_name, target_df)
                PSY.add_time_series!(system, component, ts)
                @debug "Added $(time_series_name) time series to $(PSY.get_name(component))"
            end
        end
    end

    @info "Hydro inflow time series applied to system, ready for PRAS conversion"
    return system
end
