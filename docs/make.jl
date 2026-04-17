using Documenter
using HydroSiennaPRASInterface

makedocs(
    modules=[HydroSiennaPRASInterface],
    format=Documenter.HTML(prettyurls=haskey(ENV, "GITHUB_ACTIONS")),
    sitename="HydroSiennaPRASInterface.jl",
    pages=["Home" => "index.md"],
)
