"""
check_hydro_results.jl

Unified check script for hydro simulation results.

Configure the two variables at the top of the script:
    check_mode   = "target"  # or "budget"
    output_folder = "Water_weekly_target_hourly_target"  # or "Water_daily_budget_hourly_budget"

TARGET mode
-----------
For each reservoir and each day, verifies that the end-of-day head (m) from
the hourly simulation matches the target passed down from the medium-term model,
accounting for shortage/surplus slack variables:

    head[t_end] + shortage[t_end] - surplus[t_end] ≈ target   (tol = 0.01 m)

Prints a per-reservoir summary (pass rate, max deviation) and lists any violated days.

BUDGET mode
-----------
For each reservoir and each month, computes:
    - Budget cap (m³/s-steps/day) = WaterBudgetTimeSeriesParameter × 24
    - Turbine Q (m³/s-steps/day) = Σ_t  P_t(MW) / K_unit  summed over 24 h per day
    - Utilization (%) = turbine_Q / budget_cap × 100

K factors (MW per m³/s) are derived from the rated head/discharge per turbine unit.
Monthly averages are printed per reservoir.
"""

using CSV, DataFrames, Dates, Statistics, Printf, Plots

# ─────────────────────────────────────────────────────────────────────────────
# ▶  CONFIGURATION — edit here
# ─────────────────────────────────────────────────────────────────────────────
check_mode    = "budget"    # "target"  or  "budget"
output_folder = "Water_daily_budget_hourly_budget"
                # "Water_daily_target_hourly_target"  for target mode
                # "Water_weekly_target_hourly_target"  for target mode

tol = 0.01  # (target mode) acceptable head deviation in metres
# ─────────────────────────────────────────────────────────────────────────────

# Resolve repo root whether run as a script (scripts/) or from REPL (repo root)
const RESULTS_DIR = let
    # When run as a script: @__DIR__ = scripts/, repo root is one level up
    # When included from REPL: @__DIR__ = pwd() = repo root
    _d = @__DIR__
    _candidate = isfile(joinpath(_d, "Project.toml")) ? _d : dirname(_d)
    joinpath(_candidate, "results")
end

# K factors: MW per (m³/s) for each named turbine unit
const K_PER_UNIT = Dict(
    "Chalillo_U1" => 3.94  / 8.928,
    "Chalillo_U2" => 3.94  / 8.928,
    "Mollejon_U1" => 9.70  / 8.482,
    "Mollejon_U2" => 9.70  / 8.482,
    "Vaca_U1"     => 9.00  / 19.231,
    "Vaca_U2"     => 9.00  / 19.231,
    "Vaca_U3"     => 1.00  / 2.143,
)

# Map turbine unit name → reservoir name  (strip trailing "_U<n>")
unit_to_reservoir(unit::String) = replace(unit, r"_U\d+$" => "") * "_Reservoir"

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

function load_long(path::String)
    df = CSV.read(path, DataFrame)
    df[!, :DateTime] = DateTime.(replace.(string.(df.DateTime), r"\.\d+$" => ""))
    return df
end

function pivot_wide(df::DataFrame)
    return unstack(df, :DateTime, :name, :value)
end

# ─────────────────────────────────────────────────────────────────────────────
# TARGET CHECK
# ─────────────────────────────────────────────────────────────────────────────

