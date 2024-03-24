### See how results change if only considering block groups within the city

include("../src/CHANCE_C.jl")
using .CHANCE_C
#Collect data during model evolution
include("../src/data_collect.jl")

using Plots
using DataFrames


# Set input parameters 
scenario = "Baseline"
intervention = "Baseline"
start_year = 2018
no_of_years = 80

disamenity_coef = [0 -10^3 -10^4 -10^5 -10^6 -10^7 -10^8]

## Original Output
disamenity_abms = [Simulator(scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years,
 house_choice_mode = "simple_flood_utility", flood_coefficient = i) for i in disamenity_coef]

adata = [(:population, sum, f_bgs), (:pop90, sum, f_bgs), (:population, sum, nf_bgs), (:pop90, sum, nf_bgs)]

adf_dis, _ = ensemblerun!(disamenity_abms, CHANCE_C.dummystep, CHANCE_C.model_step!, no_of_years; adata)
#adf_dis, _ = run!(disamenity_abms[1], dummystep, model_step!, no_of_years; adata)

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

## Baltimore City Block Groups only
city_df = default_df[default_df.COUNTYFP .== 510, :]


disamenity_abms = [Simulator(df = city_df, scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years,
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
