"""
HydroSiennaPRASInterface

Extension package to SiennaPRASInterface to enable exchange of data between 
hydro planning and resource adequacy analysis.
"""
module HydroSiennaPRASInterface

export greet

"""
    greet()

A simple greeting function to verify the module is working.
"""
function greet()
    println("Hello from HydroSiennaPRASInterface!")
end

end # module
