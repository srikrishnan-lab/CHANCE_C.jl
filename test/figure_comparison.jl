### Recreate key figures from Yoon et al., 2023 ###
import Pkg
Pkg.activate(dirname(@__DIR__))
Pkg.instantiate()

include(joinpath(dirname(@__DIR__), "src/CHANCE_C.jl"))
using .CHANCE_C #add period since module is local to repository
using CSV, DataFrames


## Load input Data
balt_base = DataFrame(CSV.File(joinpath(dirname(pwd()), "baltimore-data/model_inputs/surge_area_baltimore_base.csv")))
balt_levee = DataFrame(CSV.File(joinpath(dirname(pwd()), "baltimore-data/model_inputs/surge_area_baltimore_levee.csv")))

adf_old = DataFrame(CSV.File(joinpath(@__DIR__, "dataframes/adf_balt_v1.csv")))

#import functions to collect data 
include(joinpath(dirname(@__DIR__), "src/data_collect.jl"))
using Plots

### Intialize Model ###
#Define relevant parameters
model_evolve = CHANCE_C.model_step!
no_of_years = 50
perc_growth = 0.01
perc_move = 0.025
house_choice_mode = "flood_mem_utility"
flood_coef = -10.0^5
levee = false
breach = true
slr_scen = "medium" #Select SLR Scenario to use (choice of "low", "medium", and "high")
slr_rate = [3.03e-3,7.878e-3,2.3e-2] #Define SLR Rate of change for each scenario ( list order is "low", "medium", and "high")
breach_null = 0.45 
risk_averse = 0.3 
flood_mem = 10 
fixed_effect = 0

## CHANCE-C 2.0


new_abm = Simulator(default_df, balt_base, balt_levee, model_evolve; slr_scen = slr_scen, slr_rate = slr_rate, no_of_years = no_of_years,
pop_growth_perc = perc_growth, house_choice_mode = house_choice_mode, flood_coefficient = flood_coef, levee = false, breach = breach, breach_null = breach_null, risk_averse = risk_averse,
 flood_mem = flood_mem, fixed_effect = fixed_effect, seed = 1897)

adata = [(:population, sum, f_bgs), (:pop90, sum, f_bgs), (:population, sum, nf_bgs), (:pop90, sum, nf_bgs)]
mdata = [flood_scenario, flood_record, total_fld_area]

adf_new, mdf_new = run!(new_abm, no_of_years; adata, mdata)


#Plot results

surge_base = Plots.plot(mdf_new.time[2:51], mdf_new.flood_record[2:51], linecolor = :black, lw = 4, legend = false)
Plots.ylims!(0.5,4)
Plots.xlabel!("Time (years)")
Plots.ylabel!("Max Flood Depth (m)")

flood_pop_change = 100 .* (adf_new.sum_population_f_bgs .- adf_new.sum_pop90_f_bgs) ./ adf_new.sum_pop90_f_bgs
nf_pop_change = 100 .* (adf_new.sum_population_nf_bgs .- adf_new.sum_pop90_nf_bgs) ./ adf_new.sum_pop90_nf_bgs

plot_compare = Plots.plot(adf_new.time, flood_pop_change, lw = 4, label = "Floodplain")
Plots.plot!(adf_new.time, nf_pop_change, lw = 4, label = "Outside Floodplain")
Plots.xlabel!("Time (years)")
Plots.ylabel!("% Change in Population")

test_evo = Plots.plot(surge_base, plot_compare, layout = (2,1), dpi = 300, size = (700,600))

savefig(test_evo, joinpath(@__DIR__,"Figures/model_test_run.png"))


flood_pop_change_old = 100 .* (adf_old.sum_population_f_bgs .- adf_old.sum_pop90_f_bgs) ./ adf_old.sum_pop90_f_bgs
nf_pop_change_old = 100 .* (adf_old.sum_population_nf_bgs .- adf_old.sum_pop90_nf_bgs) ./ adf_old.sum_pop90_nf_bgs

plot_old = Plots.plot(adf_old.step, nf_pop_change_old)
Plots.plot!(adf_old.step, flood_pop_change_old)



