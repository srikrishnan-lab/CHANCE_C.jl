### Recreate key figures from Yoon et al., 2023 ###
import Pkg
Pkg.activate(dirname(@__DIR__))
Pkg.instantiate()
<<<<<<< HEAD

include(joinpath(dirname(@__DIR__), "src/CHANCE_C.jl"))
using .CHANCE_C #add period since module is local to repository
using CSV, DataFrames
=======

include("../src/CHANCE_C.jl")
using .CHANCE_C

#Collect data during model evolution
include("../src/data_collect.jl")
>>>>>>> main


## Load input Data
balt_base = DataFrame(CSV.File(joinpath(dirname(pwd()), "baltimore-data/model_inputs/surge_area_baltimore_base.csv")))
balt_levee = DataFrame(CSV.File(joinpath(dirname(pwd()), "baltimore-data/model_inputs/surge_area_baltimore_levee.csv")))

#import functions to collect data 
include(joinpath(dirname(@__DIR__), "src/data_collect.jl"))
using Plots
using Statistics

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
fixed_effect = 0.0

## For Risk Aversion
ra_params = [0.3 0.7]

avoid_abms = [Simulator(default_df, balt_base, balt_levee; scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years,
pop_growth_perc = perc_growth, house_choice_mode = house_choice_mode, flood_coefficient = flood_coefficient, levee = false, breach = breach, breach_null = breach_null, risk_averse = i,
 flood_mem = flood_mem, fixed_effect = fixed_effect, seed = 1897) for i in ra_params]

adata = [(:population, sum, f_bgs), (:pop90, sum, f_bgs), (:population, sum, nf_bgs), (:pop90, sum, nf_bgs)]
mdata = [flood_scenario, flood_record, total_fld_area]

adf_avoid, mdf_avoid = ensemblerun!(avoid_abms, dummystep, CHANCE_C.model_step!, no_of_years; adata, mdata)


#Plot results
#surge level
surge_base = Plots.plot(mdf_avoid.step[2:51], mdf_avoid.flood_record[2:51], linecolor = :black, lw = 4)
Plots.title!("Baseline")

#Cumulative remembered flood density at each time step
flood_dense = Plots.plot(mdf_avoid.step[2:51], mdf_avoid.total_fld_area[2:51], linecolor = :blue, lw = 3)
Plots.ylims!(0,30)

#Pop Change
avoid_col = cgrad(:redsblues, 2, categorical = true)
flood_pop_change = 100 .* (adf_avoid.sum_population_f_bgs .- adf_avoid.sum_pop90_f_bgs) ./ adf_avoid.sum_pop90_f_bgs
nf_pop_change = 100 .* (adf_avoid.sum_population_nf_bgs .- adf_avoid.sum_pop90_nf_bgs) ./ adf_avoid.sum_pop90_nf_bgs

pop_avoidance = Plots.plot(adf_avoid.step, nf_pop_change, group = adf_avoid.ensemble,
 linecolor = [avoid_col[1] avoid_col[2]], ls = :solid,
  label = ra_params, lw = 2.5)

Plots.plot!(adf_avoid.step, flood_pop_change, group = adf_avoid.ensemble, 
linecolor = [avoid_col[1] avoid_col[2]], ls = :dash,
 label = false, lw = 2.5)

Plots.ylims!(-10,100)
Plots.xlabel!("Model Year")
Plots.ylabel!("% Change in Population")

#create subplot
averse_results = Plots.plot(surge_base, flood_dense, pop_avoidance, layout = (3,1), dpi = 300, size = (500,600))





### For Levee Scenario ### 

## For Risk Aversion
ra_params = [0.3 0.7]

levee_abms = [Simulator(default_df, balt_base, balt_levee; scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years,
pop_growth_perc = perc_growth, house_choice_mode = house_choice_mode, flood_coefficient = flood_coefficient, levee = true, breach = breach, breach_null = breach_null, risk_averse = i,
 flood_mem = flood_mem, fixed_effect = fixed_effect) for i in ra_params]

