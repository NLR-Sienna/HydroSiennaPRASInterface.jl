"""
hydro_planning_overloads.jl

Method overloads to extend hydro-focused SiennaPRASInterface constructors with
an additional `hydro_planning::Bool` argument.
"""

"""
    SPI.GeneratorPRAS(hydro_planning::Bool; kwargs...)

Hydro-planning overload for `GeneratorPRAS` that preserves original constructor
behavior and adds a first positional `hydro_planning::Bool` flag.
"""
function SPI.GeneratorPRAS(hydro_planning::Bool; kwargs...)
    if hydro_planning
        @info "GeneratorPRAS: hydro planning enabled"
    else
        @info "GeneratorPRAS: hydro planning disabled"
    end

    return SPI.GeneratorPRAS(; kwargs...)
end

"""
    SPI.HydroEnergyReservoirPRAS(hydro_planning::Bool; kwargs...)

Hydro-focused overload that preserves original constructor behavior while adding
`hydro_planning::Bool` as the first positional argument.

# Returns
- A `SiennaPRASInterface.HydroEnergyReservoirPRAS` instance

# Example
```julia
SPI.HydroEnergyReservoirPRAS(true)
SPI.HydroEnergyReservoirPRAS(true; max_active_power="max_active_POWER")
```
"""
function SPI.HydroEnergyReservoirPRAS(hydro_planning::Bool; kwargs...)
    if hydro_planning
        @info "HydroEnergyReservoirPRAS: hydro planning enabled"
    else
        @info "HydroEnergyReservoirPRAS: hydro planning disabled"
    end

    return SPI.HydroEnergyReservoirPRAS(; kwargs...)
end

if isdefined(SPI, :EnergyReservoirSoC)
    """
        SPI.EnergyReservoirSoC(hydro_planning::Bool; kwargs...)

    Hydro-planning overload for `EnergyReservoirSoC` (only defined when
    `SiennaPRASInterface` exposes this constructor in the current version).
    """
    @eval function SPI.EnergyReservoirSoC(hydro_planning::Bool; kwargs...)
        if hydro_planning
            @info "EnergyReservoirSoC: hydro planning enabled"
        else
            @info "EnergyReservoirSoC: hydro planning disabled"
        end

        return SPI.EnergyReservoirSoC(; kwargs...)
    end
end

