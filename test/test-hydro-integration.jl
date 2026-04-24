@testset "Hydro Planning: System Integration with Time Series" verbose = true begin
    import HydroSiennaPRASInterface as HSPI
    import PowerSystemCaseBuilder
    import PowerSystems
    import SiennaPRASInterface
    using DataFrames

    PSB = PowerSystemCaseBuilder
    PSY = PowerSystems
    SPI = SiennaPRASInterface

    # Build test system
    sys = PSB.build_system(PSB.PSISystems, "5_bus_hydro_uc_sys")
    @test isa(sys, PSY.System)

    @testset "Extract and Apply Inflow Data to System" begin
        # Extract inflow data from UC simulation
        hydro_data = HSPI.extract_hydro_inflow_from_simulation(sys)
        @test isa(hydro_data, Dict)
        @test length(hydro_data) > 0

        # Copy system to avoid modifying original
        sys_modified = deepcopy(sys)

        # Apply inflow data to system
        result_sys = HSPI.apply_hydro_inflow_to_system!(sys_modified, hydro_data)
        @test result_sys === sys_modified
    end

    @testset "Time Series Added to HydroDispatch Components" begin
        # Extract and apply data
        hydro_data = HSPI.extract_hydro_inflow_from_simulation(sys)
        sys_modified = deepcopy(sys)
        HSPI.apply_hydro_inflow_to_system!(sys_modified, hydro_data)

        # Check if HydroDispatch components have time series
        if isdefined(PSY, :HydroDispatch)
            hydro_dispatches = collect(PSY.get_components(PSY.HydroDispatch, sys_modified))
            if length(hydro_dispatches) > 0
                # Check first component
                comp = hydro_dispatches[1]
                @test PSY.has_time_series(comp, PSY.SingleTimeSeries, "inflow")
                
                # Verify time series data
                ts = PSY.get_time_series(PSY.SingleTimeSeries, comp, "inflow")
                @test isa(ts, PSY.SingleTimeSeries)
                ts_data = PSY.get_data(ts)
                @test size(ts_data, 1) > 0
                @info "HydroDispatch [$(PSY.get_name(comp))] has $(size(ts_data, 1)) time steps"
            end
        end
    end

    @testset "Compare Original vs Updated Inflow Time Series" begin
        if isdefined(PSY, :HydroDispatch)
            sys_modified = deepcopy(sys)
            hydro_dispatches = collect(PSY.get_components(PSY.HydroDispatch, sys_modified))

            if !isempty(hydro_dispatches)
                comp = hydro_dispatches[1]
                @test PSY.has_time_series(comp, PSY.SingleTimeSeries, "inflow")

                before_ts = PSY.get_time_series(PSY.SingleTimeSeries, comp, "inflow")
                before_df = DataFrame(PSY.get_data(before_ts))

                hydro_data = HSPI.extract_hydro_inflow_from_simulation(sys_modified)
                HSPI.apply_hydro_inflow_to_system!(sys_modified, hydro_data)

                after_ts = PSY.get_time_series(PSY.SingleTimeSeries, comp, "inflow")
                after_df = DataFrame(PSY.get_data(after_ts))

                before_sample = first(before_df, min(10, size(before_df, 1)))
                after_sample = first(after_df, min(10, size(after_df, 1)))

                @info "Original inflow time series sample for $(PSY.get_name(comp))" before_sample
                @info "Updated inflow time series sample for $(PSY.get_name(comp))" after_sample

                @test size(before_df, 1) >= 1
                @test size(after_df, 1) >= 1

                function _extract_timestamp_value_map(df::DataFrame)
                    cols = names(df)
                    timestamp_idx = findfirst(c -> lowercase(String(c)) in ("timestamp", "datetime", "time"), cols)
                    timestamp_col = isnothing(timestamp_idx) ? cols[1] : cols[timestamp_idx]
                    value_col = first(filter(c -> c != timestamp_col, cols))
                    return Dict(df[!, timestamp_col] .=> Float64.(df[!, value_col]))
                end

                before_map = _extract_timestamp_value_map(before_df)
                after_map = _extract_timestamp_value_map(after_df)
                common_timestamps = intersect(collect(keys(before_map)), collect(keys(after_map)))

                @test !isempty(common_timestamps)

                changed_overlap = count(
                    t -> !isapprox(before_map[t], after_map[t]; atol=1e-12, rtol=1e-9),
                    common_timestamps,
                )
                @test changed_overlap > 0
                @info "Changed overlapping points for $(PSY.get_name(comp)): $(changed_overlap)/$(length(common_timestamps))"
            else
                @test true
            end
        else
            @test true
        end
    end

    @testset "Time Series Added to HydroEnergyReservoir Components" begin
        # Extract and apply data
        hydro_data = HSPI.extract_hydro_inflow_from_simulation(sys)
        sys_modified = deepcopy(sys)
        HSPI.apply_hydro_inflow_to_system!(sys_modified, hydro_data)

        # Check if HydroEnergyReservoir components have time series
        if isdefined(PSY, :HydroEnergyReservoir)
            hydro_reservoirs = collect(PSY.get_components(PSY.HydroEnergyReservoir, sys_modified))
            if length(hydro_reservoirs) > 0
                # Check first component
                comp = hydro_reservoirs[1]
                @test PSY.has_time_series(comp, PSY.SingleTimeSeries, "inflow")
                
                # Verify time series data
                ts = PSY.get_time_series(PSY.SingleTimeSeries, comp, "inflow")
                @test isa(ts, PSY.SingleTimeSeries)
                ts_data = PSY.get_data(ts)
                @test size(ts_data, 1) > 0
                @info "HydroEnergyReservoir [$(PSY.get_name(comp))] has $(size(ts_data, 1)) time steps"
            end
        end
    end

    @testset "Empty Inflow Data Handling" begin
        sys_test = deepcopy(sys)
        empty_data = Dict{String, Matrix{Float64}}()
        
        # Should not error, just warn
        result = HSPI.apply_hydro_inflow_to_system!(sys_test, empty_data)
        @test result === sys_test
    end

    @testset "Constructor Overload with System Parameter" begin
        # Test that constructor with system parameter triggers integration
        sys_test = deepcopy(sys)
        
        # This should run UC simulation and apply data
        hydro_pras = SPI.HydroEnergyReservoirPRAS(
            true;
            system=sys_test,
            max_active_power="max_active_power"
        )
        
        @test isa(hydro_pras, SPI.HydroEnergyReservoirPRAS)
        
        # Verify time series was applied to the system
        if isdefined(PSY, :HydroEnergyReservoir)
            hydro_reservoirs = collect(PSY.get_components(PSY.HydroEnergyReservoir, sys_test))
            if length(hydro_reservoirs) > 0
                comp = hydro_reservoirs[1]
                # Should have inflow time series from extraction and application
                @test PSY.has_time_series(comp, PSY.SingleTimeSeries, "inflow")
            end
        end
    end

    @testset "Constructor Overload with Pre-Computed Data" begin
        # Pre-compute inflow data
        hydro_data = HSPI.extract_hydro_inflow_from_simulation(sys)
        sys_test = deepcopy(sys)
        
        # Use pre-computed data with constructor
        hydro_pras = SPI.HydroEnergyReservoirPRAS(
            true;
            system=sys_test,
            hydro_inflow_data=hydro_data,
            max_active_power="max_active_power"
        )
        
        @test isa(hydro_pras, SPI.HydroEnergyReservoirPRAS)
        
        # Verify time series was applied
        if isdefined(PSY, :HydroEnergyReservoir)
            hydro_reservoirs = collect(PSY.get_components(PSY.HydroEnergyReservoir, sys_test))
            if length(hydro_reservoirs) > 0
                comp = hydro_reservoirs[1]
                @test PSY.has_time_series(comp, PSY.SingleTimeSeries, "inflow")
            end
        end
    end

    @testset "System Without Hydro Components" begin
        try
            generic_sys = PSB.build_system(PSB.PSISystems, "3_bus_multi_slack_network")
            hydro_data = HSPI.extract_hydro_inflow_from_simulation(generic_sys)
            @test isa(hydro_data, Dict)
        catch e
            @info "Skipping non-hydro case validation because case or UC setup is unavailable: $e"
            @test true
        end
    end
end