function run_target_check(daily_dir, hourly_dir=nothing)
    # TARGET = daily med-term optimized head trajectory
    target_long = load_long(joinpath(daily_dir, "HydroReservoirHeadVariable_HydroReservoir.csv"))

    # ACTUAL = hourly head + slack variables (use daily_dir if no separate hourly_dir given)
    _hdir       = isnothing(hourly_dir) ? daily_dir : hourly_dir
    head_df     = pivot_wide(load_long(joinpath(_hdir, "HydroReservoirHeadVariable_HydroReservoir.csv")))
    shortage_df = pivot_wide(load_long(joinpath(_hdir, "HydroWaterShortageVariable_HydroReservoir.csv")))
    surplus_df  = pivot_wide(load_long(joinpath(_hdir, "HydroWaterSurplusVariable_HydroReservoir.csv")))

    reservoirs = setdiff(names(head_df), ["DateTime"])
    timestamps = head_df[!, :DateTime]

    # Check only the last timestamp of each calendar day (end-of-day)
    dates_unique = unique(Date.(timestamps))
    check_timestamps = [last(filter(t -> Date(t) == d, timestamps)) for d in dates_unique]

    rows = NamedTuple[]
    for res in reservoirs
        target_res = sort(filter(r -> r.name == res, target_long), :DateTime)

        for ts in check_timestamps
            d   = Date(ts)
            i   = findfirst(==(ts), timestamps)
            isnothing(i) && continue

            head_val     = head_df[i, res]
            shortage_val = shortage_df[i, res]
            surplus_val  = surplus_df[i, res]
            head_eff     = head_val + shortage_val - surplus_val

            # Match target: last daily entry with DateTime ≤ this timestamp
            valid_targets = filter(r -> r.DateTime <= ts, target_res)
            isempty(valid_targets) && continue
            tgt_val = last(sort(valid_targets, :DateTime)).value

            dev = head_eff - tgt_val
            push!(rows, (
                reservoir      = res,
                date           = d,
                head_actual    = head_val,
                shortage       = shortage_val,
                surplus        = surplus_val,
                head_effective = head_eff,
                target         = tgt_val,
                deviation      = dev,
                met            = abs(dev) <= tol,
            ))
        end
    end

    df = DataFrame(rows)

    println("\n", "="^72)
    println("  TARGET CHECK — end-of-day head vs medium-term target  (tol=$(tol) m)")
    println("="^72)
    for res in sort(unique(df.reservoir))
        sub = filter(r -> r.reservoir == res, df)
        n_met = count(sub.met)
        n_tot = nrow(sub)
        max_dev = maximum(abs.(sub.deviation))
        @printf("  %-32s  %3d/%3d days met  |  max |dev| = %.4f m\n",
                res, n_met, n_tot, max_dev)
        violated = filter(r -> !r.met, sub)
        if nrow(violated) > 0
            println("    Violated days:")
            for row in eachrow(violated)
                @printf("      %s  head_eff=%7.3f  target=%7.3f  dev=%+.4f  shortage=%.3f  surplus=%.3f\n",
                        row.date, row.head_effective, row.target, row.deviation,
                        row.shortage, row.surplus)
            end
        end
    end
    println("="^72, "\n")
    return df
end

function plot_target_check(check_df::DataFrame, plots_dir::String, output_folder_path::String)
    # TARGET = daily optimized head from med-term
    daily_dir    = isdir(joinpath(output_folder_path, "daily")) ? joinpath(output_folder_path, "daily") : joinpath(output_folder_path, "weekly")
    target_long  = load_long(joinpath(daily_dir, "HydroReservoirHeadVariable_HydroReservoir.csv"))

    # ACTUAL = hourly head/shortage/surplus
    hourly_dir   = joinpath(output_folder_path, "hourly")
    hourly_head  = load_long(joinpath(hourly_dir, "HydroReservoirHeadVariable_HydroReservoir.csv"))
    hourly_short = load_long(joinpath(hourly_dir, "HydroWaterShortageVariable_HydroReservoir.csv"))
    hourly_surpl = load_long(joinpath(hourly_dir, "HydroWaterSurplusVariable_HydroReservoir.csv"))

    timestamps    = sort(unique(hourly_head.DateTime))
    hours_per_day = 24
    n_daily       = length(timestamps) ÷ hours_per_day
    day_ends      = [timestamps[i * hours_per_day] for i in 1:n_daily]

    reservoirs = sort(unique(check_df.reservoir))
    for res in reservoirs
        h   = sort(filter(r -> r.name == res, hourly_head),  :DateTime)
        sho = sort(filter(r -> r.name == res, hourly_short), :DateTime)
        sur = sort(filter(r -> r.name == res, hourly_surpl), :DateTime)
        tgt_res = sort(filter(r -> r.name == res, target_long), :DateTime)

        # Staircase from daily optimized head trajectory
        stair_t = vcat(tgt_res.DateTime, [last(tgt_res.DateTime) + Day(1)])
        stair_v = vcat(tgt_res.value,    [last(tgt_res.value)])

        # End-of-day markers
        ok_t = DateTime[];   ok_v  = Float64[]
        bad_t = DateTime[];  bad_v = Float64[]

        for t_end in day_ends
            h_row   = filter(r -> r.DateTime == t_end, h)
            sho_row = filter(r -> r.DateTime == t_end, sho)
            sur_row = filter(r -> r.DateTime == t_end, sur)
            isempty(h_row) && continue
            head_val = h_row[1, :value]
            sho_val  = isempty(sho_row) ? 0.0 : sho_row[1, :value]
            sur_val  = isempty(sur_row) ? 0.0 : sur_row[1, :value]
            # Active target: last daily entry with DateTime ≤ t_end
            valid = filter(r -> r.DateTime <= t_end, tgt_res)
            isempty(valid) && continue
            tgt_val = last(valid).value
            dev     = head_val + sho_val - sur_val - tgt_val
            if abs(dev) <= tol
                push!(ok_t, t_end);  push!(ok_v,  head_val)
            else
                push!(bad_t, t_end); push!(bad_v, head_val)
            end
        end

        p = plot(
            size = (1200, 450), title = "$res — Hourly Head vs Daily Target",
            xlabel = "Date", ylabel = "Head (m)", legend = :outertopright,
            margins = (5, :mm),
        )
        plot!(p, h.DateTime, h.value;
            label = "Hourly head", color = "#2980b9", linewidth = 1.2, alpha = 0.85)
        plot!(p, stair_t, stair_v;
            label = "Daily target (med-term)", color = "#c0392b",
            linewidth = 2.0, linestyle = :dash, seriestype = :steppost)
        if !isempty(ok_t)
            scatter!(p, ok_t, ok_v;
                label = "Day-end: met", color = :green,
                markershape = :circle, markersize = 5, markerstrokewidth = 0)
        end
        if !isempty(bad_t)
            scatter!(p, bad_t, bad_v;
                label = "Day-end: MISS", color = :red,
                markershape = :x, markersize = 6, markerstrokewidth = 2)
        end

        path = joinpath(plots_dir, "head_target_check_$(res).png")
        savefig(p, path)
        println("Saved: $path")
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# BUDGET CHECK
# ─────────────────────────────────────────────────────────────────────────────

