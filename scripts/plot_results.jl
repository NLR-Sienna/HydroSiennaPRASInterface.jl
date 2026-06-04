using CSV, DataFrames, Dates, Plots
using PowerSystems
const PSY = PowerSystems

weekly_model_type      = "target"  # "target" or "budget"
hourly_model_type      = "target" # "target" or "budget"
hydro_model_type        = "Water"  # "Energy" or "Water"
weekly_hydro_model_type = hydro_model_type  # "Energy" or "Water"
hourly_hydro_model_type = hydro_model_type  # "Energy" or "Water"
plots_folder = "$(weekly_hydro_model_type)_weekly_$(weekly_model_type)_hourly_$(hourly_model_type)"
# ── Paths ─────────────────────────────────────────────────────────────────────
const WEEKLY_DIR = joinpath(@__DIR__, "..", "results", "$(hydro_model_type)_weekly_$(weekly_model_type)_hourly_$(hourly_model_type)", "weekly")
const HOURLY_DIR = joinpath(@__DIR__, "..", "results", "$(hydro_model_type)_weekly_$(weekly_model_type)_hourly_$(hourly_model_type)", "hourly")
const PLOTS_DIR  = joinpath(@__DIR__, "..", "results", "plots", plots_folder)

if !isdir(PLOTS_DIR)
    mkpath(PLOTS_DIR)
end

# ── Hydro parameter key / label: depends on reservoir model (Energy vs Water) ─
function _param_key(model_type::String, hydro_model::String)
    prefix = hydro_model == "Energy" ? "Energy" : "Water"
    suffix = model_type == "target" ? "Target" : "Budget"
    return "$(prefix)$(suffix)TimeSeriesParameter_HydroReservoir"
end
_param_label(model_type::String, hydro_model::String) =
    (hydro_model == "Energy" ? "Energy " : "") * (model_type == "target" ? "Target" : "Budget")

const WEEKLY_PARAM_KEY   = _param_key(weekly_model_type, weekly_hydro_model_type)
const HOURLY_PARAM_KEY   = _param_key(hourly_model_type, hourly_hydro_model_type)
const WEEKLY_PARAM_LABEL = _param_label(weekly_model_type, weekly_hydro_model_type)
const HOURLY_PARAM_LABEL = _param_label(hourly_model_type, hourly_hydro_model_type)

const RESERVOIRS = ["Mollejon_Reservoir", "Vaca_Reservoir", "Chalillo_Reservoir"]
const TURBINES   = ["Mollejon_U1", "Mollejon_U2",
                    "Vaca_U1",     "Vaca_U2",    "Vaca_U3",
                    "Chalillo_U1", "Chalillo_U2"]

# ── Helpers ───────────────────────────────────────────────────────────────────
function load_csv(dir::String, name::String)
    df = CSV.read(joinpath(dir, name * ".csv"), DataFrame)
    if !(eltype(df.DateTime) <: DateTime)
        df.DateTime = DateTime.(first.(split.(string.(df.DateTime), ".")))
    end
    sort!(df, [:name, :DateTime])
    return df
end

function series(df::DataFrame, component::String)
    mask = df.name .== component
    return df.DateTime[mask], df.value[mask]
end

const COLOR_HOURLY = colorant"#2980b9"   # bright blue
const COLOR_WEEKLY = colorant"#c0392b"   # bright red

function plot_series!(p, wdf, hdf, component, wlabel, hlabel=wlabel)
    wt, wv = series(wdf, component)
    ht, hv = series(hdf, component)
    plot!(p, ht, hv; label="$hlabel (hourly)", linestyle=:solid, color=COLOR_HOURLY, linewidth=1.5, alpha=0.8)
    plot!(p, wt, wv; label="$wlabel (weekly)", linestyle=:dash,  color=COLOR_WEEKLY, linewidth=2.0)
end

# ── Load data ─────────────────────────────────────────────────────────────────
const SHARED_CSV_KEYS = [
    "EnergyVariable_HydroReservoir",
    "InflowTimeSeriesParameter_HydroReservoir",
    "WaterSpillageVariable_HydroReservoir",
    "HydroEnergyShortageVariable_HydroReservoir",
    "HydroEnergySurplusVariable_HydroReservoir",
    "ActivePowerVariable_HydroTurbine",
    "OnVariable_HydroTurbine",
]

