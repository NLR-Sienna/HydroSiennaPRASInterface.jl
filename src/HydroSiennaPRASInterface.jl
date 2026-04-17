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
```
"""
module HydroSiennaPRASInterface

import PowerSystems
import SiennaPRASInterface

const PSY = PowerSystems
const SPI = SiennaPRASInterface

# This module extends SPI.HydroEnergyReservoirPRAS with the hydro_planning parameter
# No explicit exports needed - the overloads are automatically available
# when both packages are loaded

include("hydro_planning_overloads.jl")

"""
    greet()

A simple greeting function to verify the module is working.
"""
function greet()
    println("Hello from HydroSiennaPRASInterface!")
end

end # module
