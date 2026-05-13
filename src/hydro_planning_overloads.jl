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
function SPI.GeneratorPRAS(hydro_planning::Bool; system=nothing, hydro_inflow_data=nothing, template=nothing, kwargs...)
    if hydro_planning
        if !isnothing(system) && isnothing(hydro_inflow_data)
            @info "GeneratorPRAS: Running UC simulation for hydro planning..."
            hydro_inflow_data = extract_hydro_inflow_from_simulation(system; template=template)
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
function SPI.HydroEnergyReservoirPRAS(hydro_planning::Bool; system=nothing, hydro_inflow_data=nothing, template=nothing, kwargs...)
    if hydro_planning
        if !isnothing(system) && isnothing(hydro_inflow_data)
            @info "HydroEnergyReservoirPRAS: Running UC simulation for hydro planning..."
            hydro_inflow_data = extract_hydro_inflow_from_simulation(system; template=template)
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
    @eval function SPI.EnergyReservoirSoC(hydro_planning::Bool; system=nothing, hydro_inflow_data=nothing, template=nothing, kwargs...)
        if hydro_planning
            if !isnothing(system) && isnothing(hydro_inflow_data)
                @info "EnergyReservoirSoC: Running UC simulation for hydro planning..."
                hydro_inflow_data = extract_hydro_inflow_from_simulation(system; template=template)
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
    (system::PSY.System; template=nothing, optimizer=HiGHS.Optimizer)

Run a UC simulation to extract hydro active power data for use as inflow time series in multi-stage RA planning.

# Arguments
- `system::PSY.System`: Power system to simulate
- `template::PSI.ProblemTemplate`: Optional custom UC template (defaults to standard UC with hydro)
- `optimizer`: Optimizer for UC problem (default: HiGHS.Optimizer)

