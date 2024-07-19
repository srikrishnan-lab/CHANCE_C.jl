### Recreate key figures from Yoon et al., 2023 ###
import Pkg
Pkg.activate(dirname(@__DIR__))
Pkg.instantiate()

include(joinpath(dirname(@__DIR__), "src/CHANCE_C.jl"))
using .CHANCE_C #add period since module is local to repository
using CSV, DataFrames


## Load input Data
balt_base = DataFrame(CSV.File(joinpath(dirname(pwd()), "baltimore-housing-data/model_inputs/surge_area_baltimore_base.csv")))
balt_levee = DataFrame(CSV.File(joinpath(dirname(pwd()), "baltimore-housing-data/model_inputs/surge_area_baltimore_levee.csv")))

#import functions to collect data 
include(joinpath(dirname(@__DIR__), "src/data_collect.jl"))
using Plots

## Set input parameters 
scenario = "Baseline"
intervention = "Baseline"
start_year = 2018
no_of_years = 50
perc_growth = 0.01
house_choice_mode = "flood_mem_utility"
flood_coefficient = -10^5
breach = true 
breach_null = 0.45  
flood_mem = 10 
fixed_effect = 0

## For Risk Aversion
ra_params = [0.3 0.7]

## Include SLR
slr_abms = [Simulator(default_df, balt_base, balt_levee; slr_scen = "high", slr_rate = [3.03e-3,7.878e-3,2.3e-2], scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years,
pop_growth_perc = perc_growth, house_choice_mode = house_choice_mode, flood_coefficient = flood_coefficient, levee = false, breach = breach, breach_null = breach_null, risk_averse = i,
 flood_mem = flood_mem, fixed_effect = fixed_effect) for i in ra_params]

adata = [(:flood_hazard, sum, BG), (:population, sum, f_bgs), (:pop90, sum, f_bgs), (:population, sum, nf_bgs), (:pop90, sum, nf_bgs)]
mdata = [flood_scenario, flood_record, total_fld_area]

adf_slr, mdf_slr = ensemblerun!(slr_abms, dummystep, CHANCE_C.model_step!, no_of_years; adata, mdata)


#Plot results
#surge level
surge_base_slr = Plots.plot(mdf_slr.step[2:51], mdf_slr.flood_record[2:51], linecolor = :black, lw = 4)
Plots.title!("Baseline with SLR")

#Cumulative remembered flood density at each time step
flood_dense_slr = Plots.plot(mdf_slr.step[2:51], mdf_slr.total_fld_area[2:51], linecolor = :blue, lw = 3)

#Pop Change
avoid_col = cgrad(:redsblues, 2, categorical = true)
flood_pop_change = 100 .* (adf_slr.sum_population_f_bgs .- adf_slr.sum_pop90_f_bgs) ./ adf_slr.sum_pop90_f_bgs
nf_pop_change = 100 .* (adf_slr.sum_population_nf_bgs .- adf_slr.sum_pop90_nf_bgs) ./ adf_slr.sum_pop90_nf_bgs

pop_avoidance_slr = Plots.plot(adf_slr.step, nf_pop_change, group = adf_slr.ensemble,
 linecolor = [avoid_col[1] avoid_col[2]], ls = :solid,
  label = ra_params, lw = 2.5)

Plots.plot!(adf_slr.step, flood_pop_change, group = adf_slr.ensemble, 
linecolor = [avoid_col[1] avoid_col[2]], ls = :dash,
 label = false, lw = 2.5)

Plots.ylims!(-10,100)
Plots.xlabel!("Model Year")
Plots.ylabel!("% Change in Population")

#create subplot
slr_results = Plots.plot(surge_base_slr, flood_dense_slr, pop_avoidance_slr, layout = (3,1), dpi = 300, size = (500,600))



### Levee Presence
## Include SLR
slr_abms_levee = [Simulator(default_df, balt_base, balt_levee; slr = true, slr_scen = [3.03e-3,7.878e-3,2.3e-2], scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years,
pop_growth_perc = perc_growth, house_choice_mode = house_choice_mode, flood_coefficient = flood_coefficient, levee = true, breach = breach, breach_null = breach_null, risk_averse = i,
 flood_mem = flood_mem, fixed_effect = fixed_effect) for i in ra_params]

adata = [(:flood_hazard, sum, BG), (:population, sum, f_bgs), (:pop90, sum, f_bgs), (:population, sum, nf_bgs), (:pop90, sum, nf_bgs)]
mdata = [flood_scenario, flood_record, total_fld_area]

adf_slr_levee, mdf_slr_levee = ensemblerun!(slr_abms_levee, dummystep, CHANCE_C.model_step!, no_of_years; adata, mdata)


#Plot results
#surge level
surge_slr_levee = Plots.plot(mdf_slr_levee.step[2:51], mdf_slr_levee.flood_record[2:51], linecolor = :black, lw = 4)
Plots.title!("Levee with SLR")

#Cumulative remembered flood density at each time step
flood_slr_levee = Plots.plot(mdf_slr_levee.step[2:51], mdf_slr_levee.total_fld_area[2:51], linecolor = :blue, lw = 3)

#Pop Change
avoid_col = cgrad(:redsblues, 2, categorical = true)
flood_pop_change = 100 .* (adf_slr_levee.sum_population_f_bgs .- adf_slr_levee.sum_pop90_f_bgs) ./ adf_slr_levee.sum_pop90_f_bgs
nf_pop_change = 100 .* (adf_slr_levee.sum_population_nf_bgs .- adf_slr_levee.sum_pop90_nf_bgs) ./ adf_slr_levee.sum_pop90_nf_bgs

pop_slr_levee = Plots.plot(adf_slr_levee.step, nf_pop_change, group = adf_slr_levee.ensemble,
 linecolor = [avoid_col[1] avoid_col[2]], ls = :solid,
  label = ra_params, lw = 2.5)

Plots.plot!(adf_slr_levee.step, flood_pop_change, group = adf_slr_levee.ensemble, 
linecolor = [avoid_col[1] avoid_col[2]], ls = :dash,
 label = false, lw = 2.5)

Plots.ylims!(-10,100)
Plots.xlabel!("Model Year")
Plots.ylabel!("% Change in Population")

#create subplot
averse_results = Plots.plot(surge_slr_levee, flood_slr_levee, pop_slr_levee, layout = (3,1), dpi = 300, size = (500,600))