function run_budget_check(daily_dir)
    budget_long  = load_long(joinpath(daily_dir, "WaterBudgetTimeSeriesParameter_HydroReservoir.csv"))
    turbine_long = load_long(joinpath(daily_dir, "ActivePowerVariable_HydroTurbine.csv"))

    # Convert turbine power → flow rate (m³/s) per unit, then sum by reservoir
    turbine_long[!, :reservoir] = unit_to_reservoir.(String.(turbine_long.name))
    turbine_long[!, :Q_m3s]     = [
        row.value / get(K_PER_UNIT, String(row.name), NaN)
        for row in eachrow(turbine_long)
    ]

    # Daily results: one row per day.  Convert Q (m³/s average) → m³/s-steps/day (×24)
    # and budget parameter (stored as B_csv/24) → daily cap (×24).
    turbine_long[!, :date] = Date.(turbine_long.DateTime)
    budget_long[!, :date]  = Date.(budget_long.DateTime)

    turbine_daily = combine(
        groupby(turbine_long, [:date, :reservoir]),
        :Q_m3s => (q -> sum(q) * 24) => :turbine_Q_daily,   # sum units × 24 steps/day
    )

    # Budget parameter stored as B_csv/24; recover daily cap by ×24
    budget_daily = combine(
        groupby(budget_long, [:date, :name]),
        :value => (v -> first(v) * 24) => :budget_cap_daily,
    )
    DataFrames.rename!(budget_daily, :name => :reservoir)

    merged = innerjoin(turbine_daily, budget_daily; on = [:date, :reservoir])
    merged[!, :utilization_pct] = merged.turbine_Q_daily ./ merged.budget_cap_daily .* 100.0
    merged[!, :month] = Dates.month.(merged.date)

    println("\n", "="^80)
    println("  BUDGET CHECK — monthly turbine Q vs daily budget cap")
    println("  Units: m³/s-steps/day  |  Utilization = turbine_Q / budget_cap × 100%")
    println("="^80)

    for res in sort(unique(merged.reservoir))
        sub = filter(r -> r.reservoir == res, merged)
        println("\n  Reservoir: $res")
        @printf("  %6s  %12s  %12s  %8s\n", "Month", "Budget cap", "Turbine Q", "Util %")
        println("  ", "-"^44)
        for m in 1:12
            msub = filter(r -> r.month == m, sub)
            isempty(msub) && continue
            cap  = mean(msub.budget_cap_daily)
            qval = mean(msub.turbine_Q_daily)
            util = mean(msub.utilization_pct)
            @printf("  %6d  %12.3f  %12.3f  %7.1f%%\n", m, cap, qval, util)
        end
        ann_cap  = mean(sub.budget_cap_daily)
        ann_q    = mean(sub.turbine_Q_daily)
        ann_util = mean(sub.utilization_pct)
        println("  ", "-"^44)
        @printf("  %6s  %12.3f  %12.3f  %7.1f%%\n", "Annual", ann_cap, ann_q, ann_util)
    end
    println("\n", "="^80, "\n")
    return merged
end

