using HydroSiennaPRASInterface
using Test
import Aqua

@testset "Aqua.jl" begin
    Aqua.test_unbound_args(HydroSiennaPRASInterface)
    Aqua.test_undefined_exports(HydroSiennaPRASInterface)
    Aqua.test_ambiguities(HydroSiennaPRASInterface)
    Aqua.test_deps_compat(HydroSiennaPRASInterface; check_extras=false)
end

@testset "All tests" begin
    for (root, _, files) in walkdir(@__DIR__)
        for file in files
            if isnothing(match(r"^test.*\.jl$", file))
                continue
            end
            title = titlecase(replace(splitext(file[6:end])[1], "-" => " "))
            @testset "$title" begin
                include(joinpath(root, file))
            end
        end
    end
end
