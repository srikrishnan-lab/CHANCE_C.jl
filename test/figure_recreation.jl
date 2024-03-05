

### Recreate key figures from Yoon et al., 2023 ###

include("../src/model_initialization.jl")
#Import model step function
include("../src/model_evolution.jl")
#Collect data during model evolution
include("../src/data_collect.jl")

using Plots

## Set input parameters 
scenario = "Baseline"
intervention = "Baseline"
start_year = 2018
no_of_years = 80

## For avoidance
avoid_params = [0 0.1 0.25 0.50 0.75 0.85 0.95]

avoid_abms = [Simulator(scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years, house_choice_mode = "simple_avoidance_utility",
 simple_avoidance_perc = i) for i in avoid_params]

adata = [(:population, sum, f_bgs), (:pop90, sum, f_bgs), (:population, sum, nf_bgs), (:pop90, sum, nf_bgs)]

adf_avoid, _ = ensemblerun!(avoid_abms, dummystep, model_step!, no_of_years; adata)

#Plot results

flood_pop_change = 100 .* (adf_avoid.sum_population_f_bgs .- adf_avoid.sum_pop90_f_bgs) ./ adf_avoid.sum_pop90_f_bgs
nf_pop_change = 100 .* (adf_avoid.sum_population_nf_bgs .- adf_avoid.sum_pop90_nf_bgs) ./ adf_avoid.sum_pop90_nf_bgs

avoid_col = cgrad(:heat, 7, categorical = true)
pop_avoidance = Plots.plot(adf_avoid.step, nf_pop_change, group = adf_avoid.ensemble,
 linecolor = [avoid_col[1] avoid_col[2] avoid_col[3] avoid_col[4] avoid_col[5] avoid_col[6] avoid_col[7]], ls = :solid,
  label = avoid_params, lw = 2.5)

Plots.plot!(adf_avoid.step, flood_pop_change, group = adf_avoid.ensemble, 
linecolor = [avoid_col[1] avoid_col[2] avoid_col[3] avoid_col[4] avoid_col[5] avoid_col[6] avoid_col[7]], ls = :dash,
 label = false, lw = 2.5)

Plots.xlabel!("Model Year")
Plots.ylabel!("% Change in Population")

### For disamenity ### 
disamenity_coef = [0 -10^3 -10^4 -10^5 -10^6 -10^7 -10^8]

disamenity_abms = [Simulator(scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years,
 house_choice_mode = "simple_flood_utility", flood_coefficient = i) for i in disamenity_coef]

adata = [(:population, sum, f_bgs), (:pop90, sum, f_bgs), (:population, sum, nf_bgs), (:pop90, sum, nf_bgs)]

adf_dis, _ = ensemblerun!(disamenity_abms, dummystep, model_step!, no_of_years; adata)

#Plot results
flood_pop_change = 100 .* (adf_dis.sum_population_f_bgs .- adf_dis.sum_pop90_f_bgs) ./ adf_dis.sum_pop90_f_bgs
nf_pop_change = 100 .* (adf_dis.sum_population_nf_bgs .- adf_dis.sum_pop90_nf_bgs) ./ adf_dis.sum_pop90_nf_bgs

disam_col = cgrad(:blues, 7, categorical = true)
pop_disamenity = Plots.plot(adf_dis.step, nf_pop_change, group = adf_dis.ensemble,
linecolor = [disam_col[1] disam_col[2] disam_col[3] disam_col[4] disam_col[5] disam_col[6] disam_col[7]], ls = :solid,
label = disamenity_coef, lw = 2.5)

Plots.plot!(adf_dis.step, flood_pop_change, group = adf_dis.ensemble, 
linecolor = [disam_col[1] disam_col[2] disam_col[3] disam_col[4] disam_col[5] disam_col[6] disam_col[7]], ls = :dash,
 label = false, lw = 2.5)

Plots.xlabel!("Model Year")
Plots.ylabel!("% Change in Population")

savefig(pop_disamenity, "test/Figures/disamenity_pop_change.png")