# Returns
- `Dict{String, Any}`: Dictionary mapping hydro component categories to extracted inflow payloads.
    `HydroDispatch` and `HydroReservoir` are returned as `DataFrame`s with one column per
    component (column names are component names).

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
    working_system = system

    has_forecast_data = try
        !isempty(PSY.get_forecast_initial_times(system))
    catch
        false
    end

    # Detect system resolution from SingleTimeSeries or DeterministicSingleTimeSeries
    _system_resolution = try
        # First try SingleTimeSeries (present before transform)
        sts = collect(Iterators.take(
            PSY.get_time_series_multiple(working_system; time_series_type=PSY.SingleTimeSeries), 1
        ))
        if !isempty(sts)
            PSY.get_resolution(last(sts))
        else
            # Fall back to DeterministicSingleTimeSeries (present after transform)
            dsts = collect(Iterators.take(
                PSY.get_time_series_multiple(working_system; time_series_type=PSY.DeterministicSingleTimeSeries), 1
            ))
            isempty(dsts) ? Hour(1) : PSY.get_resolution(last(dsts))
        end
    catch
        Hour(1)
    end
    _is_hourly = _system_resolution <= Hour(1)

    if !has_forecast_data && isdefined(PSY, :transform_single_time_series!)
        working_system = deepcopy(system)
        try
            if _is_hourly
                PSY.transform_single_time_series!(working_system, Hour(25), Hour(1))
            else
                PSY.transform_single_time_series!(working_system, Week(25), Week(1))
            end
        catch e
            @debug "Failed to transform single time series to deterministic forecasts for hydro planning" exception=(e, catch_backtrace())
        end
    end

    function _component_count(component_type)
        if !isdefined(PSY, component_type)
            return 0
        end
        return length(collect(PSY.get_components(getfield(PSY, component_type), working_system)))
    end

    function _set_device_model_if_components!(template_obj, component_type, formulation)
        if _component_count(component_type) > 0
            PSI.set_device_model!(template_obj, getfield(PSY, component_type), formulation)
        end
    end

    # Create default UC template if not provided
    if isnothing(template)
        template = PSI.ProblemTemplate(PSI.NetworkModel(PSI.CopperPlatePowerModel; use_slacks = true))

        _set_device_model_if_components!(template, :ThermalStandard, PSI.ThermalDispatchNoMin)
        _set_device_model_if_components!(template, :RenewableDispatch, PSI.RenewableFullDispatch)
        _set_device_model_if_components!(template, :RenewableNonDispatch, PSI.FixedOutput)
        _set_device_model_if_components!(template, :StandardLoad, PSI.StaticPowerLoad)
        _set_device_model_if_components!(template, :PowerLoad, PSI.StaticPowerLoad)

        if _component_count(:HydroReservoir) > 0
            reservoir_model = PSI.DeviceModel(
                PSY.HydroReservoir,
                HPS.HydroWaterModelReservoir;
                attributes = Dict("hydro_target" => true, "hydro_budget" => false),
            )
            PSI.set_device_model!(template, reservoir_model)
        end

        if _component_count(:HydroTurbine) > 0
            PSI.set_device_model!(template, PSY.HydroTurbine, HPS.HydroTurbineWaterLinearCommitment)
        end

        if _component_count(:HydroDispatch) > 0
            PSI.set_device_model!(template, PSY.HydroDispatch, HPS.HydroDispatchRunOfRiver)
        end

        # Add reserve service model with slacks if VariableReserve{ReserveUp} components are present.
        # Must use the concrete parameterized type directly — get_components on the bare
        # VariableReserve abstract/parametric type returns 0 even when components exist.
        if isdefined(PSY, :VariableReserve) && isdefined(PSY, :ReserveUp) &&
                !isempty(collect(PSY.get_components(PSY.VariableReserve{PSY.ReserveUp}, working_system)))
            PSI.set_service_model!(
                template,
                PSI.ServiceModel(PSY.VariableReserve{PSY.ReserveUp}, PSI.RangeReserve; use_slacks=true),
            )
        end
        #TODO: other type of components might need to be set for device model

    end

    # Build and execute UC simulation
    model = PSI.DecisionModel(
        template,
        working_system;
        name = "HydroPlanning",
        initialize_model = true,
        calculate_conflict = true,
         store_variable_names       = true,
    optimizer_solve_log_print  = true,
        optimizer = optimizer,
    )

    models = PSI.SimulationModels(; decision_models = [model])

    sequence = PSI.SimulationSequence(;
        models = models,
        ini_cond_chronology = PSI.InterProblemChronology(),
    )

    sim_initial_time = begin
        try
            available_times = PSY.get_forecast_initial_times(working_system)
            isempty(available_times) ? DateTime("2020-01-01T00:00:00") : first(available_times)
        catch
            DateTime("2020-01-01T00:00:00")
        end
    end

    sim_steps = begin
        default_steps = _is_hourly ? 8736 : 52
        try
            available_times = PSY.get_forecast_initial_times(working_system)
            isempty(available_times) ? default_steps : max(1, length(available_times))
        catch
            default_steps
        end
    end

    sim = PSI.Simulation(;
        name = "hydro_planning_sim",
        steps = 24,
        models = models,
        initial_time = sim_initial_time,
        sequence = sequence,
        simulation_folder = mktempdir(; cleanup = true),
    )

    @info "Building UC simulation for hydro planning..."
    PSI.build!(sim)

    @info "Executing UC simulation for hydro planning..."
    PSI.execute!(sim)

    results = PSI.SimulationResults(sim; ignore_status = true)
    r = PSI.get_decision_problem_results(results, "HydroPlanning")
    # Extract realized variables into a dict
    inflow_dict = Dict{String, Any}()

    function _extract_variable_dataframe(variable_name::String; aux::Bool=false)
        try
            return aux ? PSI.read_realized_aux_variable(r, variable_name) :
                   PSI.read_realized_variable(r, variable_name)
        catch e
            @debug "Could not extract dataframe for $(variable_name)" exception=(e, catch_backtrace())
            return nothing
        end
    end

    function _extract_numeric_component_columns(df::DataFrame)
        if size(df, 2) < 2
            return String[], Vector{Vector{Float64}}()
        end

        numeric_col_names = String[]
        numeric_col_vectors = Vector{Vector{Float64}}()
        for col in names(df)[2:end]
            try
                values = Float64.(df[!, col])
                push!(numeric_col_names, String(col))
                push!(numeric_col_vectors, values)
            catch e
                @debug "Skipping non-numeric UC results column $(col)" exception=(e, catch_backtrace())
            end
        end

        return numeric_col_names, numeric_col_vectors
    end

    function _extract_series_to_matrix!(dict_obj::Dict{String, Any}, key::String, variable_name::String; aux::Bool=false)
        try
            var_df = _extract_variable_dataframe(variable_name; aux=aux)
            if isnothing(var_df)
                return false
            end
            numeric_col_names, numeric_col_vectors = _extract_numeric_component_columns(var_df)
            if !isempty(numeric_col_vectors)
                if key == "HydroDispatch"
                    component_df = DataFrame()
                    for (name, values) in zip(numeric_col_names, numeric_col_vectors)
                        component_df[!, Symbol(name)] = values
                    end
                    dict_obj[key] = component_df
                else
                    dict_obj[key] = hcat(numeric_col_vectors...)
                end
                @info "Extracted $(length(numeric_col_names)) $(key) components from UC results ($(variable_name))"
            end
            return true
        catch e
            @debug "Could not extract $(key) from $(variable_name)" exception=(e, catch_backtrace())
            return false
        end
    end

    # Short-term hydro component outputs
    _extract_series_to_matrix!(inflow_dict, "HydroDispatch", "ActivePowerVariable__HydroDispatch")

    # HydroReservoir inflow: aggregate upstream turbine active power by reservoir
    if isdefined(PSY, :HydroReservoir)
        reservoir_list = collect(PSY.get_components(PSY.HydroReservoir, working_system))
        if !isempty(reservoir_list)
            turbine_var_df = _extract_variable_dataframe("ActivePowerVariable__HydroTurbine")

            turbine_to_reservoir_map = Dict{String, String}()
            for reservoir in reservoir_list
                upstream_turbines = if isdefined(PSY, :HydroTurbine) &&
                                       hasproperty(reservoir, :upstream_turbines) &&
                                       !isempty(reservoir.upstream_turbines)
                    reservoir.upstream_turbines
                else
                    []
                end
                for turbine in upstream_turbines
                    turbine_to_reservoir_map[PSY.get_name(turbine)] = PSY.get_name(reservoir)
                end
            end

            if !isnothing(turbine_var_df) && size(turbine_var_df, 2) >= 2 && !isempty(turbine_to_reservoir_map)
                turbine_long_df = DataFrame(:DateTime => DateTime[], :name => String[], :value => Float64[])
                lower_names = lowercase.(String.(names(turbine_var_df)))
                dt_idx = findfirst(x -> x in ("datetime", "timestamp", "time"), lower_names)
                name_idx = findfirst(==("name"), lower_names)
                value_idx = findfirst(==("value"), lower_names)

                if !isnothing(dt_idx) && !isnothing(name_idx) && !isnothing(value_idx)
                    dt_col = names(turbine_var_df)[dt_idx]
                    name_col = names(turbine_var_df)[name_idx]
                    val_col = names(turbine_var_df)[value_idx]
                    turbine_long_df = DataFrame(
                        :DateTime => DateTime.(turbine_var_df[!, dt_col]),
                        :name => String.(turbine_var_df[!, name_col]),
                        :value => Float64.(turbine_var_df[!, val_col]),
                    )
                else
                    dt_col = isnothing(dt_idx) ? nothing : names(turbine_var_df)[dt_idx]
                    timestamps = if isnothing(dt_col)
                        collect(sim_initial_time:Week(1):(sim_initial_time + Week(size(turbine_var_df, 1) - 1)))
                    else
                        DateTime.(turbine_var_df[!, dt_col])
                    end

                    excluded_cols = isnothing(dt_col) ? Symbol[] : [dt_col]
                    numeric_cols = [
                        col for col in names(turbine_var_df)
                        if !(col in excluded_cols) && eltype(turbine_var_df[!, col]) <: Number
                    ]

                    rows = NamedTuple{(:DateTime, :name, :value), Tuple{DateTime, String, Float64}}[]
                    for turbine_col in numeric_cols
                        values = Float64.(turbine_var_df[!, turbine_col])
                        append!(rows, (DateTime = timestamps[i], name = String(turbine_col), value = values[i]) for i in eachindex(values))
                    end
                    turbine_long_df = DataFrame(rows)
                end

                if !isempty(turbine_long_df)
                    turbine_long_df.reservoir = [get(turbine_to_reservoir_map, n, missing) for n in turbine_long_df.name]
                    turbine_long_df = DataFrames.dropmissing(turbine_long_df, :reservoir)

                    if !isempty(turbine_long_df)
                        df_agg = DataFrames.combine(
                            DataFrames.groupby(turbine_long_df, [:DateTime, :reservoir]),
                            :value => sum => :value,
                        )
                        reservoir_df = DataFrames.unstack(df_agg, :DateTime, :reservoir, :value, fill=0.0)
                        inflow_dict["HydroReservoir"] = DataFrames.sort(reservoir_df, :DateTime)
                        @info "Extracted inflow data for $(length(unique(turbine_long_df.reservoir))) HydroReservoir component(s): $(size(reservoir_df, 1)) time steps"
                    end
                end
            end
        end
    end

    if isempty(inflow_dict)
        @warn "No hydro variables were extracted from the HydroPlanning simulation results"
    end

    return inflow_dict
