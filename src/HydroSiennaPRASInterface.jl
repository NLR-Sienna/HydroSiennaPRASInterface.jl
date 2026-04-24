"""
HydroSiennaPRASInterface

Extension package to SiennaPRASInterface that adds hydro planning capabilities
via hydro-focused method overloads to existing SiennaPRASInterface functions.

When you import both SiennaPRASInterface and HydroSiennaPRASInterface, you can call
the same hydro constructor with an additional `hydro_planning::Bool` parameter.

# Example
```julia
import SiennaPRASInterface as SPI
using HydroSiennaPRASInterface

# Original call (without hydro planning)
SPI.HydroEnergyReservoirPRAS()

# New call (with hydro planning enabled)
SPI.HydroEnergyReservoirPRAS(true)

# With UC simulation to extract hydro inflow data
sys = PSB.build_system(PSB.PSISystems, "5_bus_hydro_uc_sys")
hydro_data = extract_hydro_inflow_from_simulation(sys)
SPI.HydroEnergyReservoirPRAS(true, hydro_inflow_data=hydro_data; ...)
```
"""
module HydroSiennaPRASInterface

import HiGHS
import PowerSystems
import SiennaPRASInterface
import HydroPowerSimulations
import PowerSimulations
import PowerSystemCaseBuilder
import DataFrames
using Dates

const PSY = PowerSystems
const SPI = SiennaPRASInterface
const HPS = HydroPowerSimulations
const PSI = PowerSimulations
const PSB = PowerSystemCaseBuilder
const DataFrame = DataFrames.DataFrame

# Export the hydro planning extraction and integration functions
export extract_hydro_inflow_from_simulation, apply_hydro_inflow_to_system!

# This module extends SPI constructors with the hydro_planning parameter
# The overloaded methods are automatically available when both packages are loaded

include("hydro_planning_overloads.jl")

"""
    greet()

A simple greeting function to verify the module is working.
"""
function greet()
    println("Hello from HydroSiennaPRASInterface!")
end

end # module
