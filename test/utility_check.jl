### Check to see sensitivity of flood coefficient value on model outcomes ###
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
levee = true
breach = true 
breach_null = 0.45
r_a = 0.3
flood_mem = 10 
fixed_effect = 0
disamenity_coef = [0 -10^3 -10^4 -10^5 -10^6 -10^7 -10^8]

disamenity_abms = [Simulator(default_df, balt_base, balt_levee; scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years,
pop_growth_perc = perc_growth, house_choice_mode = house_choice_mode, flood_coefficient = i, levee = levee, breach = breach, breach_null = breach_null, risk_averse = r_a,
 flood_mem = flood_mem, fixed_effect = fixed_effect) for i in disamenity_coef]

adata = [(:population, sum, f_bgs), (:pop90, sum, f_bgs), (:population, sum, nf_bgs), (:pop90, sum, nf_bgs)]
mdata = [flood_scenario, flood_record]

        
adf_dis, mdf_dis = ensemblerun!(disamenity_abms, dummystep, model_step!, no_of_years; adata, mdata)
        
#Plot results
#Plot results
#surge level
surge_base = Plots.plot(mdf_dis.step[2:51], mdf_dis.flood_record[2:51], linecolor = :black, lw = 4)
flood_pop_change = 100 .* (adf_dis.sum_population_f_bgs .- adf_dis.sum_pop90_f_bgs) ./ adf_dis.sum_pop90_f_bgs
nf_pop_change = 100 .* (adf_dis.sum_population_nf_bgs .- adf_dis.sum_pop90_nf_bgs) ./ adf_dis.sum_pop90_nf_bgs
Plots.title!("Disamenity Coeff. at Baseline, RA = 0.3")

#Pop Change
disam_col = cgrad(:blues, 7, categorical = true)
pop_disam = Plots.plot(adf_dis.step, nf_pop_change, group = adf_dis.ensemble,
 linecolor = [disam_col[1] disam_col[2] disam_col[3] disam_col[4] disam_col[5] disam_col[6] disam_col[7]], ls = :solid,
  label = disamenity_coef, lw = 2.5)

Plots.plot!(adf_dis.step, flood_pop_change, group = adf_dis.ensemble, 
linecolor = [disam_col[1] disam_col[2] disam_col[3] disam_col[4] disam_col[5] disam_col[6] disam_col[7]], ls = :dash,
 label = false, lw = 2.5)

Plots.ylims!(-50,100)
Plots.xlabel!("Model Year")
Plots.ylabel!("% Change in Population")

#create subplot
disam_results = Plots.plot(surge_base, pop_disam, layout = (2,1), dpi = 300, size = (500,600))

        
savefig(pop_disam, "test/Figures/disamen_coef.png")