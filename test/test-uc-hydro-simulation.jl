import Dates
import Logging

import HiGHS
import HydroPowerSimulations
import PowerSimulations
import PowerSystemCaseBuilder
import PowerSystems

const HPS = HydroPowerSimulations
const PSI = PowerSimulations
const PSB = PowerSystemCaseBuilder
const PSY = PowerSystems

@testset "UC Hydro Simulation Build" begin
    sys_uc = PSB.build_system(PSB.PSISystems, "5_bus_hydro_uc_sys")

    if isdefined(PSY, :transform_single_time_series!)
        PSY.transform_single_time_series!(sys_uc, Dates.Hour(24), Dates.Hour(24))
    end

    template_uc = PSI.ProblemTemplate(PSI.CopperPlatePowerModel)
    PSI.set_device_model!(template_uc, PSY.ThermalStandard, PSI.ThermalBasicUnitCommitment)
    PSI.set_device_model!(template_uc, PSY.PowerLoad, PSI.StaticPowerLoad)
    PSI.set_device_model!(template_uc, PSY.HydroDispatch, HPS.HydroDispatchRunOfRiver)
    PSI.set_device_model!(template_uc, PSY.HydroEnergyReservoir, HPS.HydroCommitmentReservoirStorage)
    models = PSI.SimulationModels([
        PSI.DecisionModel(
            template_uc,
            sys_uc;
            name = "UC",
            initialize_model = false,
            system_to_file = false,
            optimizer = HiGHS.Optimizer,
        ),
    ])

    sequence = PSI.SimulationSequence(;
        models = models,
        ini_cond_chronology = PSI.InterProblemChronology(),
    )

    sim = PSI.Simulation(;
        name = "test_uc_only",
        steps = 1,
        models = models,
        sequence = sequence,
        simulation_folder = mktempdir(; cleanup = true),
    )

    @test PSI.build!(sim; serialize = false) == PSI.SimulationBuildStatus.BUILT
    @test PSI.execute!(sim; enable_progress_bar = false) == PSI.RunStatus.SUCCESSFULLY_FINALIZED

    results = PSI.SimulationResults(sim)
    r_uc = PSI.get_decision_problem_results(results, "UC")

    uc_p_hy_dispatch = PSI.read_realized_variable(r_uc, "ActivePowerVariable__HydroDispatch")
    uc_p_hy_reservoir = PSI.read_realized_variable(r_uc, "ActivePowerVariable__HydroEnergyReservoir")
    uc_energy_hy = PSI.read_realized_aux_variable(r_uc, "HydroEnergyOutput__HydroEnergyReservoir")

    @test !isempty(uc_p_hy_dispatch)
    @test !isempty(uc_p_hy_reservoir)
    @test !isempty(uc_energy_hy)
end