end

"""
    apply_hydro_inflow_to_system!(system::PSY.System, hydro_inflow_data::Dict{String, Any}; time_series_name::String="inflow")

Apply extracted hydro inflow data to a system by creating and attaching time series to components.
This integrates with SiennaPRASInterface's PRAS conversion pipeline, which expects time series
with the name specified in the HydroEnergyReservoirPRAS formulation (default: "inflow").

# Arguments
- `system::PSY.System`: System to modify (mutated in place)
- `hydro_inflow_data::Dict{String, Any}`: Output from `extract_hydro_inflow_from_simulation`
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
    hydro_inflow_data::Dict{String, Any};
    time_series_name::String="inflow",
    hydro_dispatch_time_series_name::String="max_active_power",
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
        inflow_payload = hydro_inflow_data["HydroDispatch"]
        hydro_dispatch_list = collect(PSY.get_components(PSY.HydroDispatch, system))
        dispatch_inflow_by_name = Dict{String, Vector{Float64}}()

        if inflow_payload isa DataFrame
            for col in names(inflow_payload)
                dispatch_inflow_by_name[String(col)] = Float64.(inflow_payload[!, col])
            end
        elseif inflow_payload isa Matrix{Float64}
            n_components_fallback = min(size(inflow_payload, 2), length(hydro_dispatch_list))
            for (i, component) in enumerate(hydro_dispatch_list[1:n_components_fallback])
                dispatch_inflow_by_name[PSY.get_name(component)] = inflow_payload[:, i]
            end
        else
            @warn "HydroDispatch inflow payload has unsupported type $(typeof(inflow_payload)); skipping dispatch inflow application"
        end

        n_components = count(c -> haskey(dispatch_inflow_by_name, PSY.get_name(c)), hydro_dispatch_list)
        
        if n_components > 0
            @info "Attaching inflow time series to $(n_components) HydroDispatch components"
            for component in hydro_dispatch_list
                component_name = PSY.get_name(component)
                if !haskey(dispatch_inflow_by_name, component_name)
                    continue
                end

                data = dispatch_inflow_by_name[component_name]
                timestamps = _build_timestamps(length(data))
                ts_df = DataFrame(
                    :timestamp => timestamps,
                    Symbol(hydro_dispatch_time_series_name) => data,
                )
                target_df = ts_df
                if PSY.has_time_series(component, PSY.SingleTimeSeries, hydro_dispatch_time_series_name)
                    existing_ts = PSY.get_time_series(PSY.SingleTimeSeries, component, hydro_dispatch_time_series_name)
                    existing_df = _to_series_dataframe(PSY.get_data(existing_ts), hydro_dispatch_time_series_name)

                    full_match =
                        size(existing_df, 1) == size(ts_df, 1) &&
                        all(existing_df.timestamp .== ts_df.timestamp)

                    if !full_match
                        merged_df, replaced = _merge_matching_timestamps(existing_df, ts_df, hydro_dispatch_time_series_name)
                        if replaced == 0
                            @warn "No matching timestamps found for $(PSY.get_name(component)); keeping original series"
                            continue
                        end
                        @info "Partially replaced $(replaced)/$(size(existing_df, 1)) points for $(PSY.get_name(component)) due to length/timestamp mismatch"
                        target_df = merged_df
                    end

                    local function _remove_existing_dispatch_series!(component)
                        if !PSY.has_time_series(component, PSY.SingleTimeSeries, hydro_dispatch_time_series_name)
                            return true
                        end
                        try
                            PSY.remove_time_series!(system, PSY.SingleTimeSeries, component, hydro_dispatch_time_series_name)
                        catch e
                            @warn "Could not remove existing $(hydro_dispatch_time_series_name) series on $(PSY.get_name(component))" exception=(e, catch_backtrace())
                            return false
                        end
                        return !PSY.has_time_series(component, PSY.SingleTimeSeries, hydro_dispatch_time_series_name)
                    end

                    if !_remove_existing_dispatch_series!(component)
                        @warn "Skipping replacement for $(PSY.get_name(component)) because existing series could not be removed"
                        continue
                    end
                end
                ts = PSY.SingleTimeSeries(hydro_dispatch_time_series_name, target_df)
                PSY.add_time_series!(system, component, ts)
                @debug "Added $(hydro_dispatch_time_series_name) time series to $(PSY.get_name(component))"
            end
        end
    end

   

    # Process HydroReservoir components (medium-term formulation)
    if haskey(hydro_inflow_data, "HydroReservoir") && isdefined(PSY, :HydroReservoir)
        inflow_payload = hydro_inflow_data["HydroReservoir"]
        hydro_reservoir_list = collect(PSY.get_components(PSY.HydroReservoir, system))

        reservoir_inflow_by_name = Dict{String, Vector{Float64}}()
        reservoir_payload_timestamps = DateTime[]
        if inflow_payload isa DataFrame
            ts_col_idx = findfirst(c -> lowercase(String(c)) in ("datetime", "timestamp", "time"), names(inflow_payload))
            if !isnothing(ts_col_idx)
                ts_col = names(inflow_payload)[ts_col_idx]
                reservoir_payload_timestamps = DateTime.(inflow_payload[!, ts_col])
            end
            for col in names(inflow_payload)
                if lowercase(String(col)) in ("datetime", "timestamp", "time")
                    continue
                end
                reservoir_inflow_by_name[String(col)] = Float64.(inflow_payload[!, col])
            end
        elseif inflow_payload isa Matrix{Float64}
            n_components_fallback = min(size(inflow_payload, 2), length(hydro_reservoir_list))
            for (i, component) in enumerate(hydro_reservoir_list[1:n_components_fallback])
                reservoir_inflow_by_name[PSY.get_name(component)] = inflow_payload[:, i]
            end
        else
            @warn "HydroReservoir inflow payload has unsupported type $(typeof(inflow_payload)); skipping reservoir inflow application"
        end

        n_components = count(c -> haskey(reservoir_inflow_by_name, PSY.get_name(c)), hydro_reservoir_list)
        if n_components > 0
            @info "Attaching inflow time series to $(n_components) HydroReservoir components"
            for component in hydro_reservoir_list
                component_name = PSY.get_name(component)
                if !haskey(reservoir_inflow_by_name, component_name)
                    continue
                end

                data = reservoir_inflow_by_name[component_name]
                if all(isnan, data)
                    @debug "Skipping HydroReservoir inflow replacement for $(PSY.get_name(component)); no connected upstream HydroTurbine data"
                    continue
                end
                timestamps = if !isempty(reservoir_payload_timestamps) && length(reservoir_payload_timestamps) == length(data)
                    reservoir_payload_timestamps
                else
                    _build_timestamps(length(data))
                end
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