println("Loading CSV data...")
_existing(dir, keys) = filter(k -> isfile(joinpath(dir, k * ".csv")), keys)
W = Dict(k => load_csv(WEEKLY_DIR, k) for k in _existing(WEEKLY_DIR, [SHARED_CSV_KEYS; WEEKLY_PARAM_KEY]))
H = Dict(k => load_csv(HOURLY_DIR, k) for k in _existing(HOURLY_DIR, [SHARED_CSV_KEYS; HOURLY_PARAM_KEY]))
println("Data loaded.\n")

# ── Reservoir metadata (requires PowerSystems system) ────────────────────────
const SYS_PATH = joinpath(@__DIR__, "..", "models", "sys_weekly.json")
const BASE_POWER, RESERVOIR_TURBINES, RESERVOIR_CAPACITY = let
    sys = PSY.System(SYS_PATH; time_series_read_only = true)
    bp  = PSY.get_base_power(sys)
    turbines = Dict(
        PSY.get_name(res) => PSY.get_name.(PSY.get_downstream_turbines(res))
        for res in PSY.get_components(PSY.HydroReservoir, sys)
    )
    capacity = Dict(
        PSY.get_name(res) => PSY.get_storage_level_limits(res).max
        for res in PSY.get_components(PSY.HydroReservoir, sys)
    )
    bp, turbines, capacity
end

# ── Grid panel builder ────────────────────────────────────────────────────────
# vars: vector of (weekly_key, hourly_key, weekly_label, hourly_label, ylabel) tuples.
function grid_panels(vars)
    n_vars = length(vars)
    panels = []
    for res in RESERVOIRS
        for (wkey, hkey, wlabel, hlabel, ylabel_str) in vars
            panel_label = wlabel == hlabel ? wlabel : "$wlabel/$hlabel"
            title_str = n_vars > 1 ?
                "$(replace(res, "_" => " ")) — $panel_label" :
                replace(res, "_" => " ")
            p = plot(; title=title_str, ylabel=ylabel_str,
                       titlefontsize=8, legend=:outertopright,
                       legendfontsize=6, xrotation=30)
            haskey(W, wkey) && haskey(H, hkey) && plot_series!(p, W[wkey], H[hkey], res, wlabel, hlabel)
            push!(panels, p)
        end
    end
    return panels
end

# ── Figure 1: Reservoir Volume + Hydro Parameter — 2 columns ─────────────────
println("Plotting reservoir volume + hydro parameter...")
param_title = WEEKLY_PARAM_LABEL == HOURLY_PARAM_LABEL ?
    WEEKLY_PARAM_LABEL :
    "$(WEEKLY_PARAM_LABEL)/$(HOURLY_PARAM_LABEL)"
panels1 = grid_panels([
    ("EnergyVariable_HydroReservoir", "EnergyVariable_HydroReservoir", "Energy",           "Energy",           "Energy [p.u.]"),
    (WEEKLY_PARAM_KEY,                HOURLY_PARAM_KEY,                WEEKLY_PARAM_LABEL, HOURLY_PARAM_LABEL, "Parameter [p.u.]"),
])
fig1 = plot(panels1...; layout=(3, 2), size=(1400, 900), dpi=150,
            plot_title="Reservoir Volume & $param_title")
savefig(fig1, joinpath(PLOTS_DIR, "reservoir_volume.png"))
println("  → reservoir_volume.png")

# ── Figure 2: Reservoir Inflow ────────────────────────────────────────────────
println("Plotting reservoir inflow...")
panels2 = grid_panels([
    ("InflowTimeSeriesParameter_HydroReservoir", "InflowTimeSeriesParameter_HydroReservoir", "Inflow", "Inflow", "Flow [p.u.]"),
])
fig2 = plot(panels2...; layout=(3, 1), size=(900, 900), dpi=150,
            plot_title="Reservoir Inflow")
savefig(fig2, joinpath(PLOTS_DIR, "reservoir_inflow.png"))
println("  → reservoir_inflow.png")

# ── Figure 3: Spillage / Shortage / Surplus — 3 columns ──────────────────────
println("Plotting reservoir spillage / shortage / surplus...")
panels3 = grid_panels([
    ("WaterSpillageVariable_HydroReservoir",       "WaterSpillageVariable_HydroReservoir",       "Spillage", "Spillage", "Water [p.u.]"),
    ("HydroEnergyShortageVariable_HydroReservoir", "HydroEnergyShortageVariable_HydroReservoir", "Shortage", "Shortage", "Energy [p.u.]"),
    ("HydroEnergySurplusVariable_HydroReservoir",  "HydroEnergySurplusVariable_HydroReservoir",  "Surplus",  "Surplus",  "Energy [p.u.]"),
])
fig3 = plot(panels3...; layout=(3, 3), size=(1600, 900), dpi=150,
            plot_title="Reservoir Spillage, Shortage & Surplus")