function plot_budget_check(df::DataFrame, plots_dir::String, daily_dir::String)
    # Load inflow and volume for the Chalillo 3-panel seasonal plot
    inflow_long = load_long(joinpath(daily_dir, "InflowTimeSeriesParameter_HydroReservoir.csv"))
    vol_long    = load_long(joinpath(daily_dir, "HydroReservoirVolumeVariable_HydroReservoir.csv"))

    reservoirs = sort(unique(df.reservoir))
    for res in reservoirs
        sub = sort(filter(r -> r.reservoir == res, df), :date)
        dates = sub.date

        # Budget cap stored as B_csv/24; display as m³/s (the per-step rate)
        bud_m3s = sub.budget_cap_daily ./ 24
        q_m3s   = sub.turbine_Q_daily  ./ 24

        inf_res = sort(filter(r -> r.name == res, inflow_long), :DateTime)
        inf_vals = [let rows = filter(r -> Date(r.DateTime) == d, inf_res)
                        isempty(rows) ? NaN : first(rows).value
                    end for d in dates]

        vol_res  = sort(filter(r -> r.name == res, vol_long), :DateTime)
        vol_vals = [let rows = filter(r -> Date(r.DateTime) == d, vol_res)
                        isempty(rows) ? NaN : first(rows).value
                    end for d in dates]

        net = q_m3s .- inf_vals

        # Panel 1: turbine Q vs budget cap vs inflow
        p1 = plot(dates, inf_vals;
            label = "Inflow (m³/s)", color = "#5dade2", linewidth = 1.5,
            ylabel = "m³/s",
            title  = "$res — Daily model: seasonal budget effect",
            legend = :topright, left_margin = 8Plots.mm)
        plot!(p1, dates, bud_m3s;
            label = "Budget cap B_csv/24 (m³/s)", color = "#e91e8c",
            linewidth = 2.0, linestyle = :dash)
        plot!(p1, dates, q_m3s;
            label = "Turbine Q (m³/s)", color = "#2c3e9e", linewidth = 1.5, alpha = 0.85)

        # Panel 2: net fill/draw
        p2 = plot(; ylabel = "m³/s", legend = :topright, left_margin = 8Plots.mm,
            title = "Turbine Q − Inflow  (+ drawing reservoir, − filling)")
        fill_pos = copy(net); fill_pos[fill_pos .< 0] .= 0
        fill_neg = copy(net); fill_neg[fill_neg .>= 0] .= 0
        plot!(p2, dates, fill_pos; fillrange = 0, fillalpha = 0.6,
            color = "#e67e22", label = "Drawing stored water")
        plot!(p2, dates, fill_neg; fillrange = 0, fillalpha = 0.6,
            color = "#2980b9", label = "Filling reservoir")
        hline!(p2, [0.0]; color = :black, linewidth = 0.8, label = "")

        # Panel 3: reservoir volume
        p3 = plot(vol_res.DateTime, vol_res.value;
            label = "Volume (km³)", color = "#117864", linewidth = 1.8,
            ylabel = "km³", xlabel = "Date", legend = :topright, left_margin = 8Plots.mm)
        hline!(p3, [0.800]; color = :red, linewidth = 0.8, linestyle = :dash,
            alpha = 0.5, label = "Max capacity (0.800 km³)")

        p = plot(p1, p2, p3;
            layout = (3, 1), size = (1300, 900),
            plot_title = "",
        )
        path = joinpath(plots_dir, "daily_seasonal_budget_check_$(res).png")
        savefig(p, path)
        println("Saved: $path")
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────────────────────────────────────

# Use "daily/" if it exists (budget run), otherwise fall back to "weekly/" (target run)
_subdir   = isdir(joinpath(RESULTS_DIR, output_folder, "daily")) ? "daily" : "weekly"
daily_dir = joinpath(RESULTS_DIR, output_folder, _subdir)
isdir(daily_dir) || error("med-term results not found (tried daily/ and weekly/): $(joinpath(RESULTS_DIR, output_folder))")

plots_dir = joinpath(RESULTS_DIR, output_folder, "plots")
mkpath(plots_dir)

if check_mode == "target"
    hourly_dir_st = joinpath(RESULTS_DIR, output_folder, "hourly")
    result_df = run_target_check(daily_dir, hourly_dir_st)
    plot_target_check(result_df, plots_dir, joinpath(RESULTS_DIR, output_folder))

elseif check_mode == "budget"
    result_df = run_budget_check(daily_dir)
    plot_budget_check(result_df, plots_dir, daily_dir)

else
    error("Unknown check_mode: \"$check_mode\". Use \"target\" or \"budget\".")
end