adata = [(:flood_hazard, sum, BG), (:population, sum, f_bgs), (:pop90, sum, f_bgs), (:population, sum, nf_bgs), (:pop90, sum, nf_bgs)]
mdata = [flood_scenario, flood_record, total_fld_area]

adf_levee, mdf_levee = ensemblerun!(levee_abms, dummystep, CHANCE_C.model_step!, no_of_years; adata, mdata)

#Plot results
#surge level
surge_levee = Plots.plot(mdf_levee.step[2:51], mdf_levee.flood_record[2:51], linecolor = :black, lw = 4)
flood_pop_change = 100 .* (adf_levee.sum_population_f_bgs .- adf_levee.sum_pop90_f_bgs) ./ adf_levee.sum_pop90_f_bgs
nf_pop_change = 100 .* (adf_levee.sum_population_nf_bgs .- adf_levee.sum_pop90_nf_bgs) ./ adf_levee.sum_pop90_nf_bgs
Plots.title!("Levee")

#Cumulative remembered flood density at each time step
flood_dense_levee = Plots.plot(mdf_levee.step[2:51], mdf_levee.total_fld_area[2:51], linecolor = :blue, lw = 3)
Plots.ylims!(0,30)
#Population change
avoid_col = cgrad(:redsblues, 2, categorical = true)
pop_avoid_levee = Plots.plot(adf_levee.step, nf_pop_change, group = adf_levee.ensemble,
 linecolor = [avoid_col[1] avoid_col[2]], ls = :solid,
  label = ra_params, lw = 2.5)

Plots.plot!(adf_levee.step, flood_pop_change, group = adf_levee.ensemble, 
linecolor = [avoid_col[1] avoid_col[2]], ls = :dash, 
label = false, lw = 2.5)

Plots.ylims!(-10,100)
Plots.xlabel!("Model Year")
Plots.ylabel!("% Change in Population")

<<<<<<< HEAD
#create subplot
levee_results = Plots.plot(surge_levee, flood_dense_levee, pop_avoid_levee, layout = (3,1), dpi = 300, size = (500,600))
=======
savefig(pop_disamenity, "test/Figures/disamenity_pop_change.png")


### For disamenity and assessing home prices### 
disamenity_coef = [0 -10^3 -10^4 -10^5 -10^6 -10^7 -10^8]

disamenity_abms = [Simulator(scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years,
 house_choice_mode = "simple_flood_utility", flood_coefficient = i) for i in disamenity_coef]
>>>>>>> main

adata = [(avg_price, sum, f_bgs), (avg_price, sum, nf_bgs), (:population, sum, f_bgs), (:population, sum, nf_bgs)]

adf_dis, _ = ensemblerun!(disamenity_abms, dummystep, model_step!, no_of_years; adata)

#Plot results
flood_avg_price = adf_dis.sum_avg_price_f_bgs ./ adf_dis.sum_population_f_bgs
nf_avg_price = adf_dis.sum_avg_price_nf_bgs ./ adf_dis.sum_population_nf_bgs

disam_col = cgrad(:blues, 7, categorical = true)
pop_disamenity = Plots.plot(adf_dis.step, nf_avg_price, group = adf_dis.ensemble,
linecolor = [disam_col[1] disam_col[2] disam_col[3] disam_col[4] disam_col[5] disam_col[6] disam_col[7]], ls = :solid,
label = disamenity_coef, lw = 2.5)

Plots.plot!(adf_dis.step, flood_avg_price, group = adf_dis.ensemble, 
linecolor = [disam_col[1] disam_col[2] disam_col[3] disam_col[4] disam_col[5] disam_col[6] disam_col[7]], ls = :dash,
 label = false, lw = 2.5)

Plots.xlabel!("Model Year")
Plots.ylabel!("Average Home Price")

savefig(pop_disamenity, "test/Figures/disamenity_home_price.png")