savefig(fig3, joinpath(PLOTS_DIR, "reservoir_spillage_shortage_surplus.png"))
println("  → reservoir_spillage_shortage_surplus.png")

# ── Figure 4: Turbine Active Power ────────────────────────────────────────────
println("Plotting turbine active power...")
turb_key = "ActivePowerVariable_HydroTurbine"
turb_panels = map(TURBINES) do t
    p = plot(; title=replace(t, "_" => " "), ylabel="Power [MW]",
               titlefontsize=9, legend=:topright, legendfontsize=6, xrotation=30)
    plot_series!(p, W[turb_key], H[turb_key], t, "Power")
    p
end

# Pad to fill the 4×2 grid (8 slots for 7 turbines)
push!(turb_panels, plot(; framestyle=:none, legend=false))

fig4 = plot(turb_panels...; layout=(4, 2), size=(1200, 1100), dpi=150,
            plot_title="Turbine Active Power")
savefig(fig4, joinpath(PLOTS_DIR, "turbine_active_power.png"))
println("  → turbine_active_power.png")

# ── Figure 5: Budget vs turbine power (weekly budget only) ───────────────────
if weekly_model_type == "budget"
    println("Plotting weekly budget vs turbine output power...")

    turb_power_df = W["ActivePowerVariable_HydroTurbine"]
    budget_df     = W[WEEKLY_PARAM_KEY]

    budget_panels = map(RESERVOIRS) do res
        turbines = get(RESERVOIR_TURBINES, res, String[])
        cap      = get(RESERVOIR_CAPACITY, res, 1.0)

        bt, bv = series(budget_df, res)

        # Energy model: CSV already in natural units (fraction × cap, comparable to MW)
        # Water model:  CSV stores raw m³/s → needs separate axis
        if weekly_hydro_model_type == "Energy"
            budget_scaled = bv
            budget_label  = "Budget (cap=$(round(cap; digits=1)))"
        else
            budget_scaled = bv
            budget_label  = "Budget [m³/s]"
        end

        p = plot(; title = replace(res, "_" => " "),
                   titlefontsize = 9, legend = :outertopright,
                   legendfontsize = 7, xrotation = 30)

        # Individual turbine active powers (thin auto-coloured lines)
        for turb in turbines
            tt, tv = series(turb_power_df, turb)
            plot!(p, tt, tv;
                  label     = replace(turb, "_" => " "),
                  linestyle = :solid,
                  linewidth = 1.0,
                  alpha     = 0.6)
        end

        # Sum of downstream turbines (thick blue line)
        turb_mask   = in.(turb_power_df.name, Ref(turbines))
        turb_subset = turb_power_df[turb_mask, :]
        turb_sum    = combine(groupby(turb_subset, :DateTime), :value => sum => :value)
        sort!(turb_sum, :DateTime)

        if weekly_hydro_model_type == "Energy"
            # Single axis: budget and turbine power both in MW
            plot!(p, turb_sum.DateTime, turb_sum.value;
                  label     = "Total output",
                  linestyle = :solid,
                  color     = COLOR_HOURLY,
                  linewidth = 2.5,
                  ylabel    = "Power [MW]")
            plot!(p, bt, budget_scaled;
                  label     = budget_label,
                  linestyle = :dash,
                  color     = COLOR_WEEKLY,
                  linewidth = 2.0)
        else
            # Dual axis: turbine power [MW] left, budget [m³/s] right
            plot!(p, turb_sum.DateTime, turb_sum.value;
                  label     = "Total output",
                  linestyle = :solid,
                  color     = COLOR_HOURLY,
                  linewidth = 2.5,
                  ylabel    = "Power [MW]")
            plot!(twinx(p), bt, budget_scaled;
                  label     = budget_label,
                  linestyle = :dash,
                  color     = COLOR_WEEKLY,
                  linewidth = 2.0,
                  ylabel    = "Flow [m³/s]",
                  legend    = :topleft,
                  legendfontsize = 7)
        end

        p
    end

    fig6 = plot(budget_panels...; layout=(length(RESERVOIRS), 1),
                size=(1100, 350 * length(RESERVOIRS)), dpi=150,
                plot_title="Weekly Budget vs Turbine Output Power ($weekly_hydro_model_type model)")
    savefig(fig6, joinpath(PLOTS_DIR, "weekly_budget_vs_turbine_power.png"))
    println("  → weekly_budget_vs_turbine_power.png")
end

println("\nAll plots saved to: $PLOTS_DIR")
